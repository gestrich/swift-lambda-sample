import Foundation
import ArgumentParser

struct FreshDeployCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "fresh-deploy",
        abstract: "Initial deployment: CDK infrastructure + Lambda code"
    )

    @Option(name: .long, help: "AWS profile to use")
    var awsProfile: String = "production"

    @Option(name: .long, help: "CDK directory path")
    var cdkDirectory: String = "cdk"

    @Flag(name: .long, help: "Include PostgreSQL database (adds cost)")
    var withPostgres: Bool = false

    @Flag(name: .long, help: "Include NAT Gateway (adds cost)")
    var withNatGateway: Bool = false

    @Flag(name: .long, help: "Skip git push")
    var skipPush: Bool = false

    mutating func run() async throws {
        print("🚀 Starting deployment...\n")

        if !withPostgres && !withNatGateway {
            print("💰 MINIMAL COST MODE (default)")
            print("   - No PostgreSQL database")
            print("   - No NAT Gateway")
            print("   - Cost: ~$0/month (only pay for Lambda invocations, S3, SQS usage)")
            print("")
        }

        let projectRoot = FileManager.default.currentDirectoryPath
        let deploymentService = DeploymentService(projectRoot: projectRoot)
        let gitService = GitService(repoPath: projectRoot)

        // 1. Deploy CDK infrastructure
        let options = DeploymentOptions(
            skipPostgres: !withPostgres,  // Invert: default is to skip
            skipNATGateway: !withNatGateway,  // Invert: default is to skip
            awsProfile: awsProfile,
            cdkDirectory: cdkDirectory
        )

        try await deploymentService.deploy(options: options)

        // 2. Poll deployment status
        try await deploymentService.pollDeploymentStatus(
            stackName: "SwiftLambdaSampleStack",
            awsProfile: awsProfile
        )

        // 3. Get and display stack outputs
        let outputs = try await deploymentService.getStackOutputs(
            stackName: "SwiftLambdaSampleStack",
            awsProfile: awsProfile
        )

        if !outputs.isEmpty {
            print("\n📋 Stack Outputs:")
            for (key, value) in outputs.sorted(by: { $0.key < $1.key }) {
                print("  \(key): \(value)")
            }
        }

        // 4. Deploy Lambda code via GitHub Actions
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
                // No commits to push, but we still need to deploy Lambda code
                // Manually trigger the workflow
                print("\n✅ No commits to push")
                try await githubService.triggerWorkflowAndWait(
                    workflowName: "Dev Deploy",
                    branch: currentBranch,
                    timeoutMinutes: 10
                )
            }
        } else {
            // Skip push is enabled, but we still need Lambda code deployed
            // Manually trigger the workflow
            print("\n⏭️  Skipping git push (--skip-push enabled)")
            try await githubService.triggerWorkflowAndWait(
                workflowName: "Dev Deploy",
                branch: currentBranch,
                timeoutMinutes: 10
            )
        }

        // 5. Initialize database if PostgreSQL was deployed
        if withPostgres {
            print("\n🗄️  Initializing database...")
            do {
                try await initializeDatabase(
                    stackName: "SwiftLambdaSampleStack",
                    awsProfile: awsProfile
                )
                print("  ✓ Database initialized successfully")
            } catch {
                print("\n⚠️  Database initialization failed: \(error)")
                print("⚠️  You may need to initialize the database manually.")
            }
        }

        // 6. Verify deployment by testing the API
        print("\n🧪 Verifying deployment...")

        do {
            try await verifyDeployment(
                stackName: "SwiftLambdaSampleStack",
                awsProfile: awsProfile,
                withPostgres: withPostgres
            )
            print("\n✅ Deployment verification passed!")
        } catch {
            print("\n⚠️  Deployment verification failed: \(error)")
            print("⚠️  The infrastructure is deployed but the API may not be working correctly.")
        }

        print("\n🎉 Deployment completed successfully!")
    }

    private func initializeDatabase(stackName: String, awsProfile: String) async throws {
        let projectRoot = FileManager.default.currentDirectoryPath
        let deploymentService = DeploymentService(projectRoot: projectRoot)
        let cliService = CLIService.shared

        // Get API Gateway URL
        let outputs = try await deploymentService.getStackOutputs(
            stackName: stackName,
            awsProfile: awsProfile
        )

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

    private func verifyDeployment(stackName: String, awsProfile: String, withPostgres: Bool) async throws {
        let projectRoot = FileManager.default.currentDirectoryPath
        let deploymentService = DeploymentService(projectRoot: projectRoot)
        let cliService = CLIService.shared

        // Get API Gateway URL
        let outputs = try await deploymentService.getStackOutputs(
            stackName: stackName,
            awsProfile: awsProfile
        )

        guard let apiUrl = outputs["ApiGatewayUrl"] else {
            throw CLIError.invalidOutput(reason: "Could not find ApiGatewayUrl in stack outputs")
        }

        // Test the file endpoint
        print("  Testing S3 file endpoint...")
        print("  → POST \(apiUrl)api/file")

        let testResult = try await cliService.execute(
            command: "curl",
            arguments: [
                "-s",
                "-X", "POST",
                "\(apiUrl)api/file"
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

        if !response.contains("File uploaded and downloaded") {
            throw CLIError.deploymentFailed(reason: "Unexpected API response: \(response)")
        }

        print("  ✓ API Gateway working")
        print("  ✓ Lambda function executing")
        print("  ✓ S3 integration working")

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
