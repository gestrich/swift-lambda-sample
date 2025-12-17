import sdk_cli
import sdk_cli_node
import Foundation

/// Generic client for interacting with AWS CDK CLI
/// This client provides CDK operations without app-specific logic.
/// App-specific configuration (like skipPostgres, skipNATGateway) should be
/// passed via the context parameter in DeployOptions.
public actor CDKClient {
    private let cliClient: CLIClient
    private let cdkDirectory: String
    private let credentialProvider: AWSCredentialProvider

    public init(
        cdkDirectory: String,
        credentialProvider: AWSCredentialProvider,
        cliClient: CLIClient
    ) {
        self.cliClient = cliClient
        self.cdkDirectory = cdkDirectory
        self.credentialProvider = credentialProvider
    }

    // MARK: - Installation Check

    /// Check if CDK is installed (static method that only needs CLIClient)
    public static func isInstalled(cliClient: CLIClient) async -> Bool {
        do {
            let result = try await cliClient.executeForResult(Cdk.Version(), printCommand: false)
            return result.isSuccess
        } catch {
            return false
        }
    }

    // MARK: - Command Building

    /// Build command line with optional aws-vault wrapping
    private func buildCommandLine<C: CLICommand>(_ command: C) -> (command: String, arguments: [String]) where C.Program == Cdk {
        credentialProvider.buildCommandLine(command)
    }

    /// Build npm command line
    private func buildNpmCommandLine<C: CLICommand>(_ command: C) -> (command: String, arguments: [String]) where C.Program == Npm {
        return ("npm", command.commandArguments)
    }

    // MARK: - Deployment Operations

    /// Options for CDK deploy command
    public struct DeployOptions: Sendable {
        /// Stack name to deploy (nil deploys all stacks)
        public let stackName: String?

        /// Context key-value pairs passed to CDK (e.g., ["skipPostgres": "true"])
        public let context: [String: String]

        /// Whether to require approval for changes
        public let requireApproval: Bool

        /// Path to write outputs file
        public let outputsFile: String?

        public init(
            stackName: String? = nil,
            context: [String: String] = [:],
            requireApproval: Bool = false,
            outputsFile: String? = nil
        ) {
            self.stackName = stackName
            self.context = context
            self.requireApproval = requireApproval
            self.outputsFile = outputsFile
        }
    }

    /// Options for CDK destroy command
    public struct DestroyOptions: Sendable {
        /// Stack name to destroy (nil destroys all stacks)
        public let stackName: String?

        /// Skip confirmation prompts
        public let force: Bool

        public init(stackName: String? = nil, force: Bool = false) {
            self.stackName = stackName
            self.force = force
        }
    }

    // MARK: - Stream Methods

    /// Deploy CDK stack and return progress as an AsyncThrowingStream.
    /// This method does not use internal state - it yields progress directly.
    /// - Parameters:
    ///   - options: Deployment options
    ///   - output: Optional client-owned stream to receive raw CLI output
    /// - Returns: AsyncThrowingStream that yields CDKProgress updates
    public nonisolated func deployStream(
        options: DeployOptions = DeployOptions(),
        output: CLIOutputStream? = nil
    ) -> AsyncThrowingStream<CDKProgress, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    try await self.runDeployStream(
                        options: options,
                        output: output,
                        continuation: continuation
                    )
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Internal implementation for deployStream
    private func runDeployStream(
        options: DeployOptions,
        output: CLIOutputStream?,
        continuation: AsyncThrowingStream<CDKProgress, Error>.Continuation
    ) async throws {
        let nodeModulesPath = (cdkDirectory as NSString).appendingPathComponent("node_modules")
        if !FileManager.default.fileExists(atPath: nodeModulesPath) {
            continuation.yield(.installing)
            try await install(output: output)
        }

        continuation.yield(.building)
        try await build(output: output)

        continuation.yield(.deploying(DeploymentProgress()))

        let contextArray = options.context.map { "\($0.key)=\($0.value)" }

        let command = Cdk.Deploy(
            profile: credentialProvider.profileName,
            requireApproval: options.requireApproval ? "any" : "never",
            context: contextArray
        )

        let (execCommand, arguments) = buildCommandLine(command)

        let internalOutput = output ?? CLIOutputStream()
        let parser = CDKOutputParser()
        let accumulator = CDKProgressAccumulator()

        let parsingTask = Task {
            let stream = await internalOutput.makeStream()
            for await item in stream {
                guard !Task.isCancelled else { break }

                let text: String
                switch item {
                case .stdout(_, let t), .stderr(_, let t):
                    text = t
                default:
                    continue
                }

                for line in text.components(separatedBy: .newlines) {
                    if let event = parser.parse(line) {
                        accumulator.update(with: event)
                        let newProgress = accumulator.snapshot().toDeploymentProgress()
                        continuation.yield(.deploying(newProgress))
                    }
                }
            }
        }

        let result = try await cliClient.execute(
            command: execCommand,
            arguments: arguments,
            workingDirectory: cdkDirectory,
            environment: credentialProvider.environment,
            output: internalOutput
        )

        parsingTask.cancel()

        guard result.isSuccess else {
            throw CDKError.commandFailed(
                command: "cdk deploy",
                exitCode: result.exitCode,
                output: result.errorOutput
            )
        }

        continuation.yield(.deployed(outputs: [:]))
        continuation.finish()
    }

    /// Destroy CDK stack and return progress as an AsyncThrowingStream.
    /// This method does not use internal state - it yields progress directly.
    /// - Parameters:
    ///   - options: Destroy options
    ///   - output: Optional client-owned stream to receive raw CLI output
    /// - Returns: AsyncThrowingStream that yields CDKProgress updates
    public nonisolated func destroyStream(
        options: DestroyOptions = DestroyOptions(),
        output: CLIOutputStream? = nil
    ) -> AsyncThrowingStream<CDKProgress, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    try await self.runDestroyStream(
                        options: options,
                        output: output,
                        continuation: continuation
                    )
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Internal implementation for destroyStream
    private func runDestroyStream(
        options: DestroyOptions,
        output: CLIOutputStream?,
        continuation: AsyncThrowingStream<CDKProgress, Error>.Continuation
    ) async throws {
        continuation.yield(.destroying(DeploymentProgress()))

        let command = Cdk.Destroy(
            profile: credentialProvider.profileName,
            force: options.force
        )

        let (execCommand, arguments) = buildCommandLine(command)

        let internalOutput = output ?? CLIOutputStream()
        let parser = CDKOutputParser()
        let accumulator = CDKProgressAccumulator()

        let parsingTask = Task {
            let stream = await internalOutput.makeStream()
            for await item in stream {
                guard !Task.isCancelled else { break }

                let text: String
                switch item {
                case .stdout(_, let t), .stderr(_, let t):
                    text = t
                default:
                    continue
                }

                for line in text.components(separatedBy: .newlines) {
                    if let event = parser.parse(line) {
                        accumulator.update(with: event)
                        let newProgress = accumulator.snapshot().toDeploymentProgress()
                        continuation.yield(.destroying(newProgress))
                    }
                }
            }
        }

        let result = try await cliClient.execute(
            command: execCommand,
            arguments: arguments,
            workingDirectory: cdkDirectory,
            environment: credentialProvider.environment,
            output: internalOutput
        )

        parsingTask.cancel()

        guard result.isSuccess else {
            throw CDKError.commandFailed(
                command: "cdk destroy",
                exitCode: result.exitCode,
                output: result.errorOutput
            )
        }

        continuation.yield(.destroyed)
        continuation.finish()
    }

    /// Install CDK dependencies
    private func install(output: CLIOutputStream? = nil) async throws {
        let command = Npm.Install()
        let (execCommand, arguments) = buildNpmCommandLine(command)

        let result = try await cliClient.execute(
            command: execCommand,
            arguments: arguments,
            workingDirectory: cdkDirectory,
            output: output
        )

        guard result.isSuccess else {
            throw CDKError.commandFailed(
                command: "npm install",
                exitCode: result.exitCode,
                output: result.errorOutput
            )
        }
    }

    /// Build TypeScript CDK code
    private func build(output: CLIOutputStream? = nil) async throws {
        let command = Npm.Run(script: "build")
        let (execCommand, arguments) = buildNpmCommandLine(command)

        let result = try await cliClient.execute(
            command: execCommand,
            arguments: arguments,
            workingDirectory: cdkDirectory,
            output: output
        )

        guard result.isSuccess else {
            throw CDKError.commandFailed(
                command: "npm run build",
                exitCode: result.exitCode,
                output: result.errorOutput
            )
        }
    }

    /// Show differences between deployed stack and local code
    /// - Returns: Diff output string
    public func diff() async throws -> String {
        let command = Cdk.Diff(profile: credentialProvider.profileName)
        let (execCommand, arguments) = buildCommandLine(command)

        let result = try await cliClient.execute(
            command: execCommand,
            arguments: arguments,
            workingDirectory: cdkDirectory,
            environment: credentialProvider.environment
        )

        guard result.isSuccess else {
            throw CDKError.commandFailed(
                command: command.commandString,
                exitCode: result.exitCode,
                output: result.errorOutput
            )
        }

        return result.stdout
    }

    /// Synthesize CloudFormation template
    /// - Returns: Synthesized template output
    public func synth() async throws -> String {
        let command = Cdk.Synth(profile: credentialProvider.profileName)
        let (execCommand, arguments) = buildCommandLine(command)

        let result = try await cliClient.execute(
            command: execCommand,
            arguments: arguments,
            workingDirectory: cdkDirectory,
            environment: credentialProvider.environment,
            printCommand: false
        )

        guard result.isSuccess else {
            throw CDKError.commandFailed(
                command: command.commandString,
                exitCode: result.exitCode,
                output: result.errorOutput
            )
        }

        return result.stdout
    }

    /// List all stacks in the app
    /// - Returns: Array of stack names
    public func listStacks() async throws -> [String] {
        let command = Cdk.List(profile: credentialProvider.profileName)
        let (execCommand, arguments) = buildCommandLine(command)

        let result = try await cliClient.execute(
            command: execCommand,
            arguments: arguments,
            workingDirectory: cdkDirectory,
            environment: credentialProvider.environment,
            printCommand: false
        )

        guard result.isSuccess else {
            throw CDKError.commandFailed(
                command: command.commandString,
                exitCode: result.exitCode,
                output: result.errorOutput
            )
        }

        return result.stdout
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Setup Operations

    /// Bootstrap CDK (one-time setup for AWS account)
    public func bootstrap() async throws {
        let command = Cdk.Bootstrap(profile: credentialProvider.profileName)
        let (execCommand, arguments) = buildCommandLine(command)

        let result = try await cliClient.execute(
            command: execCommand,
            arguments: arguments,
            workingDirectory: cdkDirectory,
            environment: credentialProvider.environment
        )

        guard result.isSuccess else {
            throw CDKError.commandFailed(
                command: "cdk bootstrap",
                exitCode: result.exitCode,
                output: result.errorOutput
            )
        }
    }
}

// MARK: - Errors

public enum CDKError: LocalizedError {
    case commandFailed(command: String, exitCode: Int32, output: String)
    case buildFailed(String)
    case deployFailed(String)

    public var errorDescription: String? {
        switch self {
        case .commandFailed(let command, let exitCode, let output):
            return "Command '\(command)' failed with exit code \(exitCode): \(output)"
        case .buildFailed(let reason):
            return "CDK build failed: \(reason)"
        case .deployFailed(let reason):
            return "CDK deployment failed: \(reason)"
        }
    }
}
