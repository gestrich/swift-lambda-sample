import Foundation

/// Service for interacting with AWS CDK
public actor CDKService {
    private let cliService: CLIService
    private let cdkDirectory: String
    private let awsProfile: String

    public init(
        cdkDirectory: String = "cdk",
        awsProfile: String
    ) {
        self.cliService = CLIService.shared
        self.cdkDirectory = cdkDirectory
        self.awsProfile = awsProfile
    }

    // MARK: - Build Operations

    /// Build TypeScript CDK code
    public func build() async throws {
        print("\n🔨 Building CDK TypeScript...")

        _ = try await cliService.execute(
            command: "npm",
            arguments: ["run", "build"],
            workingDirectory: cdkDirectory
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

        var arguments = [
            "deploy",
            "--profile", awsProfile,
            "--require-approval", options.requireApproval ? "any" : "never"
        ]

        // Add context parameters
        if options.skipPostgres {
            arguments.append(contentsOf: ["--context", "skipPostgres=true"])
        }
        if options.skipNATGateway {
            arguments.append(contentsOf: ["--context", "skipNATGateway=true"])
        }

        _ = try await cliService.execute(
            command: "cdk",
            arguments: arguments,
            workingDirectory: cdkDirectory,
            environment: ["AWS_PROFILE": awsProfile]
        )
    }

    /// Destroy CDK stack
    public func destroy(force: Bool = false) async throws {
        print("\n🗑️  Destroying CDK stack...")

        var arguments = [
            "destroy",
            "--profile", awsProfile
        ]

        if force {
            arguments.append("--force")
        }

        _ = try await cliService.execute(
            command: "cdk",
            arguments: arguments,
            workingDirectory: cdkDirectory,
            environment: ["AWS_PROFILE": awsProfile]
        )
    }

    /// Show differences between deployed stack and local code
    public func diff() async throws -> String {
        let result = try await cliService.execute(
            command: "cdk",
            arguments: [
                "diff",
                "--profile", awsProfile
            ],
            workingDirectory: cdkDirectory,
            environment: ["AWS_PROFILE": awsProfile]
        )

        guard result.isSuccess else {
            throw CLIError.commandFailed(
                command: "cdk diff",
                exitCode: result.exitCode,
                stderr: result.stderr
            )
        }

        return result.stdout
    }

    /// Synthesize CloudFormation template
    public func synth() async throws -> String {
        let result = try await cliService.execute(
            command: "cdk",
            arguments: [
                "synth",
                "--profile", awsProfile
            ],
            workingDirectory: cdkDirectory,
            environment: ["AWS_PROFILE": awsProfile],
            printCommand: false
        )

        guard result.isSuccess else {
            throw CLIError.commandFailed(
                command: "cdk synth",
                exitCode: result.exitCode,
                stderr: result.stderr
            )
        }

        return result.stdout
    }

    /// List all stacks in the app
    public func listStacks() async throws -> [String] {
        let result = try await cliService.execute(
            command: "cdk",
            arguments: [
                "list",
                "--profile", awsProfile
            ],
            workingDirectory: cdkDirectory,
            environment: ["AWS_PROFILE": awsProfile],
            printCommand: false
        )

        guard result.isSuccess else {
            throw CLIError.commandFailed(
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

        _ = try await cliService.execute(
            command: "cdk",
            arguments: [
                "bootstrap",
                "--profile", awsProfile
            ],
            workingDirectory: cdkDirectory,
            environment: ["AWS_PROFILE": awsProfile]
        )
    }
}
