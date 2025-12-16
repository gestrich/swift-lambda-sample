import sdk_cli
import Foundation

/// Generic client for interacting with AWS CDK CLI
/// This client provides CDK operations without app-specific logic.
/// App-specific configuration (like skipPostgres, skipNATGateway) should be
/// passed via the context parameter in DeployOptions.
public actor CDKClient {
    private let cliClient: CLIClient
    private let cdkDirectory: String
    private let credentialProvider: AWSCredentialProvider

    // MARK: - State Management

    /// Current state of the CDK client
    private var currentState: State = .idle

    /// Continuations for state stream subscribers
    private var continuations: [UUID: AsyncStream<State>.Continuation] = [:]

    public init(
        cdkDirectory: String,
        credentialProvider: AWSCredentialProvider,
        cliClient: CLIClient
    ) {
        self.cliClient = cliClient
        self.cdkDirectory = cdkDirectory
        self.credentialProvider = credentialProvider
    }

    // MARK: - State Stream

    /// Subscribe to state changes
    /// Returns an AsyncStream that yields state updates
    public nonisolated func states() -> AsyncStream<State> {
        AsyncStream { continuation in
            let id = UUID()

            Task {
                await self.addContinuation(id: id, continuation: continuation)

                continuation.onTermination = { @Sendable _ in
                    Task { await self.removeContinuation(id: id) }
                }
            }
        }
    }

    /// Get the current state (for synchronous queries)
    public func getState() -> State {
        currentState
    }

    /// Add a continuation to track
    private func addContinuation(id: UUID, continuation: AsyncStream<State>.Continuation) {
        continuations[id] = continuation
        continuation.yield(currentState)
    }

    /// Remove a continuation when stream is cancelled
    private func removeContinuation(id: UUID) {
        continuations.removeValue(forKey: id)
    }

    /// Publish a state change to all subscribers
    private func publish(_ state: State) {
        currentState = state
        for continuation in continuations.values {
            continuation.yield(state)
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

    // MARK: - Build Operations

    /// Build TypeScript CDK code
    /// - Parameter output: Optional client-owned stream to receive output
    public func build(output: CLIOutputStream? = nil) async throws {
        guard currentState.canDeploy else {
            throw CDKError.operationInProgress("build")
        }

        let nodeModulesPath = (cdkDirectory as NSString).appendingPathComponent("node_modules")
        if !FileManager.default.fileExists(atPath: nodeModulesPath) {
            try await install(output: output)
        }

        publish(.building)

        let command = Npm.Run(script: "build")
        let (execCommand, arguments) = buildNpmCommandLine(command)

        do {
            let result = try await cliClient.execute(
                command: execCommand,
                arguments: arguments,
                workingDirectory: cdkDirectory,
                output: output
            )

            guard result.isSuccess else {
                let error = CDKError.commandFailed(
                    command: "npm run build",
                    exitCode: result.exitCode,
                    output: result.errorOutput
                )
                publish(.failed(error: error.localizedDescription))
                throw error
            }

            publish(.idle)
        } catch {
            if case .failed = currentState {
                // Already published failure
            } else {
                publish(.failed(error: error.localizedDescription))
            }
            throw error
        }
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

    /// Deploy CDK stack
    /// - Parameters:
    ///   - options: Deployment options
    ///   - output: Optional client-owned stream to receive output
    public func deploy(options: DeployOptions = DeployOptions(), output: CLIOutputStream? = nil) async throws {
        guard currentState.canDeploy else {
            throw CDKError.operationInProgress("deploy")
        }

        let startTime = Date()
        publish(.deploying(progress: DeploymentProgress(), startTime: startTime))

        let contextArray = options.context.map { "\($0.key)=\($0.value)" }

        let command = Cdk.Deploy(
            profile: credentialProvider.profileName,
            requireApproval: options.requireApproval ? "any" : "never",
            context: contextArray
        )

        let (execCommand, arguments) = buildCommandLine(command)

        // Create internal output stream for progress parsing if needed
        let internalOutput = output ?? CLIOutputStream()
        let parser = CDKOutputParser()
        let accumulator = CDKProgressAccumulator()

        // Start progress parsing task
        let parsingTask = Task { [weak self] in
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
                        await self?.publishDeployProgress(newProgress, startTime: startTime)
                    }
                }
            }
        }

        do {
            let result = try await cliClient.execute(
                command: execCommand,
                arguments: arguments,
                workingDirectory: cdkDirectory,
                environment: credentialProvider.environment,
                output: internalOutput
            )

            parsingTask.cancel()

            guard result.isSuccess else {
                let error = CDKError.commandFailed(
                    command: "cdk deploy",
                    exitCode: result.exitCode,
                    output: result.errorOutput
                )
                publish(.failed(error: error.localizedDescription))
                throw error
            }

            publish(.deployed(outputs: [:]))
        } catch {
            parsingTask.cancel()
            if case .failed = currentState {
                // Already published failure
            } else {
                publish(.failed(error: error.localizedDescription))
            }
            throw error
        }
    }

    /// Helper to publish deploy progress from parsing task
    private func publishDeployProgress(_ progress: DeploymentProgress, startTime: Date) {
        publish(.deploying(progress: progress, startTime: startTime))
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

    /// Destroy CDK stack
    /// - Parameters:
    ///   - options: Destroy options
    ///   - output: Optional client-owned stream to receive output
    public func destroy(options: DestroyOptions = DestroyOptions(), output: CLIOutputStream? = nil) async throws {
        guard currentState.canDestroy else {
            throw CDKError.operationInProgress("destroy")
        }

        let startTime = Date()
        publish(.destroying(progress: DeploymentProgress(), startTime: startTime))

        let command = Cdk.Destroy(
            profile: credentialProvider.profileName,
            force: options.force
        )

        let (execCommand, arguments) = buildCommandLine(command)

        // Create internal output stream for progress parsing if needed
        let internalOutput = output ?? CLIOutputStream()
        let parser = CDKOutputParser()
        let accumulator = CDKProgressAccumulator()

        // Start progress parsing task
        let parsingTask = Task { [weak self] in
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
                        await self?.publishDestroyProgress(newProgress, startTime: startTime)
                    }
                }
            }
        }

        do {
            let result = try await cliClient.execute(
                command: execCommand,
                arguments: arguments,
                workingDirectory: cdkDirectory,
                environment: credentialProvider.environment,
                output: internalOutput
            )

            parsingTask.cancel()

            guard result.isSuccess else {
                let error = CDKError.commandFailed(
                    command: "cdk destroy",
                    exitCode: result.exitCode,
                    output: result.errorOutput
                )
                publish(.failed(error: error.localizedDescription))
                throw error
            }

            publish(.destroyed)
        } catch {
            parsingTask.cancel()
            if case .failed = currentState {
                // Already published failure
            } else {
                publish(.failed(error: error.localizedDescription))
            }
            throw error
        }
    }

    /// Helper to publish destroy progress from parsing task
    private func publishDestroyProgress(_ progress: DeploymentProgress, startTime: Date) {
        publish(.destroying(progress: progress, startTime: startTime))
    }

    // MARK: - Stateless Stream Methods

    /// Deploy CDK stack and return progress as an AsyncThrowingStream.
    /// This method does not use internal state - it yields progress directly.
    /// - Parameters:
    ///   - options: Deployment options
    ///   - output: Optional client-owned stream to receive raw CLI output
    /// - Returns: AsyncThrowingStream that yields CDKProgress updates
    public func deployStream(
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
            try await installWithoutPublish(output: output)
        }

        continuation.yield(.building)
        try await buildWithoutPublish(output: output)

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
    public func destroyStream(
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

    /// Install CDK dependencies without publishing state
    private func installWithoutPublish(output: CLIOutputStream? = nil) async throws {
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

    /// Build TypeScript CDK code without publishing state
    private func buildWithoutPublish(output: CLIOutputStream? = nil) async throws {
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

    // MARK: - Installation & Setup

    /// Install CDK dependencies
    /// - Parameter output: Optional client-owned stream to receive output
    public func install(output: CLIOutputStream? = nil) async throws {
        guard currentState.canDeploy else {
            throw CDKError.operationInProgress("install")
        }

        publish(.installing)

        let command = Npm.Install()
        let (execCommand, arguments) = buildNpmCommandLine(command)

        do {
            let result = try await cliClient.execute(
                command: execCommand,
                arguments: arguments,
                workingDirectory: cdkDirectory,
                output: output
            )

            guard result.isSuccess else {
                let error = CDKError.commandFailed(
                    command: "npm install",
                    exitCode: result.exitCode,
                    output: result.errorOutput
                )
                publish(.failed(error: error.localizedDescription))
                throw error
            }

            publish(.idle)
        } catch {
            if case .failed = currentState {
                // Already published failure
            } else {
                publish(.failed(error: error.localizedDescription))
            }
            throw error
        }
    }

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
    case operationInProgress(String)

    public var errorDescription: String? {
        switch self {
        case .commandFailed(let command, let exitCode, let output):
            return "Command '\(command)' failed with exit code \(exitCode): \(output)"
        case .buildFailed(let reason):
            return "CDK build failed: \(reason)"
        case .deployFailed(let reason):
            return "CDK deployment failed: \(reason)"
        case .operationInProgress(let operation):
            return "Cannot start operation: \(operation) is already in progress"
        }
    }
}

// MARK: - CDKClient State

extension CDKClient {
    /// State of the CDK client operations
    public enum State: Sendable, Equatable {
        /// No operation in progress
        case idle

        /// Installing npm dependencies
        case installing

        /// Building TypeScript CDK code
        case building

        /// Deploying CDK stack
        case deploying(progress: DeploymentProgress, startTime: Date)

        /// Successfully deployed with stack outputs
        case deployed(outputs: [String: String])

        /// Destroying CDK stack
        case destroying(progress: DeploymentProgress, startTime: Date)

        /// Successfully destroyed
        case destroyed

        /// Operation failed
        case failed(error: String)

        /// Whether an operation is currently in progress
        public var isBusy: Bool {
            switch self {
            case .idle, .deployed, .destroyed, .failed:
                return false
            case .installing, .building, .deploying, .destroying:
                return true
            }
        }

        /// Whether deploy operation can be started
        public var canDeploy: Bool {
            switch self {
            case .idle, .deployed, .failed, .destroyed:
                return true
            case .installing, .building, .deploying, .destroying:
                return false
            }
        }

        /// Whether destroy operation can be started
        public var canDestroy: Bool {
            switch self {
            case .idle, .deployed, .failed:
                return true
            case .installing, .building, .deploying, .destroying, .destroyed:
                return false
            }
        }

        /// Deployment progress (if in deploying/destroying state)
        public var progress: DeploymentProgress {
            switch self {
            case .deploying(let progress, _), .destroying(let progress, _):
                return progress
            default:
                return DeploymentProgress()
            }
        }

        /// Human-readable description of the current state
        public var description: String {
            switch self {
            case .idle:
                return "Idle"
            case .installing:
                return "Installing dependencies..."
            case .building:
                return "Building CDK..."
            case .deploying(let progress, let startTime):
                let elapsed = Int(Date().timeIntervalSince(startTime))
                let completed = progress.resources.filter { $0.status == .complete }.count
                let total = progress.resources.count
                if total > 0 {
                    return "Deploying... (\(completed)/\(total) resources, \(elapsed)s)"
                }
                return "Deploying... (\(elapsed)s)"
            case .deployed:
                return "Deployed"
            case .destroying(let progress, let startTime):
                let elapsed = Int(Date().timeIntervalSince(startTime))
                let completed = progress.resources.filter { $0.status == .complete }.count
                let total = progress.resources.count
                if total > 0 {
                    return "Destroying... (\(completed)/\(total) resources, \(elapsed)s)"
                }
                return "Destroying... (\(elapsed)s)"
            case .destroyed:
                return "Destroyed"
            case .failed(let error):
                return "Failed: \(error)"
            }
        }
    }
}
