import Foundation

/// Service for interacting with AWS CDK
public actor CDKService {
    private let cliService: CLIService
    private let cdkDirectory: String
    private let awsProfile: String
    private let vaultService: AWSVaultService?

    public init(
        cdkDirectory: String = "cdk",
        awsConfig: AWSAuthConfiguration
    ) {
        self.cliService = CLIService.shared
        self.cdkDirectory = cdkDirectory
        self.awsProfile = awsConfig.profileName
        self.vaultService = awsConfig.useAWSVault ? AWSVaultService(profile: awsConfig.profileName) : nil
    }

    // MARK: - Command Building

    /// Build CDK command with optional aws-vault wrapping
    /// - Parameter arguments: CDK arguments (without "cdk" command)
    /// - Returns: Tuple with command and full arguments
    private func buildCommand(arguments: [String]) -> (command: String, arguments: [String]) {
        if let vaultService = vaultService {
            // Remove --profile flags (aws-vault handles auth via environment)
            let filteredArgs = AWSVaultService.removeProfileFlags(from: arguments)
            return vaultService.wrapCommand(command: "cdk", arguments: filteredArgs)
        } else {
            // Traditional approach with --profile
            return ("cdk", arguments)
        }
    }

    // MARK: - Build Operations

    /// Build TypeScript CDK code
    public func build() async throws {
        print("\n🔨 Building CDK TypeScript...")

        _ = try await cliService.execute(
            command: "npm",
            arguments: ["run", "build"],
            workingDirectory: cdkDirectory,
            inheritIO: true
        )
    }

    // MARK: - Deployment Operations

    public struct DeployOptions {
        public var skipPostgres: Bool = false
        public var skipNATGateway: Bool = false
        public var requireApproval: Bool = false

        public init(
            skipPostgres: Bool = false,
            skipNATGateway: Bool = false,
            requireApproval: Bool = false
        ) {
            self.skipPostgres = skipPostgres
            self.skipNATGateway = skipNATGateway
            self.requireApproval = requireApproval
        }
    }

    /// Deploy CDK stack
    public func deploy(options: DeployOptions = DeployOptions()) async throws {
        print("\n🚀 Deploying CDK stack...")

        var cdkArguments = [
            "deploy",
            "--profile", awsProfile,
            "--require-approval", options.requireApproval ? "any" : "never"
        ]

        // Add context parameters
        if options.skipPostgres {
            cdkArguments.append(contentsOf: ["--context", "skipPostgres=true"])
        }
        if options.skipNATGateway {
            cdkArguments.append(contentsOf: ["--context", "skipNATGateway=true"])
        }

        let (command, arguments) = buildCommand(arguments: cdkArguments)

        _ = try await cliService.execute(
            command: command,
            arguments: arguments,
            workingDirectory: cdkDirectory,
            environment: ["AWS_PROFILE": awsProfile],
            inheritIO: true
        )
    }

    /// Destroy CDK stack
    public func destroy(force: Bool = false) async throws {
        print("\n🗑️  Destroying CDK stack...")

        var cdkArguments = [
            "destroy",
            "--profile", awsProfile
        ]

        if force {
            cdkArguments.append("--force")
        }

        let (command, arguments) = buildCommand(arguments: cdkArguments)

        _ = try await cliService.execute(
            command: command,
            arguments: arguments,
            workingDirectory: cdkDirectory,
            environment: ["AWS_PROFILE": awsProfile],
            inheritIO: true
        )
    }

    /// Show differences between deployed stack and local code
    public func diff() async throws -> String {
        let (command, arguments) = buildCommand(arguments: [
            "diff",
            "--profile", awsProfile
        ])

        let result = try await cliService.execute(
            command: command,
            arguments: arguments,
            workingDirectory: cdkDirectory,
            environment: ["AWS_PROFILE": awsProfile]
        )

        guard result.isSuccess else {
            throw DeployError.commandFailed(
                command: "cdk diff",
                exitCode: result.exitCode,
                stderr: result.stderr
            )
        }

        return result.stdout
    }

    /// Synthesize CloudFormation template
    public func synth() async throws -> String {
        let (command, arguments) = buildCommand(arguments: [
            "synth",
            "--profile", awsProfile
        ])

        let result = try await cliService.execute(
            command: command,
            arguments: arguments,
            workingDirectory: cdkDirectory,
            environment: ["AWS_PROFILE": awsProfile],
            printCommand: false
        )

        guard result.isSuccess else {
            throw DeployError.commandFailed(
                command: "cdk synth",
                exitCode: result.exitCode,
                stderr: result.stderr
            )
        }

        return result.stdout
    }

    /// List all stacks in the app
    public func listStacks() async throws -> [String] {
        let (command, arguments) = buildCommand(arguments: [
            "list",
            "--profile", awsProfile
        ])

        let result = try await cliService.execute(
            command: command,
            arguments: arguments,
            workingDirectory: cdkDirectory,
            environment: ["AWS_PROFILE": awsProfile],
            printCommand: false
        )

        guard result.isSuccess else {
            throw DeployError.commandFailed(
                command: "cdk list",
                exitCode: result.exitCode,
                stderr: result.stderr
            )
        }

        return result.stdout
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Installation & Setup

    /// Install CDK dependencies
    public func install() async throws {
        print("\n📦 Installing CDK dependencies...")

        _ = try await cliService.execute(
            command: "npm",
            arguments: ["install"],
            workingDirectory: cdkDirectory
        )
    }

    /// Bootstrap CDK (one-time setup for AWS account)
    public func bootstrap() async throws {
        print("\n🔧 Bootstrapping CDK...")

        let (command, arguments) = buildCommand(arguments: [
            "bootstrap",
            "--profile", awsProfile
        ])

        _ = try await cliService.execute(
            command: command,
            arguments: arguments,
            workingDirectory: cdkDirectory,
            environment: ["AWS_PROFILE": awsProfile]
        )
    }
}
