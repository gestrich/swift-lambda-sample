import sdk_cli
import Foundation

/// Generic service for interacting with AWS CloudFormation via CLI
/// This service provides CloudFormation operations without app-specific logic.
public actor CloudFormationClient {
    private let cliClient: CLIClient
    private let credentialProvider: AWSCredentialProvider

    // MARK: - State Management

    /// Current state of the CloudFormation client
    private var currentState: State = .idle

    /// Continuations for state stream subscribers
    private var continuations: [UUID: AsyncStream<State>.Continuation] = [:]

    public init(
        credentialProvider: AWSCredentialProvider,
        cliClient: CLIClient
    ) {
        self.cliClient = cliClient
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

    // MARK: - Command Execution

    /// Execute a typed AWS CLI command
    private func execute<C: CLICommand, P: CLIOutputParser>(
        _ command: C,
        parser: P,
        printCommand: Bool = false
    ) async throws -> P.Output where C.Program == Aws {
        let (execCommand, arguments) = credentialProvider.buildCommandLine(command)

        let result = try await cliClient.execute(
            command: execCommand,
            arguments: arguments,
            environment: credentialProvider.environment,
            printCommand: printCommand
        )

        guard result.isSuccess else {
            throw CloudFormationError.commandFailed(
                command: command.commandString,
                exitCode: result.exitCode,
                output: result.output
            )
        }

        return try parser.parse(result.stdout)
    }

    /// Execute a typed AWS CLI command and return raw output
    private func execute<C: CLICommand>(
        _ command: C,
        printCommand: Bool = false
    ) async throws -> String where C.Program == Aws {
        try await execute(command, parser: StringParser(), printCommand: printCommand)
    }

    // MARK: - Stack Operations

    /// Describe a CloudFormation stack
    /// - Parameter name: The stack name
    /// - Returns: Stack information as a dictionary
    public func describeStack(name: String) async throws -> [String: Any] {
        publish(.querying(operation: "describeStack"))

        let command = Aws.CloudFormation.DescribeStacks(
            stackName: name,
            profile: credentialProvider.profileName,
            output: "json"
        )

        let (execCommand, arguments) = credentialProvider.buildCommandLine(command)

        do {
            let result = try await cliClient.execute(
                command: execCommand,
                arguments: arguments,
                environment: credentialProvider.environment,
                printCommand: false
            )

            guard result.isSuccess else {
                let error = CloudFormationError.commandFailed(
                    command: "aws cloudformation describe-stacks",
                    exitCode: result.exitCode,
                    output: result.output
                )
                publish(.failed(error: error.localizedDescription))
                throw error
            }

            guard let data = result.stdout.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let stacks = json["Stacks"] as? [[String: Any]],
                  let stack = stacks.first else {
                let error = CloudFormationError.parseError("Failed to parse CloudFormation stack")
                publish(.failed(error: error.localizedDescription))
                throw error
            }

            publish(.ready(stackExists: true))
            return stack
        } catch {
            if case .failed = currentState {
                // Already published failure
            } else {
                publish(.failed(error: error.localizedDescription))
            }
            throw error
        }
    }

    /// Get stack status
    /// - Parameter name: The stack name
    /// - Returns: Stack status string
    public func getStackStatus(name: String) async throws -> String {
        let command = Aws.CloudFormation.DescribeStacks(
            stackName: name,
            profile: credentialProvider.profileName,
            output: "text",
            query: "Stacks[0].StackStatus"
        )

        return try await execute(command)
    }

    /// Get stack outputs as a dictionary
    /// - Parameter name: The stack name
    /// - Returns: Dictionary of output key to value
    public func getStackOutputs(name: String) async throws -> [String: String] {
        let stack = try await describeStack(name: name)

        guard let outputs = stack["Outputs"] as? [[String: Any]] else {
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

    /// Get a specific stack output value
    /// - Parameters:
    ///   - stackName: The stack name
    ///   - outputKey: The output key to retrieve
    /// - Returns: The output value
    public func getStackOutput(stackName: String, outputKey: String) async throws -> String {
        let command = Aws.CloudFormation.DescribeStacks(
            stackName: stackName,
            profile: credentialProvider.profileName,
            output: "text",
            query: "Stacks[0].Outputs[?OutputKey==`\(outputKey)`].OutputValue"
        )

        let value = try await execute(command)

        guard !value.isEmpty else {
            throw CloudFormationError.outputNotFound(key: outputKey, stackName: stackName)
        }

        return value
    }

    /// Describe stack resources
    /// - Parameter name: The stack name
    /// - Returns: Array of stack resources
    public func describeStackResources(name: String) async throws -> [CloudFormationStackResource] {
        let command = Aws.CloudFormation.DescribeStackResources(
            stackName: name,
            profile: credentialProvider.profileName,
            output: "json"
        )

        return try await execute(command, parser: CloudFormationStackResourcesParser())
    }

    /// Get stack events for deployment progress tracking
    /// - Parameters:
    ///   - name: The stack name
    ///   - limit: Maximum number of events to return (default: 50)
    /// - Returns: Array of stack events
    public func getStackEvents(name: String, limit: Int = 50) async throws -> [CloudFormationStackEvent] {
        let command = Aws.CloudFormation.DescribeStackEvents(
            stackName: name,
            profile: credentialProvider.profileName,
            output: "json"
        )

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let parser = JSONOutputParser<CloudFormationStackEventsResponse>(decoder: decoder)

        let response = try await execute(command, parser: parser)
        return Array(response.StackEvents.prefix(limit))
    }

    /// Check if a stack exists
    /// - Parameter name: The stack name
    /// - Returns: True if the stack exists
    public func stackExists(name: String) async throws -> Bool {
        publish(.querying(operation: "stackExists"))

        do {
            _ = try await describeStack(name: name)
            publish(.ready(stackExists: true))
            return true
        } catch let error as CloudFormationError {
            if case .commandFailed(_, _, let output) = error,
               output.contains("does not exist") {
                publish(.ready(stackExists: false))
                return false
            }
            publish(.failed(error: error.localizedDescription))
            throw error
        }
    }

    // MARK: - Deployment State Query

    /// Query the deployment state of a CloudFormation stack.
    /// Maps CloudFormation stack status to a generic DeploymentState.
    /// - Parameter stackName: The stack name
    /// - Returns: DeploymentState based on stack status
    /// - Throws: DeploymentError.credentialExpired for auth issues, DeploymentError.unknown for other errors
    public func queryDeploymentState(stackName: String) async throws -> DeploymentState {
        publish(.querying(operation: "queryDeploymentState"))

        do {
            let stackStatus = try await getStackStatus(name: stackName)

            switch stackStatus {
            case StackStatus.createComplete, StackStatus.updateComplete:
                let outputs = try await getStackOutputs(name: stackName)
                publish(.ready(stackExists: true))
                return .deployed(outputs: outputs)

            case StackStatus.createInProgress,
                 StackStatus.updateInProgress,
                 StackStatus.updateCompleteCleanupInProgress:
                let startTime = await getOperationStartTime(stackName: stackName)
                publish(.ready(stackExists: true))
                return .deploying(
                    operation: "Updating",
                    progress: DeploymentProgress(),
                    startTime: startTime
                )

            case StackStatus.deleteInProgress:
                let startTime = await getOperationStartTime(stackName: stackName)
                publish(.ready(stackExists: true))
                return .destroying(progress: DeploymentProgress(), startTime: startTime)

            case StackStatus.createFailed,
                 StackStatus.updateFailed,
                 StackStatus.rollbackComplete,
                 StackStatus.rollbackFailed,
                 StackStatus.deleteFailed:
                publish(.ready(stackExists: true))
                return .failed(reason: stackStatus)

            default:
                let outputs = try await getStackOutputs(name: stackName)
                publish(.ready(stackExists: true))
                return .deployed(outputs: outputs)
            }
        } catch {
            let errorMessage = error.localizedDescription

            if DeploymentError.isCredentialError(errorMessage) {
                publish(.failed(error: errorMessage))
                throw DeploymentError.credentialExpired(message: errorMessage)
            } else if DeploymentError.isStackNotFoundError(errorMessage) {
                publish(.ready(stackExists: false))
                return .notDeployed
            } else {
                publish(.failed(error: errorMessage))
                throw DeploymentError.unknown(message: errorMessage)
            }
        }
    }

    /// Get the start time of the current in-progress operation from stack events
    /// - Parameter stackName: The stack name
    /// - Returns: The earliest IN_PROGRESS timestamp for the stack, or current date if not found
    private func getOperationStartTime(stackName: String) async -> Date {
        guard let events = try? await getStackEvents(name: stackName, limit: 50) else {
            return Date()
        }

        return events
            .filter { $0.logicalResourceId == stackName && $0.resourceStatus.contains("IN_PROGRESS") }
            .map { $0.timestamp }
            .min() ?? Date()
    }
}

// MARK: - Errors

public enum CloudFormationError: LocalizedError {
    case commandFailed(command: String, exitCode: Int32, output: String)
    case parseError(String)
    case outputNotFound(key: String, stackName: String)
    case stackNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .commandFailed(let command, let exitCode, let output):
            return "Command '\(command)' failed with exit code \(exitCode): \(output)"
        case .parseError(let reason):
            return "Failed to parse CloudFormation output: \(reason)"
        case .outputNotFound(let key, let stackName):
            return "Output key '\(key)' not found in stack '\(stackName)'"
        case .stackNotFound(let name):
            return "Stack '\(name)' not found"
        }
    }
}

// MARK: - CloudFormationClient State

extension CloudFormationClient {
    /// State of the CloudFormation client operations
    public enum State: Sendable, Equatable {
        /// No operation in progress
        case idle

        /// Querying CloudFormation (describe stacks, get outputs, etc.)
        case querying(operation: String)

        /// Successfully retrieved stack data
        case ready(stackExists: Bool)

        /// Operation failed
        case failed(error: String)

        /// Whether an operation is currently in progress
        public var isBusy: Bool {
            switch self {
            case .idle, .ready, .failed:
                return false
            case .querying:
                return true
            }
        }

        /// Human-readable description of the current state
        public var description: String {
            switch self {
            case .idle:
                return "Idle"
            case .querying(let operation):
                return "Querying: \(operation)..."
            case .ready(let stackExists):
                return stackExists ? "Stack ready" : "No stack found"
            case .failed(let error):
                return "Failed: \(error)"
            }
        }
    }
}
