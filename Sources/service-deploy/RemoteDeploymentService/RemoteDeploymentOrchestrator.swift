import sdk_cli
import sdk_aws
import sdk_client
import Foundation

/// Stateless orchestrator for remote AWS Lambda deployment and management.
/// Orchestrates SwiftLambdaCDKService, SwiftLambdaInfrastructureService,
/// GitService, and GitHubActionsService.
///
/// This is a CLI-focused orchestrator for one-off deployment operations.
/// For UI state observation, use `RemoteDeploymentService` which provides
/// an `AsyncStream<State>` for reactive updates.
public actor RemoteDeploymentOrchestrator {
    private let cdkService: SwiftLambdaCDKService
    private let infrastructureService: SwiftLambdaInfrastructureService
    private let cliClient: CLIClient
    private let projectRoot: String

    // MARK: - Initialization

    public init(
        projectRoot: String,
        awsConfig: AWSAuthConfiguration,
        cdkDirectory: String = CDKStackConfiguration.defaultCDKDirectory,
        stackName: String = CDKStackConfiguration.defaultStackName
    ) {
        self.projectRoot = projectRoot
        let cliClient = CLIClient(defaultWorkingDirectory: projectRoot)
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

    // MARK: - Deployment Operations

    /// Deploy CDK stack (maintains current configuration)
    /// Returns deployment result with stack outputs
    public func deploy(options: DeploymentConfiguration) async throws -> DeploymentResult {
        print("\n📦 Starting CDK deployment...")

        // Query current deployed state
        let deployedState = try await queryDeployedState()

        // Determine what to deploy based on current state
        let withPostgres: Bool
        let withNATGateway: Bool

        if let state = deployedState {
            print("\n📊 Detected existing stack configuration:")
            print("   Database: \(state.hasDatabase ? "YES" : "NO")")
            print("   NAT Gateway: \(state.hasNATGateway ? "YES" : "NO")")
            print("   → Maintaining current configuration\n")

            withPostgres = state.hasDatabase
            withNATGateway = state.hasNATGateway
        } else {
            print("\n⚠️  No existing stack detected")
            print("   → Using minimal configuration (no database, no NAT)")
            print("   → Use 'deploy-init' to set initial configuration\n")

            withPostgres = !options.skipPostgres
            withNATGateway = !options.skipNATGateway
        }

        // Build TypeScript first
        try await cdkService.build()

        // Deploy with resolved options
        let cdkOptions = SwiftLambdaCDKService.DeployOptions(
            withPostgres: withPostgres,
            withNATGateway: withNATGateway,
            requireApproval: false
        )

        try await cdkService.deploy(options: cdkOptions)

        print("\n✅ CDK deployment completed successfully")

        // Poll for completion and get outputs
        try await pollDeploymentStatus()
        let outputs = try await getStackOutputs()

        if !outputs.isEmpty {
            print("\n📋 Stack Outputs:")
            for (key, value) in outputs.sorted(by: { $0.key < $1.key }) {
                print("  \(key): \(value)")
            }
        }

        return DeploymentResult(outputs: outputs)
    }

    /// Initial deployment workflow - sets infrastructure configuration
    public func deployInit(
        options: DeploymentConfiguration,
        withPostgres: Bool,
        skipPush: Bool = false,
        stackName: String = CDKStackConfiguration.defaultStackName
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

    /// Tear down CDK stack
    public func tearDown(cdkDirectory: String = CDKStackConfiguration.defaultCDKDirectory) async throws {
        let cdkPath = "\(projectRoot)/\(cdkDirectory)"

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: cdkPath, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw CLIClientError.invalidWorkingDirectory("CDK directory not found at: \(cdkPath)")
        }

        try await cdkService.destroy(force: true)

        print("\n✅ CDK stack destroyed successfully")
    }

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

    // MARK: - Status Operations

    /// Get comprehensive status of remote deployment
    public func getStatus() async throws -> RemoteStatus {
        let gitService = GitClient(repoPath: projectRoot, cliClient: cliClient)

        // Get git status
        let hasUncommitted = try await gitService.hasUncommittedChanges()
        let hasCommitsToPush = try await gitService.hasCommitsToPush()
        let currentBranch = try await gitService.getCurrentBranch()

        let gitStatus = RemoteStatus.GitStatus(
            hasUncommittedChanges: hasUncommitted,
            hasCommitsToPush: hasCommitsToPush,
            currentBranch: currentBranch
        )

        // Get GitHub status if configured
        var githubStatus: RemoteStatus.GitHubStatus? = nil
        if let githubConfig = GitHubConfiguration.loadConfig() {
            let actionsService = makeGitHubActionsClient(repoPath: projectRoot, config: githubConfig, cliClient: cliClient)
            do {
                let (status, conclusion) = try await actionsService.getLatestRunStatus()
                githubStatus = RemoteStatus.GitHubStatus(
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

        return RemoteStatus(
            stackOutputs: stackOutputs,
            gitStatus: gitStatus,
            githubStatus: githubStatus
        )
    }

    /// Get stack outputs from CloudFormation
    public func getStackOutputs(
        stackName: String = CDKStackConfiguration.defaultStackName
    ) async throws -> [String: String] {
        return try await infrastructureService.getRawStackOutputs()
    }

    /// Get API Gateway URL from deployed stack
    public func getAPIGatewayURL(
        stackName: String = CDKStackConfiguration.defaultStackName
    ) async throws -> String? {
        try await infrastructureService.getAPIGatewayURL()
    }

    /// Check if stack exists
    public func checkStackExists(stackName: String = CDKStackConfiguration.defaultStackName) async -> Bool {
        do {
            return try await infrastructureService.stackExists()
        } catch {
            return false
        }
    }

    // MARK: - Testing Operations

    /// Test remote Lambda endpoints
    public func testEndpoints(apiUrl: String) async throws {
        guard !apiUrl.contains("<not-configured>") else {
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

    /// Wait for Lambda to be ready (check if endpoint responds)
    public func waitForReady(apiUrl: String, maxAttempts: Int = 30) async throws {
        guard !apiUrl.contains("<not-configured>") else {
            throw DeployError.testFailed(message: "Remote endpoint not configured")
        }

        print("🔍 Checking remote Lambda availability...")

        var attempts = 0
        var ready = false

        while attempts < maxAttempts && !ready {
            do {
                let curlCommand = Curl.Request.checkStatus(url: "\(apiUrl)api/health")
                let result = try await cliClient.executeForResult(curlCommand, printCommand: false)

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

    // MARK: - Private Helpers

    private func queryDeployedState(
        stackName: String = CDKStackConfiguration.defaultStackName
    ) async throws -> DeployedState? {
        guard let config = try await infrastructureService.detectConfiguration() else {
            return nil
        }
        return DeployedState(
            hasDatabase: config.hasDatabase,
            hasNATGateway: config.hasNATGateway,
            hasVPC: config.hasVPC
        )
    }

    private func pollDeploymentStatus(
        stackName: String = CDKStackConfiguration.defaultStackName
    ) async throws {
        print("\n⏳ Polling deployment status...")

        var attempts = 0
        let maxAttempts = 60
        let pollInterval: UInt64 = 5_000_000_000

        while attempts < maxAttempts {
            let status = try await infrastructureService.getStackStatus()
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

        throw CLIClientError.timeout(command: "CloudFormation stack deployment", duration: Double(maxAttempts * 5))
    }

    private func deployInfrastructure(
        options: DeploymentConfiguration,
        stackName: String = CDKStackConfiguration.defaultStackName
    ) async throws -> [String: String] {
        // Build TypeScript first
        try await cdkService.build()

        // Deploy with options
        let cdkOptions = SwiftLambdaCDKService.DeployOptions(
            withPostgres: !options.skipPostgres,
            withNATGateway: !options.skipNATGateway,
            requireApproval: false
        )

        try await cdkService.deploy(options: cdkOptions)
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

    private func initializeDatabase(stackName: String) async throws {
        let outputs = try await getStackOutputs(stackName: stackName)

        guard let apiUrl = outputs["ApiGatewayUrl"] else {
            throw CLIClientError.invalidOutput(reason: "Could not find ApiGatewayUrl in stack outputs")
        }

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
    }

    private func verifyDeployment(stackName: String, withPostgres: Bool) async throws {
        let outputs = try await getStackOutputs(stackName: stackName)

        guard let apiUrl = outputs["ApiGatewayUrl"] else {
            throw CLIClientError.invalidOutput(reason: "Could not find ApiGatewayUrl in stack outputs")
        }

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
    }
}

/// Detected state of deployed infrastructure
public struct DeployedState: Sendable {
    public let hasDatabase: Bool
    public let hasNATGateway: Bool
    public let hasVPC: Bool
}

/// Result of a deployment operation
public struct DeploymentResult: Sendable {
    public let outputs: [String: String]
    public let apiGatewayUrl: String?

    public init(outputs: [String: String]) {
        self.outputs = outputs
        self.apiGatewayUrl = outputs["ApiGatewayUrl"]
    }
}

/// Result of a status check
public struct RemoteStatus: Sendable {
    public let stackOutputs: [String: String]
    public let gitStatus: GitStatus
    public let githubStatus: GitHubStatus?

    public struct GitStatus: Sendable {
        public let hasUncommittedChanges: Bool
        public let hasCommitsToPush: Bool
        public let currentBranch: String
    }

    public struct GitHubStatus: Sendable {
        public let repository: String
        public let branch: String
        public let latestRunStatus: String
        public let conclusion: String?
    }
}
