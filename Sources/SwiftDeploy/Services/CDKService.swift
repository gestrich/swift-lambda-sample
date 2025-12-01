import CLIKit
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

    /// Build command line with optional aws-vault wrapping
    /// - Parameter command: The CDK command
    /// - Returns: Tuple with executable command and arguments
    private func buildCommandLine<C: CLICommand>(_ command: C) -> (command: String, arguments: [String]) where C.Program == Cdk {
        let arguments = command.commandArguments

        if let vaultService = vaultService {
            // Remove --profile flags (aws-vault handles auth via environment)
            let filteredArgs = AWSVaultService.removeProfileFlags(from: arguments)
            return vaultService.wrapCommand(command: "cdk", arguments: filteredArgs)
        } else {
            // Traditional approach
            return ("cdk", arguments)
        }
    }

    /// Build npm command line
    private func buildNpmCommandLine<C: CLICommand>(_ command: C) -> (command: String, arguments: [String]) where C.Program == Npm {
        return ("npm", command.commandArguments)
    }

    // MARK: - Build Operations

    /// Build TypeScript CDK code
    public func build() async throws {
        print("\n🔨 Building CDK TypeScript...")

        let command = Npm.Run(script: "build")
        let (execCommand, arguments) = buildNpmCommandLine(command)

        _ = try await cliService.execute(
            command: execCommand,
            arguments: arguments,
            workingDirectory: cdkDirectory,
            inheritIO: true
        )
    }

    // MARK: - Deployment Operations

    public struct DeployOptions: Sendable {
        public let skipPostgres: Bool
        public let skipNATGateway: Bool
        public let requireApproval: Bool

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

        // Build context array
        var context: [String] = []
        if options.skipPostgres {
            context.append("skipPostgres=true")
        }
        if options.skipNATGateway {
            context.append("skipNATGateway=true")
        }

        let command = Cdk.Deploy(
            profile: awsProfile,
            requireApproval: options.requireApproval ? "any" : "never",
            context: context
        )

        let (execCommand, arguments) = buildCommandLine(command)

        _ = try await cliService.execute(
            command: execCommand,
            arguments: arguments,
            workingDirectory: cdkDirectory,
            environment: ["AWS_PROFILE": awsProfile],
            inheritIO: true
        )
    }

    /// Destroy CDK stack
    public func destroy(force: Bool = false) async throws {
        print("\n🗑️  Destroying CDK stack...")

        let command = Cdk.Destroy(
            profile: awsProfile,
            force: force
        )

        let (execCommand, arguments) = buildCommandLine(command)

        _ = try await cliService.execute(
            command: execCommand,
            arguments: arguments,
            workingDirectory: cdkDirectory,
            environment: ["AWS_PROFILE": awsProfile],
            inheritIO: true
        )
    }

    /// Show differences between deployed stack and local code
    public func diff() async throws -> String {
        let command = Cdk.Diff(profile: awsProfile)
        let (execCommand, arguments) = buildCommandLine(command)

        let result = try await cliService.execute(
            command: execCommand,
            arguments: arguments,
            workingDirectory: cdkDirectory,
            environment: ["AWS_PROFILE": awsProfile]
        )

        guard result.isSuccess else {
            throw DeployError.commandFailed(
                command: command.commandString,
                exitCode: result.exitCode,
                stderr: result.stderr
            )
        }

        return result.stdout
    }

    /// Synthesize CloudFormation template
    public func synth() async throws -> String {
        let command = Cdk.Synth(profile: awsProfile)
        let (execCommand, arguments) = buildCommandLine(command)

        let result = try await cliService.execute(
            command: execCommand,
            arguments: arguments,
            workingDirectory: cdkDirectory,
            environment: ["AWS_PROFILE": awsProfile],
            printCommand: false
        )

        guard result.isSuccess else {
            throw DeployError.commandFailed(
                command: command.commandString,
                exitCode: result.exitCode,
                stderr: result.stderr
            )
        }

        return result.stdout
    }

    /// List all stacks in the app
    public func listStacks() async throws -> [String] {
        let command = Cdk.List(profile: awsProfile)
        let (execCommand, arguments) = buildCommandLine(command)

        let result = try await cliService.execute(
            command: execCommand,
            arguments: arguments,
            workingDirectory: cdkDirectory,
            environment: ["AWS_PROFILE": awsProfile],
            printCommand: false
        )

        guard result.isSuccess else {
            throw DeployError.commandFailed(
                command: command.commandString,
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

        let command = Npm.Install()
        let (execCommand, arguments) = buildNpmCommandLine(command)

        _ = try await cliService.execute(
            command: execCommand,
            arguments: arguments,
            workingDirectory: cdkDirectory
        )
    }

    /// Bootstrap CDK (one-time setup for AWS account)
    public func bootstrap() async throws {
        print("\n🔧 Bootstrapping CDK...")

        let command = Cdk.Bootstrap(profile: awsProfile)
        let (execCommand, arguments) = buildCommandLine(command)

        _ = try await cliService.execute(
            command: execCommand,
            arguments: arguments,
            workingDirectory: cdkDirectory,
            environment: ["AWS_PROFILE": awsProfile]
        )
    }
}
