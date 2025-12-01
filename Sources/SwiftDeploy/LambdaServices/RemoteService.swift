import Client
import Combine
import Foundation
import Observation

/// Detected state of deployed infrastructure
public struct DeployedState: Sendable {
    let hasDatabase: Bool
    let hasNATGateway: Bool
    let hasVPC: Bool
}

/// Service for remote AWS Lambda deployment and management
/// Conforms to LambdaService for consistency with local services
/// Start/stop lifecycle operations are no-ops since remote services are managed by AWS
@MainActor
@Observable
public class RemoteService: LambdaService {
    private let cdkService: CDKService
    private let awsService: AWSCLIService
    private let cliService: CLIService
    private let projectRoot: String

    private var _endpoint: String? {
        didSet {
            if let endpoint = _endpoint {
                UserDefaults.standard.set(endpoint, forKey: Self.endpointKey)
            }
        }
    }

    private static let endpointKey = "remoteService.endpoint"

    // MARK: - Combine Publishers

    private let statusSubject = CurrentValueSubject<DeploymentStatus, Never>(.stopped)
    private let isLoadingStatusSubject = CurrentValueSubject<Bool, Never>(false)

    public var statusPublisher: AnyPublisher<DeploymentStatus, Never> {
        statusSubject.eraseToAnyPublisher()
    }

    public var isLoadingStatusPublisher: AnyPublisher<Bool, Never> {
        isLoadingStatusSubject.eraseToAnyPublisher()
    }

    // MARK: - Unified Output

    public let unifiedOutput = UnifiedOutputState()

    // MARK: - Build State

    public let buildState = BuildState()

    // MARK: - Lambda State

    public let lambdaState = LambdaState()

    // MARK: - GitHub Service (lazy initialized)

    private var _githubService: GitHubService?

    /// Get or create the GitHub service for this repository
    public func getGitHubService() async throws -> GitHubService {
        if let existing = _githubService {
            return existing
        }

        let gitService = GitService(repoPath: projectRoot)
        let repoInfo = try await gitService.getRepoInfo()
        let service = GitHubService(repoPath: projectRoot, owner: repoInfo.owner, repo: repoInfo.name)
        _githubService = service
        return service
    }

    /// Access to GitHub service (nil until first refresh)
    public var githubService: GitHubService? {
        _githubService
    }

    // MARK: - LambdaService Protocol Properties

    public static let persistenceKey = "remote"

    public var port: Int { 443 }

    public var endpoint: String {
        _endpoint ?? "https://<not-configured>"
    }

    public var endpointLabel: String { "API Gateway URL" }

    public var endpointHelpText: String {
        "URL is automatically fetched when refreshing status"
    }

    public var apiClient: APIClient {
        APIClient(baseURL: endpoint)
    }

    // MARK: - Initialization

    public init(
        projectRoot: String,
        awsConfig: AWSAuthConfiguration,
        cdkDirectory: String = "cdk"
    ) {
        self.projectRoot = projectRoot
        self.cdkService = CDKService(
            cdkDirectory: "\(projectRoot)/\(cdkDirectory)",
            awsConfig: awsConfig
        )
        self.awsService = AWSCLIService(awsConfig: awsConfig)
        self.cliService = CLIService.shared

        // Load persisted endpoint
        self._endpoint = UserDefaults.standard.string(forKey: Self.endpointKey)
    }

    /// Convenience initializer for workingDirectory-based initialization (matches local services)
    /// Requires AWS config to be available in ~/.swiftSampleDemo/aws-config.json
    public convenience init(workingDirectory: String) {
        let awsConfig = AWSAuthConfiguration.loadConfig() ?? AWSAuthConfiguration(profileName: "default", useAWSVault: false)
        self.init(projectRoot: workingDirectory, awsConfig: awsConfig)
    }

    /// Set the endpoint URL manually (persisted to UserDefaults)
    public func setEndpoint(_ url: String) {
        _endpoint = url
    }

    public var isConfigured: Bool {
        _endpoint != nil
    }

    /// Fetch and cache endpoint from CDK stack
    public func fetchEndpoint() async throws {
        let outputs = try await awsService.getStackOutputs(name: "SwiftLambdaSampleStack")
        if let apiUrl = outputs["ApiGatewayUrl"] {
            _endpoint = apiUrl
        }
    }

    // MARK: - LambdaService Protocol: Build

    /// Build is handled via CI/CD pipeline (GitHub Actions), updating buildState
    public func build(clean: Bool = false) async throws {
        buildState.startBuild()
        buildState.appendOutput("ℹ️  Remote Lambda is built via CI/CD pipeline\n")
        buildState.appendOutput("   Use 'aws update-lambda' to deploy code changes\n")
        buildState.markSuccess()
    }

    /// Check if Lambda is deployed (stack exists with endpoint)
    public func isLambdaBuilt() -> Bool {
        return _endpoint != nil
    }

    /// Delete build is not applicable for remote - just clears state
    public func deleteBuild() async throws {
        buildState.clear()
    }

    // MARK: - LambdaService Protocol: Lifecycle

    /// Start is not applicable for remote services - Lambda runs on-demand
    public func startLambda() async throws {
        lambdaState.appendOutput("ℹ️  Remote Lambda is managed by AWS\n")
        lambdaState.appendOutput("   Lambda runs automatically when invoked via API Gateway\n")
        // Remote Lambda is always "running" when stack is deployed
        if _endpoint != nil {
            lambdaState.setRunning()
        }
    }

    /// Stop is not applicable for remote services
    public func stopLambda() async throws {
        lambdaState.appendOutput("ℹ️  Remote Lambda is managed by AWS\n")
        lambdaState.appendOutput("   Use 'aws tear-down' to remove all infrastructure\n")
    }

    /// Start with services is not applicable for remote
    public func startWithServices() async throws {
        lambdaState.appendOutput("ℹ️  Remote services are managed by AWS\n")
        lambdaState.appendOutput("   Services (RDS, S3) run continuously when deployed\n")
        if _endpoint != nil {
            lambdaState.setRunning()
        }
    }

    /// Stop with services is not applicable for remote
    public func stopWithServices() async throws {
        lambdaState.appendOutput("ℹ️  Remote services are managed by AWS\n")
        lambdaState.appendOutput("   Use 'aws tear-down' to remove all infrastructure\n")
    }

    // MARK: - LambdaService Protocol: Testing

    /// Test remote Lambda endpoints
    public func testLambda() async throws {
        let apiUrl = endpoint
        guard !apiUrl.contains("<not-configured>") else {
            throw DeployError.testFailed(message: "Remote endpoint not configured. Deploy first or run fetchEndpoint().")
        }

        print("\n🧪 Testing remote Lambda at \(apiUrl)...")
        print("")

        do {
            try await performRemoteLambdaTests(apiUrl: apiUrl)
        } catch let error as APIError {
            throw DeployError.testFailed(message: "API Error: \(error.localizedDescription)")
        }

        print("")
        print("✅ All remote Lambda tests passed!")
    }

    /// Wait for Lambda to be ready (check if endpoint responds)
    public func waitForReady(maxAttempts: Int = 30) async throws {
        let apiUrl = endpoint
        guard !apiUrl.contains("<not-configured>") else {
            throw DeployError.testFailed(message: "Remote endpoint not configured")
        }

        print("🔍 Checking remote Lambda availability...")

        var attempts = 0
        var ready = false

        while attempts < maxAttempts && !ready {
            do {
                let curlCommand = Curl.Request.checkStatus(url: "\(apiUrl)api/health")
                let result = try await cliService.executeForResult(curlCommand, printCommand: false)

                if result.isSuccess && (result.stdout == "200" || result.stdout == "404") {
                    ready = true
                    break
                }
            } catch {
                // Ignore errors, keep trying
            }

            try await Task.sleep(for: .seconds(1))
            attempts += 1

            if attempts % 10 == 0 {
                print("  → Still waiting for Lambda... (\(attempts) seconds)")
            }
        }

        if !ready {
            throw DeployError.testFailed(message: "Remote Lambda not responding after \(maxAttempts) seconds")
        }

        print("  ✅ Remote Lambda is available")
    }

    // MARK: - LambdaService Protocol: Status

    /// Get status of remote services
    public func status() async throws -> DeploymentStatus {
        let stackExists = await checkStackExists()

        if stackExists {
            return DeploymentStatus(
                lambdaState: .running,
                s3State: .running,
                postgresState: .running
            )
        } else {
            return DeploymentStatus(
                lambdaState: .stopped,
                s3State: .stopped,
                postgresState: .stopped
            )
        }
    }

    /// Refresh status and publish results via Combine publishers
    /// Always fetches the latest endpoint from CDK stack
    public func refreshStatus() {
        let statusSubject = self.statusSubject
        let isLoadingStatusSubject = self.isLoadingStatusSubject

        isLoadingStatusSubject.send(true)
        Task {
            // Always fetch the latest endpoint from AWS
            try? await fetchEndpoint()

            do {
                let newStatus = try await self.status()
                statusSubject.send(newStatus)
            } catch {
                statusSubject.send(.stopped)
            }
            isLoadingStatusSubject.send(false)
        }
    }

    // MARK: - Deployment Operations

    /// Deploy CDK stack (maintains current configuration)
    public func deploy(options: DeploymentOptions) async throws {
        print("\n📦 Starting CDK deployment...")

        // Query current deployed state
        let deployedState = try await queryDeployedState()

        // Determine what to deploy based on current state
        let finalOptions: DeploymentOptions

        if let state = deployedState {
            print("\n📊 Detected existing stack configuration:")
            print("   Database: \(state.hasDatabase ? "YES" : "NO")")
            print("   NAT Gateway: \(state.hasNATGateway ? "YES" : "NO")")
            print("   → Maintaining current configuration\n")

            finalOptions = DeploymentOptions(
                skipPostgres: !state.hasDatabase,
                skipNATGateway: !state.hasNATGateway,
                awsProfile: options.awsProfile,
                cdkDirectory: options.cdkDirectory
            )
        } else {
            print("\n⚠️  No existing stack detected")
            print("   → Using minimal configuration (no database, no NAT)")
            print("   → Use 'deploy-init' to set initial configuration\n")

            finalOptions = options
        }

        // Build TypeScript first
        try await cdkService.build()

        // Deploy with resolved options
        let cdkOptions = CDKService.DeployOptions(
            skipPostgres: finalOptions.skipPostgres,
            skipNATGateway: finalOptions.skipNATGateway,
            requireApproval: false
        )

        try await cdkService.deploy(options: cdkOptions)

        print("\n✅ CDK deployment completed successfully")
    }

    /// Poll CloudFormation stack status until deployment is complete
    public func pollDeploymentStatus(
        stackName: String = "SwiftLambdaSampleStack"
    ) async throws {
        print("\n⏳ Polling deployment status...")

        var attempts = 0
        let maxAttempts = 60
        let pollInterval: UInt64 = 5_000_000_000

        while attempts < maxAttempts {
            let status = try await awsService.getStackStatus(name: stackName)
            print("  Stack status: \(status)")

            switch status {
            case "CREATE_COMPLETE", "UPDATE_COMPLETE":
                print("\n✅ Deployment completed successfully")
                return

            case "CREATE_FAILED", "UPDATE_FAILED", "ROLLBACK_COMPLETE", "ROLLBACK_FAILED":
                throw DeployError.deploymentFailed(reason: "Stack deployment failed with status: \(status)")

            case "CREATE_IN_PROGRESS", "UPDATE_IN_PROGRESS", "UPDATE_COMPLETE_CLEANUP_IN_PROGRESS":
                break

            default:
                print("  Unknown status: \(status), continuing to poll...")
            }

            attempts += 1
            try await Task.sleep(nanoseconds: pollInterval)
        }

        throw CLIServiceError.timeout(command: "CloudFormation stack deployment", duration: Double(maxAttempts * 5))
    }

    /// Tear down CDK stack
    public func tearDown(cdkDirectory: String = "cdk") async throws {
        let cdkPath = "\(projectRoot)/\(cdkDirectory)"

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: cdkPath, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw CLIServiceError.invalidWorkingDirectory("CDK directory not found at: \(cdkPath)")
        }

        try await cdkService.destroy(force: true)

        print("\n✅ CDK stack destroyed successfully")
    }

    /// Get stack outputs
    public func getStackOutputs(
        stackName: String = "SwiftLambdaSampleStack"
    ) async throws -> [String: String] {
        return try await awsService.getStackOutputs(name: stackName)
    }

    /// Get API Gateway URL from deployed stack
    public func getAPIGatewayURL(
        stackName: String = "SwiftLambdaSampleStack"
    ) async throws -> String? {
        let outputs = try await getStackOutputs(stackName: stackName)
        return outputs["ApiGatewayUrl"]
    }

    /// Deploy infrastructure and display outputs
    public func deployInfrastructure(
        options: DeploymentOptions,
        stackName: String = "SwiftLambdaSampleStack"
    ) async throws -> [String: String] {
        try await deploy(options: options)
        try await pollDeploymentStatus(stackName: stackName)

        let outputs = try await getStackOutputs(stackName: stackName)

        if !outputs.isEmpty {
            print("\n📋 Stack Outputs:")
            for (key, value) in outputs.sorted(by: { $0.key < $1.key }) {
                print("  \(key): \(value)")
            }
        }

        return outputs
    }

    /// Update Lambda code via GitHub Actions
    public func updateLambdaCode(skipPush: Bool = false) async throws {
        let gitService = GitService(repoPath: projectRoot)
        let repoInfo = try await gitService.getRepoInfo()
        let currentBranch = try await gitService.getCurrentBranch()
        let githubService = GitHubService(repoPath: projectRoot, owner: repoInfo.owner, repo: repoInfo.name)

        if !skipPush {
            let hasCommitsToPush = try await gitService.hasCommitsToPush()

            if hasCommitsToPush {
                let beforeRunId = try await githubService.getLatestRunId(branch: currentBranch)
                try await gitService.push()

                try await githubService.waitForNewWorkflowCompletion(
                    branch: currentBranch,
                    afterRunId: beforeRunId,
                    timeoutMinutes: 10
                )
            } else {
                print("\n✅ No commits to push")
                print("🔄 Triggering workflow to redeploy current code...\n")
                try await githubService.triggerWorkflowAndWait(
                    workflowName: "Dev Deploy",
                    branch: currentBranch,
                    timeoutMinutes: 10
                )
            }
        } else {
            print("\n⏭️  Skipping git push (--skip-push enabled)")
            print("🔄 Triggering workflow...\n")
            try await githubService.triggerWorkflowAndWait(
                workflowName: "Dev Deploy",
                branch: currentBranch,
                timeoutMinutes: 10
            )
        }
    }

    /// Initial deployment workflow - sets infrastructure configuration
    public func deployInit(
        options: DeploymentOptions,
        withPostgres: Bool,
        skipPush: Bool = false,
        stackName: String = "SwiftLambdaSampleStack"
    ) async throws {
        let existingState = try await queryDeployedState(stackName: stackName)

        if let state = existingState {
            print("\n⚠️  WARNING: Stack already exists!")
            print("   Current configuration:")
            print("     Database: \(state.hasDatabase ? "YES" : "NO")")
            print("     NAT Gateway: \(state.hasNATGateway ? "YES" : "NO")")
            print("\n   New configuration:")
            print("     Database: \(withPostgres ? "YES" : "NO")")
            print("     NAT Gateway: \(!options.skipNATGateway ? "YES" : "NO")")

            if state.hasDatabase && options.skipPostgres {
                print("\n❌ ERROR: This would DELETE your database!")
                print("   Use 'tear-down' first if you want to remove the database.")
                throw DeployError.invalidConfiguration("Cannot remove database with deploy-init")
            }

            print("\n   Updating existing stack...\n")
        }

        _ = try await deployInfrastructure(options: options, stackName: stackName)
        try await updateLambdaCode(skipPush: skipPush)

        if withPostgres {
            print("\n🗄️  Initializing database...")
            do {
                try await initializeDatabase(stackName: stackName)
                print("  ✓ Database initialized successfully")
            } catch {
                print("\n⚠️  Database initialization failed: \(error)")
                print("⚠️  You may need to initialize the database manually.")
            }
        }

        print("\n🧪 Verifying deployment...")
        do {
            try await verifyDeployment(stackName: stackName, withPostgres: withPostgres)
            print("\n✅ Deployment verification passed!")
        } catch {
            print("\n⚠️  Deployment verification failed: \(error)")
            print("⚠️  The infrastructure is deployed but the API may not be working correctly.")
        }

        print("\n🎉 Deployment completed successfully!")
    }

    // MARK: - GitHub CI Operations (delegates to GitHubService)

    /// Refresh GitHub CI status including git state and latest workflow run.
    /// If an in-progress run is detected, automatically starts monitoring it.
    public func refreshGitHubCIStatus() async {
        do {
            let ghService = try await getGitHubService()
            await ghService.refreshStatus()
        } catch {
            print("Failed to refresh GitHub CI status: \(error)")
        }
    }

    /// Push commits and deploy via GitHub Actions with polling progress
    public func pushAndDeploy() async throws {
        let ghService = try await getGitHubService()
        try await ghService.pushAndDeploy()
    }

    /// Open workflow logs in browser
    public func viewWorkflowLogs(runId: String) async throws {
        let ghService = try await getGitHubService()
        try await ghService.viewWorkflowLogs(runId: runId)
    }

    // MARK: - Private Helpers

    private func checkStackExists() async -> Bool {
        do {
            let outputs = try await awsService.getStackOutputs(name: "SwiftLambdaSampleStack")
            return !outputs.isEmpty
        } catch {
            return false
        }
    }

    private func queryDeployedState(
        stackName: String = "SwiftLambdaSampleStack"
    ) async throws -> DeployedState? {
        do {
            let resources = try await awsService.describeStackResources(name: stackName)

            return DeployedState(
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
        } catch {
            return nil
        }
    }

    @MainActor
    private func createRemoteAPIClient(apiUrl: String) -> APIClient {
        APIClient(baseURL: apiUrl)
    }

    @MainActor
    private func performRemoteLambdaTests(apiUrl: String) async throws {
        let client = createRemoteAPIClient(apiUrl: apiUrl)

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
    }

    private func initializeDatabase(stackName: String) async throws {
        let outputs = try await getStackOutputs(stackName: stackName)

        guard let apiUrl = outputs["ApiGatewayUrl"] else {
            throw CLIServiceError.invalidOutput(reason: "Could not find ApiGatewayUrl in stack outputs")
        }

        print("  → POST \(apiUrl)api/database")

        let curlCommand = Curl.Request.post(url: "\(apiUrl)api/database", silent: true)
        let result = try await cliService.executeForResult(curlCommand, printCommand: false)

        guard result.isSuccess else {
            throw CLIServiceError.executionFailed(
                command: curlCommand.commandString,
                exitCode: result.exitCode,
                stderr: result.stderr
            )
        }

        let response = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        print("  Response: \(response)")

        if !response.contains("Database Initialized") {
            throw DeployError.deploymentFailed(reason: "Unexpected database init response: \(response)")
        }
    }

    private func verifyDeployment(stackName: String, withPostgres: Bool) async throws {
        let outputs = try await getStackOutputs(stackName: stackName)

        guard let apiUrl = outputs["ApiGatewayUrl"] else {
            throw CLIServiceError.invalidOutput(reason: "Could not find ApiGatewayUrl in stack outputs")
        }

        print("  Testing health endpoint...")
        print("  → GET \(apiUrl)api/health")

        let healthCommand = Curl.Request.get(url: "\(apiUrl)api/health", silent: true)
        let testResult = try await cliService.executeForResult(healthCommand, printCommand: false)

        guard testResult.isSuccess else {
            throw CLIServiceError.executionFailed(
                command: healthCommand.commandString,
                exitCode: testResult.exitCode,
                stderr: testResult.stderr
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
            let usersResult = try await cliService.executeForResult(usersCommand, printCommand: false)

            guard usersResult.isSuccess else {
                throw CLIServiceError.executionFailed(
                    command: usersCommand.commandString,
                    exitCode: usersResult.exitCode,
                    stderr: usersResult.stderr
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
    }
}
