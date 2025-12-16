import sdk_cli
import sdk_aws
import sdk_client
import Foundation

/// Stateful service for remote AWS deployments.
/// Owns deployment state and exposes via AsyncStream per MV architecture.
///
/// This service follows the MV_Model_Service_State.md pattern:
/// - Service owns state as unified enum
/// - Exposes state via `AsyncStream<State>`
/// - Features/Models observe the stream
///
/// Combines:
/// - Generic CloudFormation queries (via CloudFormationClient from sdk-aws)
/// - App-specific CDK operations (via SwiftLambdaCDKService)
/// - App-specific infrastructure detection (via SwiftLambdaInfrastructureService)
/// - Git/GitHub operations for Lambda code deployment
public actor RemoteDeploymentService {

    // MARK: - State Definition

    /// High-level infrastructure state exposed to observers.
    /// App-specific state that includes typed configuration and outputs.
    public enum State: Sendable, Equatable {
        case unknown
        case loading
        case notDeployed
        case deployed(configuration: CDKInfrastructureConfiguration, outputs: CDKStackOutputs)
        case deploying(operation: String, progress: DeploymentProgress, startTime: Date)
        case destroying(progress: DeploymentProgress, startTime: Date)
        case failed(reason: String)
        case credentialExpired(message: String)

        public var isBusy: Bool {
            switch self {
            case .loading, .deploying, .destroying:
                return true
            default:
                return false
            }
        }

        public var canDeploy: Bool {
            switch self {
            case .loading, .deploying, .destroying:
                return false
            default:
                return true
            }
        }

        public var canDestroy: Bool {
            switch self {
            case .deployed:
                return true
            default:
                return false
            }
        }

        public var configuration: CDKInfrastructureConfiguration {
            if case .deployed(let config, _) = self {
                return config
            }
            return CDKInfrastructureConfiguration()
        }

        public var outputs: CDKStackOutputs {
            if case .deployed(_, let outputs) = self {
                return outputs
            }
            return CDKStackOutputs()
        }

        public var progress: DeploymentProgress {
            switch self {
            case .deploying(_, let progress, _), .destroying(let progress, _):
                return progress
            default:
                return DeploymentProgress()
            }
        }

        public var operationStartTime: Date? {
            switch self {
            case .deploying(_, _, let startTime), .destroying(_, let startTime):
                return startTime
            default:
                return nil
            }
        }
    }

    // MARK: - Private State

    private var state: State = .unknown
    private var continuations: [UUID: AsyncStream<State>.Continuation] = [:]
    private let stackName: String
    private let projectRoot: String
    private let cliClient: CLIClient

    // MARK: - Dependencies (stateless)

    private let cdkService: SwiftLambdaCDKService
    private let infrastructureService: SwiftLambdaInfrastructureService

    // MARK: - Initialization

    /// Full initializer with explicit CLIClient (for injection/testing)
    public init(
        projectRoot: String,
        awsConfig: AWSAuthConfiguration,
        cdkDirectory: String = CDKStackConfiguration.defaultCDKDirectory,
        stackName: String = CDKStackConfiguration.defaultStackName,
        cliClient: CLIClient
    ) {
        self.stackName = stackName
        self.projectRoot = projectRoot
        self.cliClient = cliClient

        self.cdkService = SwiftLambdaCDKService(
            projectRoot: projectRoot,
            awsConfig: awsConfig,
            cdkDirectory: cdkDirectory,
            stackName: stackName,
            cliClient: cliClient
        )

        self.infrastructureService = SwiftLambdaInfrastructureService(
            awsConfig: awsConfig,
            cliClient: cliClient,
            stackName: stackName
        )
    }

    /// Convenience initializer that creates its own CLIClient
    public init(
        projectRoot: String,
        awsConfig: AWSAuthConfiguration,
        cdkDirectory: String = CDKStackConfiguration.defaultCDKDirectory,
        stackName: String = CDKStackConfiguration.defaultStackName
    ) {
        let cliClient = CLIClient(defaultWorkingDirectory: projectRoot)
        self.init(
            projectRoot: projectRoot,
            awsConfig: awsConfig,
            cdkDirectory: cdkDirectory,
            stackName: stackName,
            cliClient: cliClient
        )
    }

    // MARK: - State Observation

    /// Stream of state changes. Immediately yields current state upon subscription.
    /// If state is `.unknown`, automatically triggers a refresh.
    public func states() -> AsyncStream<State> {
        if state == .unknown {
            Task { await refresh() }
        }

        return AsyncStream { continuation in
            let id = UUID()
            self.continuations[id] = continuation
            continuation.yield(self.state)

            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeContinuation(id) }
            }
        }
    }

    private func removeContinuation(_ id: UUID) {
        continuations.removeValue(forKey: id)
    }

    private func publish(_ newState: State) {
        state = newState
        for continuation in continuations.values {
            continuation.yield(newState)
        }
    }

    // MARK: - Public Operations

    /// Refresh state from AWS
    public func refresh() async {
        guard !state.isBusy else { return }

        publish(.loading)

        do {
            let newState = try await queryCurrentState()
            publish(newState)

            if newState.isBusy {
                await monitorExistingOperation()
            }
        } catch DeploymentError.credentialExpired(let message) {
            publish(.credentialExpired(message: message))
        } catch {
            publish(.failed(reason: error.localizedDescription))
        }
    }

    /// Deploy infrastructure with specified configuration
    public func deploy(withPostgres: Bool, withNATGateway: Bool, output: CLIOutputStream? = nil) async {
        guard state.canDeploy else { return }

        let operationName = withPostgres ? "Deploying with Database" : "Deploying"
        let startTime = Date()
        publish(.deploying(operation: operationName, progress: DeploymentProgress(), startTime: startTime))

        do {
            try await cdkService.build(output: output)

            await executeDeployWithProgress(
                withPostgres: withPostgres,
                withNATGateway: withNATGateway,
                output: output,
                startTime: startTime
            )

            let finalState = try await queryCurrentState()
            publish(finalState)
        } catch {
            publish(.failed(reason: error.localizedDescription))
        }
    }

    /// Update infrastructure maintaining current configuration
    public func updateInfrastructure(output: CLIOutputStream? = nil) async {
        let hasDatabase = state.configuration.hasDatabase
        let hasNATGateway = state.configuration.hasNATGateway

        await deploy(withPostgres: hasDatabase, withNATGateway: hasNATGateway, output: output)
    }

    /// Destroy infrastructure
    public func destroy(output: CLIOutputStream? = nil) async {
        guard state.canDestroy else { return }

        let startTime = Date()
        publish(.destroying(progress: DeploymentProgress(), startTime: startTime))

        do {
            await executeDestroyWithProgress(output: output, startTime: startTime)

            let finalState = try await queryCurrentState()
            publish(finalState)
        } catch {
            publish(.failed(reason: error.localizedDescription))
        }
    }

    // MARK: - Initial Deployment (with safety checks)

    /// Initial deployment with explicit configuration.
    /// Includes safety checks to prevent accidental database deletion.
    public func deployInit(
        withPostgres: Bool,
        withNATGateway: Bool,
        skipPush: Bool = false,
        output: CLIOutputStream? = nil
    ) async throws {
        guard state.canDeploy else {
            throw DeployError.invalidConfiguration("Cannot deploy while another operation is in progress")
        }

        // Check existing state for safety
        let existingConfig = try? await queryConfiguration()

        if let existing = existingConfig, existing.hasDatabase && !withPostgres {
            throw DeployError.invalidConfiguration(
                "Cannot remove database with deploy-init. Use 'tear-down' first if you want to remove the database."
            )
        }

        // Deploy infrastructure
        await deploy(withPostgres: withPostgres, withNATGateway: withNATGateway, output: output)

        // Check if deploy failed
        if case .failed(let reason) = state {
            throw DeployError.deploymentFailed(reason: reason)
        }

        // Update Lambda code via GitHub Actions
        try await updateLambdaCode(skipPush: skipPush)

        // Initialize database if needed
        if withPostgres {
            try await initializeDatabase()
        }

        // Verify deployment
        try await verifyDeployment(withPostgres: withPostgres)
    }

    // MARK: - Lambda Code Updates (via GitHub Actions)

    /// Update Lambda code via GitHub Actions
    public func updateLambdaCode(skipPush: Bool = false) async throws {
        guard let config = GitHubConfiguration.loadConfig() else {
            throw DeployError.configurationMissing(
                file: GitHubConfiguration.configPath,
                hint: "Create with: {\"repository\": \"owner/repo\", \"branch\": \"dev\"}"
            )
        }

        let gitService = GitClient(repoPath: projectRoot, cliClient: cliClient)
        let actionsService = makeGitHubActionsClient(repoPath: projectRoot, config: config, cliClient: cliClient)

        if !skipPush {
            let hasCommitsToPush = try await gitService.hasCommitsToPush()

            if hasCommitsToPush {
                let beforeRunId = try await actionsService.getLatestRunId()
                try await gitService.push()

                try await actionsService.waitForNewWorkflowCompletion(
                    afterRunId: beforeRunId,
                    timeoutMinutes: 10
                )
            } else {
                print("\n✅ No commits to push")
                print("🔄 Triggering workflow to redeploy current code...\n")
                try await actionsService.triggerWorkflowAndWait(
                    workflowName: "Dev Deploy",
                    timeoutMinutes: 10
                )
            }
        } else {
            print("\n⏭️  Skipping git push (--skip-push enabled)")
            print("🔄 Triggering workflow...\n")
            try await actionsService.triggerWorkflowAndWait(
                workflowName: "Dev Deploy",
                timeoutMinutes: 10
            )
        }
    }

    // MARK: - Status Operations (for CLI)

    /// Comprehensive status snapshot for CLI display
    public struct ComprehensiveStatus: Sendable {
        public let deploymentState: State
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
        // Refresh deployment state if unknown
        if state == .unknown {
            await refresh()
        }

        let gitService = GitClient(repoPath: projectRoot, cliClient: cliClient)

        // Get git status
        let hasUncommitted = try await gitService.hasUncommittedChanges()
        let hasCommitsToPush = try await gitService.hasCommitsToPush()
        let currentBranch = try await gitService.getCurrentBranch()

        let gitStatus = ComprehensiveStatus.GitStatusInfo(
            hasUncommittedChanges: hasUncommitted,
            hasCommitsToPush: hasCommitsToPush,
            currentBranch: currentBranch
        )

        // Get GitHub status if configured
        var githubStatus: ComprehensiveStatus.GitHubStatusInfo? = nil
        if let githubConfig = GitHubConfiguration.loadConfig() {
            let actionsService = makeGitHubActionsClient(repoPath: projectRoot, config: githubConfig, cliClient: cliClient)
            do {
                let (status, conclusion) = try await actionsService.getLatestRunStatus()
                githubStatus = ComprehensiveStatus.GitHubStatusInfo(
                    repository: githubConfig.repository,
                    branch: githubConfig.branch,
                    latestRunStatus: status,
                    conclusion: conclusion
                )
            } catch {
                // GitHub status unavailable
            }
        }

        // Get stack outputs
        let stackOutputs: [String: String]
        do {
            stackOutputs = try await getStackOutputs()
        } catch {
            stackOutputs = [:]
        }

        return ComprehensiveStatus(
            deploymentState: state,
            gitStatus: gitStatus,
            githubStatus: githubStatus,
            stackOutputs: stackOutputs
        )
    }

    // MARK: - Public Accessors

    /// Get current state synchronously (does not trigger refresh)
    public func getCurrentState() -> State {
        state
    }

    /// Get API Gateway URL from current state
    public func getAPIGatewayURL() -> String? {
        state.outputs.apiGatewayUrl
    }

    /// Get raw stack outputs
    public func getRawStackOutputs() async throws -> [String: String] {
        try await getStackOutputs()
    }

    // MARK: - Testing Operations

    /// Test remote Lambda endpoints
    public func testEndpoints() async throws {
        guard let apiUrl = state.outputs.apiGatewayUrl else {
            throw DeployError.testFailed(message: "Remote endpoint not configured. Deploy first.")
        }

        print("\n🧪 Testing remote Lambda at \(apiUrl)...")
        print("")

        let client = await APIClient(baseURL: apiUrl, serviceName: "Remote (API Gateway)")

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

    // MARK: - Private: Database Initialization

    private func initializeDatabase() async throws {
        guard let apiUrl = state.outputs.apiGatewayUrl else {
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
        guard let apiUrl = state.outputs.apiGatewayUrl else {
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

    // MARK: - Query Operations (Internal)

    private func getStackStatus() async throws -> String {
        try await infrastructureService.getStackStatus()
    }

    private func getStackOutputs() async throws -> [String: String] {
        try await infrastructureService.getRawStackOutputs()
    }

    private func queryConfiguration() async throws -> CDKInfrastructureConfiguration {
        guard let config = try await infrastructureService.detectConfiguration() else {
            return CDKInfrastructureConfiguration()
        }
        return config
    }

    private func getStackEvents(limit: Int = 50) async throws -> [CloudFormationStackEvent] {
        try await infrastructureService.getStackEvents(limit: limit)
    }

    /// Get the start time of the current operation from CloudFormation events.
    /// Returns the earliest IN_PROGRESS timestamp for the stack resource itself.
    private func getOperationStartTime() async -> Date? {
        guard let events = try? await getStackEvents() else { return nil }

        return events
            .filter { $0.logicalResourceId == stackName && $0.resourceStatus.contains("IN_PROGRESS") }
            .map { $0.timestamp }
            .min()
    }

    // MARK: - CDK Operations (Internal)

    private func executeDeploy(
        withPostgres: Bool,
        withNATGateway: Bool,
        output: CLIOutputStream? = nil
    ) async throws {
        let options = SwiftLambdaCDKService.DeployOptions(
            withPostgres: withPostgres,
            withNATGateway: withNATGateway,
            requireApproval: false
        )
        try await cdkService.deploy(options: options, output: output)
    }

    private func executeDestroy(output: CLIOutputStream? = nil) async throws {
        try await cdkService.destroy(force: true, output: output)
    }

    // MARK: - State Query

    private func queryCurrentState() async throws -> State {
        do {
            let stackStatus = try await getStackStatus()

            switch stackStatus {
            case StackStatus.createComplete,
                 StackStatus.updateComplete:
                let configuration = try await queryConfiguration()
                let outputs = CDKStackOutputs.from(try await getStackOutputs())
                return .deployed(configuration: configuration, outputs: outputs)

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
                let configuration = try await queryConfiguration()
                let outputs = CDKStackOutputs.from(try await getStackOutputs())
                return .deployed(configuration: configuration, outputs: outputs)
            }
        } catch {
            let errorMessage = error.localizedDescription

            if DeploymentError.isCredentialError(errorMessage) {
                throw DeploymentError.credentialExpired(message: errorMessage)
            } else if DeploymentError.isStackNotFoundError(errorMessage) {
                return .notDeployed
            } else {
                throw DeploymentError.unknown(message: errorMessage)
            }
        }
    }

    // MARK: - Progress Tracking

    private func executeDeployWithProgress(
        withPostgres: Bool,
        withNATGateway: Bool,
        output: CLIOutputStream?,
        startTime: Date
    ) async {
        let parser = sdk_aws.CDKOutputParser()
        let accumulator = sdk_aws.CDKProgressAccumulator()

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
                            let progress = accumulator.snapshot().toDeploymentProgress()
                            self.publish(.deploying(operation: "Deploying", progress: progress, startTime: startTime))
                        }
                    }
                }
            }
        } else {
            parsingTask = nil
        }

        do {
            try await executeDeploy(withPostgres: withPostgres, withNATGateway: withNATGateway, output: output)
        } catch {
            parsingTask?.cancel()
            publish(.failed(reason: error.localizedDescription))
            return
        }

        parsingTask?.cancel()
    }

    private func executeDestroyWithProgress(output: CLIOutputStream?, startTime: Date) async {
        let parser = sdk_aws.CDKOutputParser()
        let accumulator = sdk_aws.CDKProgressAccumulator()

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
                            let progress = accumulator.snapshot().toDeploymentProgress()
                            self.publish(.destroying(progress: progress, startTime: startTime))
                        }
                    }
                }
            }
        } else {
            parsingTask = nil
        }

        do {
            try await executeDestroy(output: output)
        } catch {
            parsingTask?.cancel()
            publish(.failed(reason: error.localizedDescription))
            return
        }

        parsingTask?.cancel()
    }

    private func monitorExistingOperation() async {
        var pollCount = 0
        let startTime = state.operationStartTime ?? Date()

        while !Task.isCancelled {
            pollCount += 1

            do {
                let events = try await getStackEvents()
                let progress = DeploymentProgress.from(
                    events: events,
                    since: nil,
                    pollCount: pollCount
                )

                if case .deploying(let op, _, _) = state {
                    publish(.deploying(operation: op, progress: progress, startTime: startTime))
                } else if case .destroying = state {
                    publish(.destroying(progress: progress, startTime: startTime))
                }

                let status = try await getStackStatus()

                if !StackStatus.isInProgress(status) {
                    let finalState = try await queryCurrentState()
                    publish(finalState)
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
}
