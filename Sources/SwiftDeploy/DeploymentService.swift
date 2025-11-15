import Foundation

/// Service for managing CDK deployments
public actor DeploymentService {
    private let cliService: CLIService
    private let projectRoot: String

    public init(projectRoot: String) {
        self.cliService = CLIService.shared
        self.projectRoot = projectRoot
    }

    /// Deploy CDK stack with streaming output
    public func deploy(options: DeploymentOptions) async throws {
        print("\n📦 Starting CDK deployment...")

        let cdkPath = "\(projectRoot)/\(options.cdkDirectory)"

        // Build TypeScript first
        print("\n🔨 Building CDK TypeScript...")
        try await executeWithStreaming(
            command: "npm",
            arguments: ["run", "build"],
            workingDirectory: cdkPath,
            errorMessage: "CDK build failed"
        )

        // Deploy with CDK
        print("\n🚀 Deploying CDK stack...")
        var cdkArgs = [
            "deploy",
            "--profile", options.awsProfile,
            "--require-approval", "never"
        ]

        // Add context parameters for deployment options
        if options.skipPostgres {
            cdkArgs.append(contentsOf: ["--context", "skipPostgres=true"])
        }
        if options.skipNATGateway {
            cdkArgs.append(contentsOf: ["--context", "skipNATGateway=true"])
        }

        try await executeWithStreaming(
            command: "cdk",
            arguments: cdkArgs,
            workingDirectory: cdkPath,
            environment: ["AWS_PROFILE": options.awsProfile],
            errorMessage: "CDK deployment failed"
        )

        print("\n✅ CDK deployment completed successfully")
    }

    /// Poll CloudFormation stack status until deployment is complete
    public func pollDeploymentStatus(
        stackName: String = "SwiftLambdaSampleStack",
        awsProfile: String = "production"
    ) async throws {
        print("\n⏳ Polling deployment status...")

        var attempts = 0
        let maxAttempts = 60 // 5 minutes with 5-second intervals
        let pollInterval: UInt64 = 5_000_000_000 // 5 seconds in nanoseconds

        while attempts < maxAttempts {
            let result = try await cliService.execute(
                command: "aws",
                arguments: [
                    "cloudformation", "describe-stacks",
                    "--stack-name", stackName,
                    "--profile", awsProfile,
                    "--query", "Stacks[0].StackStatus",
                    "--output", "text"
                ],
                printCommand: false
            )

            guard result.isSuccess else {
                throw CLIError.deploymentFailed(reason: "Failed to query stack status: \(result.stderr)")
            }

            let status = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
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

    /// Tear down CDK stack with streaming output
    public func tearDown(awsProfile: String = "production", cdkDirectory: String = "cdk") async throws {
        print("\n🗑️  Starting CDK stack destruction...")

        let cdkPath = "\(projectRoot)/\(cdkDirectory)"

        // Verify CDK directory exists
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: cdkPath, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw CLIError.invalidWorkingDirectory("CDK directory not found at: \(cdkPath)")
        }

        try await executeWithStreaming(
            command: "cdk",
            arguments: [
                "destroy",
                "--profile", awsProfile,
                "--force"
            ],
            workingDirectory: cdkPath,
            environment: ["AWS_PROFILE": awsProfile],
            errorMessage: "CDK destroy failed"
        )

        print("\n✅ CDK stack destroyed successfully")
    }

    /// Get stack outputs
    public func getStackOutputs(
        stackName: String = "SwiftLambdaSampleStack",
        awsProfile: String = "production"
    ) async throws -> [String: String] {
        let result = try await cliService.execute(
            command: "aws",
            arguments: [
                "cloudformation", "describe-stacks",
                "--stack-name", stackName,
                "--profile", awsProfile,
                "--query", "Stacks[0].Outputs",
                "--output", "json"
            ],
            printCommand: false
        )

        guard result.isSuccess else {
            throw CLIError.deploymentFailed(reason: "Failed to get stack outputs: \(result.stderr)")
        }

        guard let data = result.stdout.data(using: .utf8),
              let outputs = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return [:]
        }

        var outputDict: [String: String] = [:]
        for output in outputs {
            if let key = output["OutputKey"] as? String,
               let value = output["OutputValue"] as? String {
                outputDict[key] = value
            }
        }

        return outputDict
    }

    // MARK: - Private Helpers

    /// Execute a command with streaming output
    private func executeWithStreaming(
        command: String,
        arguments: [String],
        workingDirectory: String,
        environment: [String: String]? = nil,
        errorMessage: String
    ) async throws {
        let stream = await cliService.stream(
            command: command,
            arguments: arguments,
            workingDirectory: workingDirectory,
            environment: environment,
            printCommand: true
        )

        var exitCode: Int32 = -1

        for await output in stream {
            switch output {
            case .stdout, .stderr:
                // Output is already printed in real-time by streamProcess
                break
            case .exit(let code):
                exitCode = code
            case .error(let error):
                throw error
            }
        }

        guard exitCode == 0 else {
            throw CLIError.deploymentFailed(reason: "\(errorMessage) (exit code: \(exitCode))")
        }
    }
}
