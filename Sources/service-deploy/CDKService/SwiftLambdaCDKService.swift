import sdk_cli
import sdk_aws
import Foundation

/// App-specific CDK service for Swift Lambda Sample project.
/// Wraps the generic CDKClient from sdk-aws with app-specific configuration.
public actor SwiftLambdaCDKService {
    private let cdkService: sdk_aws.CDKClient
    private let stackName: String

    public init(
        cdkDirectory: String,
        credentialProvider: AWSCredentialProvider,
        cliService: CLIClient,
        stackName: String = CDKStackConfiguration.defaultStackName
    ) {
        self.cdkService = sdk_aws.CDKClient(
            cdkDirectory: cdkDirectory,
            credentialProvider: credentialProvider,
            cliService: cliService
        )
        self.stackName = stackName
    }

    /// Convenience initializer using AWSAuthConfiguration
    public init(
        projectRoot: String,
        awsConfig: AWSAuthConfiguration,
        cdkDirectory: String = CDKStackConfiguration.defaultCDKDirectory,
        stackName: String = CDKStackConfiguration.defaultStackName,
        cliService: CLIClient
    ) {
        let fullCdkPath = "\(projectRoot)/\(cdkDirectory)"
        self.cdkService = sdk_aws.CDKClient(
            cdkDirectory: fullCdkPath,
            credentialProvider: awsConfig.makeCredentialProvider(),
            cliService: cliService
        )
        self.stackName = stackName
    }

    // MARK: - App-Specific Deploy Options

    /// App-specific deployment options for Swift Lambda Sample
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

        /// Create options to skip both Postgres and NAT Gateway
        public static var minimal: DeployOptions {
            DeployOptions(withPostgres: false, withNATGateway: false)
        }

        /// Create options for full deployment
        public static var full: DeployOptions {
            DeployOptions(withPostgres: true, withNATGateway: true)
        }

        /// Convert to generic CDK deploy options with context
        internal func toCDKOptions() -> sdk_aws.CDKClient.DeployOptions {
            var context: [String: String] = [:]

            // CDK uses skipPostgres/skipNATGateway flags (inverted logic)
            if !withPostgres {
                context["skipPostgres"] = "true"
            }
            if !withNATGateway {
                context["skipNATGateway"] = "true"
            }

            return sdk_aws.CDKClient.DeployOptions(
                stackName: nil,  // Deploy default stack
                context: context,
                requireApproval: requireApproval,
                outputsFile: nil
            )
        }
    }

    // MARK: - Build Operations

    /// Build TypeScript CDK code
    public func build(output: CLIOutputStream? = nil) async throws {
        try await cdkService.build(output: output)
    }

    // MARK: - Deployment Operations

    /// Deploy CDK stack with app-specific options
    /// - Parameters:
    ///   - options: App-specific deployment options (withPostgres, withNATGateway)
    ///   - output: Optional client-owned stream to receive output
    public func deploy(options: DeployOptions = DeployOptions(), output: CLIOutputStream? = nil) async throws {
        try await cdkService.deploy(options: options.toCDKOptions(), output: output)
    }

    /// Destroy CDK stack
    /// - Parameters:
    ///   - force: If true, skip confirmation prompts
    ///   - output: Optional client-owned stream to receive output
    public func destroy(force: Bool = false, output: CLIOutputStream? = nil) async throws {
        let options = sdk_aws.CDKClient.DestroyOptions(stackName: nil, force: force)
        try await cdkService.destroy(options: options, output: output)
    }

    /// Show differences between deployed stack and local code
    public func diff() async throws -> String {
        try await cdkService.diff()
    }

    /// Synthesize CloudFormation template
    public func synth() async throws -> String {
        try await cdkService.synth()
    }

    /// List all stacks in the app
    public func listStacks() async throws -> [String] {
        try await cdkService.listStacks()
    }

    // MARK: - Installation & Setup

    /// Install CDK dependencies
    public func install(output: CLIOutputStream? = nil) async throws {
        try await cdkService.install(output: output)
    }

    /// Bootstrap CDK (one-time setup for AWS account)
    public func bootstrap() async throws {
        try await cdkService.bootstrap()
    }
}
