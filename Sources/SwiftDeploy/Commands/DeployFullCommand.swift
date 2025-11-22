import Foundation
import ArgumentParser

extension AWSCommand {
    struct DeployFullCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "deploy-full",
            abstract: "Full deployment: CDK infrastructure + Lambda code"
        )

    @Option(name: .long, help: AWSAuthConfiguration.profileOptionHelp)
    var awsProfile: String?

    @Option(name: .long, help: "Use aws-vault for credential management")
    var useAwsVault: Bool?

    @Option(name: .long, help: "CDK directory path")
    var cdkDirectory: String = "cdk"

    @Flag(name: .long, help: "Include PostgreSQL database (adds cost)")
    var withPostgres: Bool = false

    @Flag(name: .long, help: "Include NAT Gateway (adds cost)")
    var withNatGateway: Bool = false

    @Flag(name: .long, help: "Skip git push")
    var skipPush: Bool = false

    mutating func run() async throws {
        // Resolve AWS configuration from CLI args and config file
        let awsConfig = try AWSAuthConfiguration.resolve(
            profileName: awsProfile,
            useAWSVault: useAwsVault
        )

        if awsProfile == nil {
            print("ℹ️  Using AWS profile '\(awsConfig.profileName)' from config file\n")
        }

        print("🚀 Starting deployment...\n")

        if !withPostgres && !withNatGateway {
            print("💰 MINIMAL COST MODE (default)")
            print("   - No PostgreSQL database")
            print("   - No NAT Gateway")
            print("   - Cost: ~$0/month (only pay for Lambda invocations, S3, SQS usage)")
            print("")
        }

        let projectRoot = FileManager.default.currentDirectoryPath
        let deploymentService = DeploymentService(
            projectRoot: projectRoot,
            awsConfig: awsConfig
        )

        // 1. Deploy CDK infrastructure
        let options = DeploymentOptions(
            skipPostgres: !withPostgres,
            skipNATGateway: !withNatGateway,
            awsProfile: awsConfig.profileName,
            cdkDirectory: cdkDirectory
        )

        _ = try await deploymentService.deployInfrastructure(options: options)

        // 2. Deploy Lambda code via GitHub Actions
        try await deploymentService.updateLambdaCode(skipPush: skipPush)

        // 5. Initialize database if PostgreSQL was deployed
        if withPostgres {
            print("\n🗄️  Initializing database...")
            do {
                try await initializeDatabase(
                    stackName: "SwiftLambdaSampleStack",
                    awsConfig: awsConfig
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
                awsConfig: awsConfig,
                withPostgres: withPostgres
            )
            print("\n✅ Deployment verification passed!")
        } catch {
            print("\n⚠️  Deployment verification failed: \(error)")
            print("⚠️  The infrastructure is deployed but the API may not be working correctly.")
        }

        print("\n🎉 Deployment completed successfully!")
    }

    private func initializeDatabase(stackName: String, awsConfig: AWSAuthConfiguration) async throws {
        let projectRoot = FileManager.default.currentDirectoryPath
        let deploymentService = DeploymentService(
            projectRoot: projectRoot,
            awsConfig: awsConfig
        )
        let cliService = CLIService.shared

        // Get API Gateway URL
        let outputs = try await deploymentService.getStackOutputs(
            stackName: stackName
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

    private func verifyDeployment(stackName: String, awsConfig: AWSAuthConfiguration, withPostgres: Bool) async throws {
        let projectRoot = FileManager.default.currentDirectoryPath
        let deploymentService = DeploymentService(
            projectRoot: projectRoot,
            awsConfig: awsConfig
        )
        let cliService = CLIService.shared

        // Get API Gateway URL
        let outputs = try await deploymentService.getStackOutputs(
            stackName: stackName
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
}
