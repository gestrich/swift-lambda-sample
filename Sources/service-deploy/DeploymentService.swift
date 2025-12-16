import sdk_cli
import sdk_aws
import sdk_github
import sdk_client
import Foundation

/// Observable service for remote AWS deployments.
/// Per layered-architecture.md, this is the @Observable service that orchestrates SDK clients.
/// Services ARE models—no separate model layer needed.
///
/// This service:
/// - Observes SDK states via `for await` loops (CDKClient, CloudFormationClient, GitHubActionsClient)
/// - Exposes cross-SDK derived state (canDeploy, overallState, etc.)
/// - Implements action methods that delegate to SDKs
/// - Contains app-specific configuration logic (e.g., DeployOptions with postgres/NAT flags)
@MainActor @Observable
public class DeploymentService {
    // MARK: - SDK State Observations

    /// CDK client state (from sdk-aws)
    public private(set) var cdkState: CDKClient.State = .idle

    /// CloudFormation client state (from sdk-aws)
    public private(set) var cloudFormationState: CloudFormationClient.State = .idle

    /// GitHub Actions client state (from sdk-github)
    public private(set) var githubState: GitHubActionsClient.State = .idle

    // MARK: - App-Specific State

    /// High-level deployment state (derived from SDK states + CloudFormation queries)
    public private(set) var deploymentState: DeploymentState = .unknown

    /// Detected infrastructure configuration from CloudFormation
    public private(set) var infrastructureConfiguration: CDKInfrastructureConfiguration?

    /// Parsed stack outputs
    public private(set) var stackOutputs: CDKStackOutputs?

    /// Deployment progress (for deploying/destroying operations)
    public private(set) var progress: DeploymentProgress = DeploymentProgress()

    /// Operation start time (for elapsed time display)
    public private(set) var operationStartTime: Date?

    // MARK: - SDK Clients

    private let cdkClient: CDKClient
    private let cloudFormationClient: CloudFormationClient
    private let githubClient: GitHubActionsClient?
    private let gitClient: GitClient
    private let cliClient: CLIClient

    // MARK: - Configuration

    private let stackName: String
    private let projectRoot: String
    private let cdkDirectory: String

    // MARK: - Cross-SDK Derived State

    /// Whether any SDK operation is currently in progress
    public var isOperationInProgress: Bool {
        cdkState.isBusy || cloudFormationState.isBusy || githubState.isBusy || deploymentState.isBusy
    }

    /// Whether a deploy operation can be started
    public var canDeploy: Bool {
        !isOperationInProgress && cdkState.canDeploy
    }

    /// Whether a destroy operation can be started
    public var canDestroy: Bool {
        !isOperationInProgress && cdkState.canDestroy && deploymentState.canDestroy
    }

    /// Whether Lambda code can be updated (via GitHub Actions)
    public var canUpdateLambda: Bool {
        !isOperationInProgress && (githubClient != nil)
    }

    /// API Gateway URL from stack outputs
    public var apiGatewayUrl: String? {
        stackOutputs?.apiGatewayUrl
    }

    /// Lambda function name from stack outputs
    public var lambdaFunctionName: String? {
        stackOutputs?.lambdaFunctionName
    }

    /// S3 bucket name from stack outputs
    public var bucketName: String? {
        stackOutputs?.bucketName
    }

    /// Whether infrastructure is deployed
    public var isDeployed: Bool {
        if case .deployed = deploymentState { return true }
        return false
    }

    /// Whether credentials have expired
    public var isCredentialExpired: Bool {
        if case .credentialExpired = deploymentState { return true }
        return false
    }

    /// Error message if in failed state
    public var errorMessage: String? {
        if case .failed(let reason) = deploymentState { return reason }
        if case .credentialExpired(let message) = deploymentState { return message }
        return nil
    }

    // MARK: - Initialization

    public init(
        projectRoot: String,
        awsConfig: AWSAuthConfiguration,
        githubConfig: GitHubActionsConfiguration? = nil,
        cdkDirectory: String = CDKStackConfiguration.defaultCDKDirectory,
        stackName: String = CDKStackConfiguration.defaultStackName,
        cliClient: CLIClient? = nil
    ) {
        self.projectRoot = projectRoot
        self.stackName = stackName
        self.cdkDirectory = cdkDirectory

        let cli = cliClient ?? CLIClient(defaultWorkingDirectory: projectRoot)
        self.cliClient = cli

        let credentialProvider = awsConfig.makeCredentialProvider()
        let fullCdkPath = "\(projectRoot)/\(cdkDirectory)"

        self.cdkClient = CDKClient(
            cdkDirectory: fullCdkPath,
            credentialProvider: credentialProvider,
            cliClient: cli
        )

        self.cloudFormationClient = CloudFormationClient(
            credentialProvider: credentialProvider,
            cliClient: cli
        )

        self.gitClient = GitClient(repoPath: projectRoot, cliClient: cli)

        if let githubConfig = githubConfig {
            self.githubClient = GitHubActionsClient(
                repoPath: projectRoot,
                config: githubConfig,
                cliClient: cli
            )
        } else {
            self.githubClient = nil
        }

        Task { await startObservingSDKStates() }
    }

    /// Convenience initializer that loads configs from disk
    public convenience init(
        projectRoot: String,
        cliClient: CLIClient? = nil
    ) {
        let awsConfig = AWSAuthConfiguration.loadConfig() ?? AWSAuthConfiguration(profileName: "default", useAWSVault: false)
        let githubConfig = GitHubConfiguration.loadConfig()?.toSDKConfiguration()

        self.init(
            projectRoot: projectRoot,
            awsConfig: awsConfig,
            githubConfig: githubConfig,
            cliClient: cliClient
        )
    }

    // MARK: - SDK State Observation

    private func startObservingSDKStates() async {
        async let cdk: Void = observeCDKState()
        async let cf: Void = observeCloudFormationState()
        async let gh: Void = observeGitHubState()
        _ = await (cdk, cf, gh)
    }

    private func observeCDKState() async {
        for await state in cdkClient.states() {
            self.cdkState = state
        }
    }

    private func observeCloudFormationState() async {
        for await state in cloudFormationClient.states() {
            self.cloudFormationState = state
        }
    }

    private func observeGitHubState() async {
        guard let client = githubClient else { return }
        for await state in client.states() {
            self.githubState = state
        }
    }

    // MARK: - Refresh Operations

    /// Refresh deployment state from AWS
    public func refresh() async {
        guard !deploymentState.isBusy else { return }

        deploymentState = .loading

        do {
            let newState = try await queryCurrentState()
            deploymentState = newState

            if newState.isBusy {
                await monitorExistingOperation()
            }
        } catch let error as DeploymentError {
            if case .credentialExpired(let message) = error {
                deploymentState = .credentialExpired(message: message)
            } else {
                deploymentState = .failed(reason: error.localizedDescription)
            }
        } catch {
            deploymentState = .failed(reason: error.localizedDescription)
        }
    }

    // MARK: - Deploy Operations

    /// App-specific deployment options
    public struct DeployOptions: Sendable {
        public let withPostgres: Bool
        public let withNATGateway: Bool
        public let requireApproval: Bool

        public init(
            withPostgres: Bool = false,
            withNATGateway: Bool = false,
            requireApproval: Bool = false
        ) {
            self.withPostgres = withPostgres
            self.withNATGateway = withNATGateway
            self.requireApproval = requireApproval
        }

        public static var minimal: DeployOptions {
            DeployOptions(withPostgres: false, withNATGateway: false)
        }

        public static var full: DeployOptions {
            DeployOptions(withPostgres: true, withNATGateway: true)
        }

        func toCDKOptions() -> CDKClient.DeployOptions {
            var context: [String: String] = [:]
            if !withPostgres {
                context["skipPostgres"] = "true"
            }
            if !withNATGateway {
                context["skipNATGateway"] = "true"
            }
            return CDKClient.DeployOptions(
                stackName: nil,
                context: context,
                requireApproval: requireApproval,
                outputsFile: nil
            )
        }
    }

    /// Deploy infrastructure with specified configuration
    public func deploy(options: DeployOptions, output: CLIOutputStream? = nil) async {
        guard canDeploy else { return }

        let operationName = options.withPostgres ? "Deploying with Database" : "Deploying"
        let startTime = Date()
        operationStartTime = startTime
        progress = DeploymentProgress()
        deploymentState = .deploying(operation: operationName, progress: progress, startTime: startTime)

        do {
            try await cdkClient.build(output: output)

            await executeDeployWithProgress(
                options: options,
                output: output,
                startTime: startTime
            )

            let finalState = try await queryCurrentState()
            deploymentState = finalState
            operationStartTime = nil
        } catch {
            deploymentState = .failed(reason: error.localizedDescription)
            operationStartTime = nil
        }
    }

    /// Update infrastructure maintaining current configuration
    public func updateInfrastructure(output: CLIOutputStream? = nil) async {
        let hasDatabase = infrastructureConfiguration?.hasDatabase ?? false
        let hasNATGateway = infrastructureConfiguration?.hasNATGateway ?? false

        let options = DeployOptions(withPostgres: hasDatabase, withNATGateway: hasNATGateway)
        await deploy(options: options, output: output)
    }

    /// Initial deployment with explicit configuration.
    /// Includes safety checks to prevent accidental database deletion.
    public func deployInit(
        options: DeployOptions,
        skipPush: Bool = false,
        output: CLIOutputStream? = nil
    ) async throws {
        guard canDeploy else {
            throw DeployError.invalidConfiguration("Cannot deploy while another operation is in progress")
        }

        let existingConfig = try? await detectConfiguration()

        if let existing = existingConfig, existing.hasDatabase && !options.withPostgres {
            throw DeployError.invalidConfiguration(
                "Cannot remove database with deploy-init. Use 'tear-down' first if you want to remove the database."
            )
        }

        await deploy(options: options, output: output)

        if case .failed(let reason) = deploymentState {
            throw DeployError.deploymentFailed(reason: reason)
        }

        try await updateLambdaCode(skipPush: skipPush)

        if options.withPostgres {
            try await initializeDatabase()
        }

        try await verifyDeployment(withPostgres: options.withPostgres)
    }

    // MARK: - Destroy Operations

    /// Destroy infrastructure
    public func destroy(output: CLIOutputStream? = nil) async {
        guard canDestroy else { return }

        let startTime = Date()
        operationStartTime = startTime
        progress = DeploymentProgress()
        deploymentState = .destroying(progress: progress, startTime: startTime)

        do {
            await executeDestroyWithProgress(output: output, startTime: startTime)

            let finalState = try await queryCurrentState()
            deploymentState = finalState
            operationStartTime = nil
        } catch {
            deploymentState = .failed(reason: error.localizedDescription)
            operationStartTime = nil
        }
    }

    // MARK: - Lambda Code Updates

    /// Update Lambda code via GitHub Actions
    public func updateLambdaCode(skipPush: Bool = false) async throws {
        guard let githubClient = githubClient else {
            throw DeployError.configurationMissing(
                file: "~/.swiftSampleDemo/github-config.json",
                hint: "Create with: {\"repository\": \"owner/repo\", \"branch\": \"dev\"}"
            )
        }

        if !skipPush {
            let hasCommitsToPush = try await gitClient.hasCommitsToPush()

            if hasCommitsToPush {
                let beforeRunId = try await githubClient.getLatestRunId()
                try await gitClient.push()

                try await githubClient.waitForNewWorkflowCompletion(
                    afterRunId: beforeRunId,
                    timeoutMinutes: 10
                )
            } else {
                print("\n✅ No commits to push")
                print("🔄 Triggering workflow to redeploy current code...\n")
                try await githubClient.triggerWorkflowAndWait(
                    workflowName: "Dev Deploy",
                    timeoutMinutes: 10
                )
            }
        } else {
            print("\n⏭️  Skipping git push (--skip-push enabled)")
            print("🔄 Triggering workflow...\n")
            try await githubClient.triggerWorkflowAndWait(
                workflowName: "Dev Deploy",
                timeoutMinutes: 10
            )
        }
    }

    // MARK: - Status Operations

    /// Comprehensive status snapshot for CLI display
    public struct ComprehensiveStatus: Sendable {
        public let deploymentState: DeploymentState
        public let gitStatus: GitStatusInfo
        public let githubStatus: GitHubStatusInfo?
        public let stackOutputs: [String: String]

        public struct GitStatusInfo: Sendable {
            public let hasUncommittedChanges: Bool
            public let hasCommitsToPush: Bool
            public let currentBranch: String
        }

        public struct GitHubStatusInfo: Sendable {
            public let repository: String
            public let branch: String
            public let latestRunStatus: String
            public let conclusion: String?
        }
    }

    /// Get comprehensive status including git, GitHub, and deployment state
    public func getComprehensiveStatus() async throws -> ComprehensiveStatus {
        if case .unknown = deploymentState {
            await refresh()
        }

        let hasUncommitted = try await gitClient.hasUncommittedChanges()
        let hasCommitsToPush = try await gitClient.hasCommitsToPush()
        let currentBranch = try await gitClient.getCurrentBranch()

        let gitStatus = ComprehensiveStatus.GitStatusInfo(
            hasUncommittedChanges: hasUncommitted,
            hasCommitsToPush: hasCommitsToPush,
            currentBranch: currentBranch
        )

        var githubStatus: ComprehensiveStatus.GitHubStatusInfo? = nil
        if let githubClient = githubClient {
            do {
                let (status, conclusion) = try await githubClient.getLatestRunStatus()
                githubStatus = ComprehensiveStatus.GitHubStatusInfo(
                    repository: githubClient.repository,
                    branch: githubClient.branch,
                    latestRunStatus: status,
                    conclusion: conclusion
                )
            } catch {
                // GitHub status unavailable
            }
        }

        return ComprehensiveStatus(
            deploymentState: deploymentState,
            gitStatus: gitStatus,
            githubStatus: githubStatus,
            stackOutputs: stackOutputs?.allOutputs ?? [:]
        )
    }

    // MARK: - Testing Operations

    /// Test remote Lambda endpoints
    public func testEndpoints() async throws {
        guard let apiUrl = apiGatewayUrl else {
            throw DeployError.testFailed(message: "Remote endpoint not configured. Deploy first.")
        }

        print("\n🧪 Testing remote Lambda at \(apiUrl)...")
        print("")

        let client = APIClient(baseURL: apiUrl, serviceName: "Remote (API Gateway)")

        print("→ Testing file upload...")
        let testContent = "Hello from remote test!"
        guard let testData = testContent.data(using: .utf8) else {
            throw DeployError.testFailed(message: "Failed to create test data")
        }

        let uploadResponse = try await client.uploadFile(fileName: "test-remote.txt", data: testData)
        if uploadResponse.contains("File uploaded: test-remote.txt") {
            print("  ✅ File upload test passed")
        } else {
            print("  ❌ File upload test failed: \(uploadResponse)")
            throw DeployError.testFailed(message: "File upload endpoint test failed")
        }

        print("")

        print("→ Testing list files...")
        let fileList = try await client.listFiles()
        if fileList.contains("test-remote.txt") {
            print("  ✅ List files test passed (found \(fileList.count) files)")
        } else {
            print("  ❌ List files test failed: \(fileList)")
            throw DeployError.testFailed(message: "List files endpoint test failed")
        }

        print("")
        print("✅ All remote Lambda tests passed!")
    }

    // MARK: - Private: Infrastructure Detection

    /// Detect the current infrastructure configuration from CloudFormation resources
    private func detectConfiguration() async throws -> CDKInfrastructureConfiguration? {
        do {
            let resources = try await cloudFormationClient.describeStackResources(name: stackName)
            let config = parseConfiguration(from: resources)
            infrastructureConfiguration = config
            return config
        } catch let error as CloudFormationError {
            if case .commandFailed(_, _, let output) = error,
               output.contains("does not exist") {
                infrastructureConfiguration = nil
                return nil
            }
            throw error
        }
    }

    /// Parse infrastructure configuration from CloudFormation resources
    private func parseConfiguration(from resources: [CloudFormationStackResource]) -> CDKInfrastructureConfiguration {
        CDKInfrastructureConfiguration(
            hasDatabase: resources.contains {
                $0.logicalResourceId.contains("Database") &&
                $0.resourceType.contains("RDS")
            },
            hasNATGateway: resources.contains {
                $0.resourceType == "AWS::EC2::NatGateway"
            },
            hasVPC: resources.contains {
                $0.resourceType == "AWS::EC2::VPC"
            }
        )
    }

    // MARK: - Private: State Query

    private func queryCurrentState() async throws -> DeploymentState {
        do {
            let stackStatus = try await cloudFormationClient.getStackStatus(name: stackName)

            switch stackStatus {
            case StackStatus.createComplete,
                 StackStatus.updateComplete:
                let config = try await detectConfiguration()
                let outputs = try await getStackOutputs()
                infrastructureConfiguration = config
                stackOutputs = outputs
                return .deployed(outputs: outputs.allOutputs)

            case StackStatus.createInProgress,
                 StackStatus.updateInProgress,
                 StackStatus.updateCompleteCleanupInProgress:
                let startTime = await getOperationStartTime() ?? Date()
                return .deploying(operation: "Updating", progress: DeploymentProgress(), startTime: startTime)

            case StackStatus.deleteInProgress:
                let startTime = await getOperationStartTime() ?? Date()
                return .destroying(progress: DeploymentProgress(), startTime: startTime)

            case StackStatus.createFailed,
                 StackStatus.updateFailed,
                 StackStatus.rollbackComplete,
                 StackStatus.rollbackFailed,
                 StackStatus.deleteFailed:
                return .failed(reason: stackStatus)

            default:
                let config = try await detectConfiguration()
                let outputs = try await getStackOutputs()
                infrastructureConfiguration = config
                stackOutputs = outputs
                return .deployed(outputs: outputs.allOutputs)
            }
        } catch {
            let errorMessage = error.localizedDescription

            if DeploymentError.isCredentialError(errorMessage) {
                throw DeploymentError.credentialExpired(message: errorMessage)
            } else if DeploymentError.isStackNotFoundError(errorMessage) {
                infrastructureConfiguration = nil
                stackOutputs = nil
                return .notDeployed
            } else {
                throw DeploymentError.unknown(message: errorMessage)
            }
        }
    }

    private func getStackOutputs() async throws -> CDKStackOutputs {
        let outputs = try await cloudFormationClient.getStackOutputs(name: stackName)
        return CDKStackOutputs.from(outputs)
    }

    private func getStackEvents(limit: Int = 50) async throws -> [CloudFormationStackEvent] {
        try await cloudFormationClient.getStackEvents(name: stackName, limit: limit)
    }

    private func getOperationStartTime() async -> Date? {
        guard let events = try? await getStackEvents() else { return nil }

        return events
            .filter { $0.logicalResourceId == stackName && $0.resourceStatus.contains("IN_PROGRESS") }
            .map { $0.timestamp }
            .min()
    }

    // MARK: - Private: Deploy/Destroy With Progress

    private func executeDeployWithProgress(
        options: DeployOptions,
        output: CLIOutputStream?,
        startTime: Date
    ) async {
        let parser = CDKOutputParser()
        let accumulator = CDKProgressAccumulator()

        let parsingTask: Task<Void, Never>?
        if let output = output {
            parsingTask = Task {
                let stream = await output.makeStream()
                for await item in stream {
                    guard !Task.isCancelled else { break }

                    let text: String
                    switch item {
                    case .stdout(_, let t), .stderr(_, let t):
                        text = t
                    default:
                        continue
                    }

                    for line in text.components(separatedBy: .newlines) {
                        if let event = parser.parse(line) {
                            accumulator.update(with: event)
                            let newProgress = accumulator.snapshot().toDeploymentProgress()
                            await MainActor.run {
                                self.progress = newProgress
                                self.deploymentState = .deploying(operation: "Deploying", progress: newProgress, startTime: startTime)
                            }
                        }
                    }
                }
            }
        } else {
            parsingTask = nil
        }

        do {
            try await cdkClient.deploy(options: options.toCDKOptions(), output: output)
        } catch {
            parsingTask?.cancel()
            deploymentState = .failed(reason: error.localizedDescription)
            return
        }

        parsingTask?.cancel()
    }

    private func executeDestroyWithProgress(output: CLIOutputStream?, startTime: Date) async {
        let parser = CDKOutputParser()
        let accumulator = CDKProgressAccumulator()

        let parsingTask: Task<Void, Never>?
        if let output = output {
            parsingTask = Task {
                let stream = await output.makeStream()
                for await item in stream {
                    guard !Task.isCancelled else { break }

                    let text: String
                    switch item {
                    case .stdout(_, let t), .stderr(_, let t):
                        text = t
                    default:
                        continue
                    }

                    for line in text.components(separatedBy: .newlines) {
                        if let event = parser.parse(line) {
                            accumulator.update(with: event)
                            let newProgress = accumulator.snapshot().toDeploymentProgress()
                            await MainActor.run {
                                self.progress = newProgress
                                self.deploymentState = .destroying(progress: newProgress, startTime: startTime)
                            }
                        }
                    }
                }
            }
        } else {
            parsingTask = nil
        }

        do {
            let destroyOptions = CDKClient.DestroyOptions(stackName: nil, force: true)
            try await cdkClient.destroy(options: destroyOptions, output: output)
        } catch {
            parsingTask?.cancel()
            deploymentState = .failed(reason: error.localizedDescription)
            return
        }

        parsingTask?.cancel()
    }

    private func monitorExistingOperation() async {
        var pollCount = 0
        let startTime = operationStartTime ?? Date()

        while !Task.isCancelled {
            pollCount += 1

            do {
                let events = try await getStackEvents()
                let newProgress = DeploymentProgress.from(
                    events: events,
                    since: nil,
                    pollCount: pollCount
                )
                progress = newProgress

                if case .deploying(let op, _, _) = deploymentState {
                    deploymentState = .deploying(operation: op, progress: newProgress, startTime: startTime)
                } else if case .destroying = deploymentState {
                    deploymentState = .destroying(progress: newProgress, startTime: startTime)
                }

                let status = try await cloudFormationClient.getStackStatus(name: stackName)

                if !StackStatus.isInProgress(status) {
                    let finalState = try await queryCurrentState()
                    deploymentState = finalState
                    operationStartTime = nil
                    return
                }
            } catch {
                // Continue polling
            }

            do {
                try await Task.sleep(for: .seconds(2))
            } catch {
                break
            }
        }
    }

    // MARK: - Private: Database Initialization

    private func initializeDatabase() async throws {
        guard let apiUrl = apiGatewayUrl else {
            throw DeployError.deploymentFailed(reason: "Could not find ApiGatewayUrl in stack outputs")
        }

        print("\n🗄️  Initializing database...")
        print("  → POST \(apiUrl)api/database")

        let curlCommand = Curl.Request.post(url: "\(apiUrl)api/database", silent: true)
        let result = try await cliClient.executeForResult(curlCommand, printCommand: false)

        guard result.isSuccess else {
            throw CLIClientError.executionFailed(
                command: curlCommand.commandString,
                exitCode: result.exitCode,
                output: result.output
            )
        }

        let response = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        print("  Response: \(response)")

        if !response.contains("Database Initialized") {
            throw DeployError.deploymentFailed(reason: "Unexpected database init response: \(response)")
        }

        print("  ✓ Database initialized successfully")
    }

    private func verifyDeployment(withPostgres: Bool) async throws {
        guard let apiUrl = apiGatewayUrl else {
            throw DeployError.deploymentFailed(reason: "Could not find ApiGatewayUrl in stack outputs")
        }

        print("\n🧪 Verifying deployment...")
        print("  Testing health endpoint...")
        print("  → GET \(apiUrl)api/health")

        let healthCommand = Curl.Request.get(url: "\(apiUrl)api/health", silent: true)
        let testResult = try await cliClient.executeForResult(healthCommand, printCommand: false)

        guard testResult.isSuccess else {
            throw CLIClientError.executionFailed(
                command: healthCommand.commandString,
                exitCode: testResult.exitCode,
                output: testResult.output
            )
        }

        let response = testResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        print("  Response: \(response)")

        if !response.contains("healthy") {
            throw DeployError.deploymentFailed(reason: "Unexpected API response: \(response)")
        }

        print("  ✓ API Gateway working")
        print("  ✓ Lambda function executing")
        print("  ✓ Health check passed")

        if withPostgres {
            print("\n  Testing database endpoints...")
            print("  → GET \(apiUrl)api/users")

            let usersCommand = Curl.Request.get(url: "\(apiUrl)api/users", silent: true)
            let usersResult = try await cliClient.executeForResult(usersCommand, printCommand: false)

            guard usersResult.isSuccess else {
                throw CLIClientError.executionFailed(
                    command: usersCommand.commandString,
                    exitCode: usersResult.exitCode,
                    output: usersResult.output
                )
            }

            let usersResponse = usersResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            print("  Response: \(usersResponse)")

            if let data = usersResponse.data(using: .utf8),
               let _ = try? JSONSerialization.jsonObject(with: data) {
                print("  ✓ Database connection working")
                print("  ✓ User endpoint responding")
            } else {
                throw DeployError.deploymentFailed(reason: "Invalid JSON response from users endpoint: \(usersResponse)")
            }
        }

        print("\n✅ Deployment verification passed!")
    }
}
