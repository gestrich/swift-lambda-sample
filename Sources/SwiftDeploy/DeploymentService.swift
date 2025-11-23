import Foundation

/// Service for managing CDK deployments
public actor DeploymentService {
    private let cdkService: CDKService
    private let awsService: AWSCLIService
    private let projectRoot: String

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
    }

    /// Deploy CDK stack
    public func deploy(options: DeploymentOptions) async throws {
        print("\n📦 Starting CDK deployment...")

        // Build TypeScript first
        try await cdkService.build()

        // Deploy with CDK
        let cdkOptions = CDKService.DeployOptions(
            skipPostgres: options.skipPostgres,
            skipNATGateway: options.skipNATGateway,
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
        let maxAttempts = 60 // 5 minutes with 5-second intervals
        let pollInterval: UInt64 = 5_000_000_000 // 5 seconds in nanoseconds

        while attempts < maxAttempts {
            let status = try await awsService.getStackStatus(name: stackName)
            print("  Stack status: \(status)")

            switch status {
            case "CREATE_COMPLETE", "UPDATE_COMPLETE":
                print("\n✅ Deployment completed successfully")
                return

            case "CREATE_FAILED", "UPDATE_FAILED", "ROLLBACK_COMPLETE", "ROLLBACK_FAILED":
                throw CLIError.deploymentFailed(reason: "Stack deployment failed with status: \(status)")

            case "CREATE_IN_PROGRESS", "UPDATE_IN_PROGRESS", "UPDATE_COMPLETE_CLEANUP_IN_PROGRESS":
                // Continue polling
                break

            default:
                print("  Unknown status: \(status), continuing to poll...")
            }

            attempts += 1
            try await Task.sleep(nanoseconds: pollInterval)
        }

        throw CLIError.timeout(command: "CloudFormation stack deployment", duration: Double(maxAttempts * 5))
    }

    /// Tear down CDK stack
    public func tearDown(cdkDirectory: String = "cdk") async throws {
        let cdkPath = "\(projectRoot)/\(cdkDirectory)"

        // Verify CDK directory exists
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: cdkPath, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw CLIError.invalidWorkingDirectory("CDK directory not found at: \(cdkPath)")
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

    /// Deploy infrastructure and display outputs
    /// This is the complete infrastructure deployment workflow
    public func deployInfrastructure(
        options: DeploymentOptions,
        stackName: String = "SwiftLambdaSampleStack"
    ) async throws -> [String: String] {
        // 1. Deploy CDK infrastructure
        try await deploy(options: options)

        // 2. Poll deployment status
        try await pollDeploymentStatus(stackName: stackName)

        // 3. Get and display stack outputs
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
    /// Handles git push (if needed) and triggers/waits for GitHub Actions workflow
    public func updateLambdaCode(skipPush: Bool = false) async throws {
        let gitService = GitService(repoPath: projectRoot)
        let repoInfo = try await gitService.getRepoInfo()
        let currentBranch = try await gitService.getCurrentBranch()
        let githubService = GitHubService(owner: repoInfo.owner, repo: repoInfo.name)

        if !skipPush {
            let hasCommitsToPush = try await gitService.hasCommitsToPush()

            if hasCommitsToPush {
                // Get the current latest run ID before pushing
                let beforeRunId = try await githubService.getLatestRunId(branch: currentBranch)

                // Push commits (this will auto-trigger the workflow)
                try await gitService.push()

                // Wait for the NEW workflow that was triggered by the push
                try await githubService.waitForNewWorkflowCompletion(
                    branch: currentBranch,
                    afterRunId: beforeRunId,
                    timeoutMinutes: 10
                )
            } else {
                // No commits to push, manually trigger the workflow
                print("\n✅ No commits to push")
                print("🔄 Triggering workflow to redeploy current code...\n")
                try await githubService.triggerWorkflowAndWait(
                    workflowName: "Dev Deploy",
                    branch: currentBranch,
                    timeoutMinutes: 10
                )
            }
        } else {
            // Skip push, manually trigger the workflow
            print("\n⏭️  Skipping git push (--skip-push enabled)")
            print("🔄 Triggering workflow...\n")
            try await githubService.triggerWorkflowAndWait(
                workflowName: "Dev Deploy",
                branch: currentBranch,
                timeoutMinutes: 10
            )
        }
    }

    /// Complete full deployment workflow
    /// Deploys infrastructure, Lambda code, initializes database, and verifies deployment
    public func deployFull(
        options: DeploymentOptions,
        withPostgres: Bool,
        skipPush: Bool = false,
        stackName: String = "SwiftLambdaSampleStack"
    ) async throws {
        // 1. Deploy infrastructure
        _ = try await deployInfrastructure(options: options, stackName: stackName)

        // 2. Deploy Lambda code
        try await updateLambdaCode(skipPush: skipPush)

        // 3. Initialize database if PostgreSQL was deployed
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

        // 4. Verify deployment by testing the API
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

    /// Initialize database by calling the /api/database endpoint
    private func initializeDatabase(stackName: String) async throws {
        let cliService = CLIService.shared

        // Get API Gateway URL
        let outputs = try await getStackOutputs(stackName: stackName)

        guard let apiUrl = outputs["ApiGatewayUrl"] else {
            throw CLIError.invalidOutput(reason: "Could not find ApiGatewayUrl in stack outputs")
        }

        // Initialize the database
        print("  → POST \(apiUrl)api/database")

        let result = try await cliService.execute(
            command: "curl",
            arguments: [
                "-s",
                "-X", "POST",
                "\(apiUrl)api/database"
            ],
            printCommand: false
        )

        guard result.isSuccess else {
            throw CLIError.executionFailed(
                command: "curl",
                exitCode: result.exitCode,
                stderr: result.stderr
            )
        }

        let response = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        print("  Response: \(response)")

        if !response.contains("Database Initialized") {
            throw CLIError.deploymentFailed(reason: "Unexpected database init response: \(response)")
        }
    }

    /// Verify deployment by testing API endpoints
    private func verifyDeployment(stackName: String, withPostgres: Bool) async throws {
        let cliService = CLIService.shared

        // Get API Gateway URL
        let outputs = try await getStackOutputs(stackName: stackName)

        guard let apiUrl = outputs["ApiGatewayUrl"] else {
            throw CLIError.invalidOutput(reason: "Could not find ApiGatewayUrl in stack outputs")
        }

        // Test the health endpoint
        print("  Testing health endpoint...")
        print("  → GET \(apiUrl)api/health")

        let testResult = try await cliService.execute(
            command: "curl",
            arguments: [
                "-s",
                "-X", "GET",
                "\(apiUrl)api/health"
            ],
            printCommand: false
        )

        guard testResult.isSuccess else {
            throw CLIError.executionFailed(
                command: "curl",
                exitCode: testResult.exitCode,
                stderr: testResult.stderr
            )
        }

        let response = testResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        print("  Response: \(response)")

        if !response.contains("healthy") {
            throw CLIError.deploymentFailed(reason: "Unexpected API response: \(response)")
        }

        print("  ✓ API Gateway working")
        print("  ✓ Lambda function executing")
        print("  ✓ Health check passed")

        // Test database endpoints if PostgreSQL is deployed
        if withPostgres {
            print("\n  Testing database endpoints...")
            print("  → GET \(apiUrl)api/users")

            let usersResult = try await cliService.execute(
                command: "curl",
                arguments: [
                    "-s",
                    "-X", "GET",
                    "\(apiUrl)api/users"
                ],
                printCommand: false
            )

            guard usersResult.isSuccess else {
                throw CLIError.executionFailed(
                    command: "curl",
                    exitCode: usersResult.exitCode,
                    stderr: usersResult.stderr
                )
            }

            let usersResponse = usersResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            print("  Response: \(usersResponse)")

            // Verify it's valid JSON (empty array is expected for fresh database)
            if let data = usersResponse.data(using: .utf8),
               let _ = try? JSONSerialization.jsonObject(with: data) {
                print("  ✓ Database connection working")
                print("  ✓ User endpoint responding")
            } else {
                throw CLIError.deploymentFailed(reason: "Invalid JSON response from users endpoint: \(usersResponse)")
            }
        }
    }
}
