import Foundation

/// Service for managing CDK deployments
public actor DeploymentService {
    private let cdkService: CDKService
    private let awsService: AWSCLIService
    private let projectRoot: String

    public init(
        projectRoot: String,
        awsProfile: String,
        cdkDirectory: String = "cdk"
    ) {
        self.projectRoot = projectRoot
        self.cdkService = CDKService(
            cdkDirectory: "\(projectRoot)/\(cdkDirectory)",
            awsProfile: awsProfile
        )
        self.awsService = AWSCLIService(profile: awsProfile)
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
}
