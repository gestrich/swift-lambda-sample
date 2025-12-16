import sdk_cli
import Foundation

/// Generic service for interacting with AWS CloudFormation via CLI
/// This service provides CloudFormation operations without app-specific logic.
public actor CloudFormationClient {
    private let cliClient: CLIClient
    private let credentialProvider: AWSCredentialProvider

    // MARK: - State Management

    /// Current deployment state
    private var currentState: CloudFormationState = .unknown

    /// Continuations for state stream subscribers
    private var continuations: [UUID: AsyncStream<CloudFormationState>.Continuation] = [:]

    /// Task for monitoring in-progress operations
    private var monitorTask: Task<Void, Never>?

    public init(
        credentialProvider: AWSCredentialProvider,
        cliClient: CLIClient
    ) {
        self.cliClient = cliClient
        self.credentialProvider = credentialProvider
    }

    // MARK: - State Stream

    /// Subscribe to deployment state changes.
    /// Returns an AsyncStream that yields CloudFormationState updates.
    public nonisolated func states() -> AsyncStream<CloudFormationState> {
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

    /// Get the current deployment state
    public func getState() -> CloudFormationState {
        currentState
    }

    /// Add a continuation to track
    private func addContinuation(id: UUID, continuation: AsyncStream<CloudFormationState>.Continuation) {
        continuations[id] = continuation
        continuation.yield(currentState)
    }

    /// Remove a continuation when stream is cancelled
    private func removeContinuation(id: UUID) {
        continuations.removeValue(forKey: id)
    }

    /// Publish a deployment state change to all subscribers
    private func publish(_ state: CloudFormationState) {
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
        let command = Aws.CloudFormation.DescribeStacks(
            stackName: name,
            profile: credentialProvider.profileName,
            output: "json"
        )

        let (execCommand, arguments) = credentialProvider.buildCommandLine(command)

        let result = try await cliClient.execute(
            command: execCommand,
            arguments: arguments,
            environment: credentialProvider.environment,
            printCommand: false
        )

        guard result.isSuccess else {
            throw CloudFormationError.commandFailed(
                command: "aws cloudformation describe-stacks",
                exitCode: result.exitCode,
                output: result.output
            )
        }

        guard let data = result.stdout.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let stacks = json["Stacks"] as? [[String: Any]],
              let stack = stacks.first else {
            throw CloudFormationError.parseError("Failed to parse CloudFormation stack")
        }

        return stack
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
        do {
            _ = try await describeStack(name: name)
            return true
        } catch let error as CloudFormationError {
            if case .commandFailed(_, _, let output) = error,
               output.contains("does not exist") {
                return false
            }
            throw error
        }
    }

    // MARK: - Deployment State Query

    /// Query the deployment state of a CloudFormation stack.
    /// Maps CloudFormation stack status to a generic CloudFormationState and publishes it.
    /// - Parameter stackName: The stack name
    /// - Returns: CloudFormationState based on stack status
    /// - Throws: DeploymentError.credentialExpired for auth issues, DeploymentError.unknown for other errors
    public func queryState(stackName: String) async throws -> CloudFormationState {
        publish(.loading)

        do {
            let stackStatus = try await getStackStatus(name: stackName)

            let state: CloudFormationState
            switch stackStatus {
            case StackStatus.createComplete, StackStatus.updateComplete:
                let outputs = try await getStackOutputs(name: stackName)
                state = .deployed(outputs: outputs)

            case StackStatus.createInProgress,
                 StackStatus.updateInProgress,
                 StackStatus.updateCompleteCleanupInProgress:
                let startTime = await getOperationStartTime(stackName: stackName)
                state = .deploying(
                    operation: "Updating",
                    progress: DeploymentProgress(),
                    startTime: startTime
                )

            case StackStatus.deleteInProgress:
                let startTime = await getOperationStartTime(stackName: stackName)
                state = .destroying(progress: DeploymentProgress(), startTime: startTime)

            case StackStatus.createFailed,
                 StackStatus.updateFailed,
                 StackStatus.rollbackComplete,
                 StackStatus.rollbackFailed,
                 StackStatus.deleteFailed:
                state = .failed(reason: stackStatus)

            default:
                let outputs = try await getStackOutputs(name: stackName)
                state = .deployed(outputs: outputs)
            }

            publish(state)
            return state
        } catch {
            let errorMessage = error.localizedDescription

            if DeploymentError.isCredentialError(errorMessage) {
                let state = CloudFormationState.credentialExpired(message: errorMessage)
                publish(state)
                throw DeploymentError.credentialExpired(message: errorMessage)
            } else if DeploymentError.isStackNotFoundError(errorMessage) {
                let state = CloudFormationState.notDeployed
                publish(state)
                return state
            } else {
                let state = CloudFormationState.failed(reason: errorMessage)
                publish(state)
                throw DeploymentError.unknown(message: errorMessage)
            }
        }
    }

    // MARK: - Monitoring

    /// Start monitoring an in-progress operation.
    /// Publishes state updates via states() as progress changes.
    /// Monitoring stops automatically when the operation completes.
    /// - Parameter stackName: The stack name to monitor
    public func startMonitoring(stackName: String) {
        guard monitorTask == nil else { return }

        monitorTask = Task {
            await runMonitorLoop(stackName: stackName)
        }
    }

    /// Stop monitoring the current operation
    public func stopMonitoring() {
        monitorTask?.cancel()
        monitorTask = nil
    }

    /// Whether monitoring is currently active
    public var isMonitoring: Bool {
        monitorTask != nil
    }

    private func runMonitorLoop(stackName: String) async {
        var pollCount = 0
        let startTime = currentState.operationStartTime ?? Date()
        let operation = currentState.operationName ?? "Updating"

        while !Task.isCancelled {
            pollCount += 1

            do {
                let events = try await getStackEvents(name: stackName, limit: 50)
                let newProgress = DeploymentProgress.from(
                    events: events,
                    since: nil,
                    pollCount: pollCount
                )

                // Publish updated state with new progress
                switch currentState {
                case .deploying:
                    publish(.deploying(operation: operation, progress: newProgress, startTime: startTime))
                case .destroying:
                    publish(.destroying(progress: newProgress, startTime: startTime))
                default:
                    break
                }

                // Check if complete
                let status = try await getStackStatus(name: stackName)
                if !StackStatus.isInProgress(status) {
                    _ = try await queryState(stackName: stackName)
                    monitorTask = nil
                    return
                }
            } catch {
                // Continue polling on transient errors
            }

            do {
                try await Task.sleep(for: .seconds(2))
            } catch {
                break
            }
        }

        monitorTask = nil
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

    // MARK: - Stateless Query Methods

    /// Query the deployment state of a CloudFormation stack without publishing to subscribers.
    /// This is a one-shot query that returns the state directly.
    /// - Parameter stackName: The stack name
    /// - Returns: CloudFormationState based on stack status
    /// - Throws: DeploymentError.credentialExpired for auth issues, DeploymentError.unknown for other errors
    public func queryStateOnce(stackName: String) async throws -> CloudFormationState {
        do {
            let stackStatus = try await getStackStatus(name: stackName)

            switch stackStatus {
            case StackStatus.createComplete, StackStatus.updateComplete:
                let outputs = try await getStackOutputs(name: stackName)
                return .deployed(outputs: outputs)

            case StackStatus.createInProgress,
                 StackStatus.updateInProgress,
                 StackStatus.updateCompleteCleanupInProgress:
                let startTime = await getOperationStartTime(stackName: stackName)
                return .deploying(
                    operation: "Updating",
                    progress: DeploymentProgress(),
                    startTime: startTime
                )

            case StackStatus.deleteInProgress:
                let startTime = await getOperationStartTime(stackName: stackName)
                return .destroying(progress: DeploymentProgress(), startTime: startTime)

            case StackStatus.createFailed,
                 StackStatus.updateFailed,
                 StackStatus.rollbackComplete,
                 StackStatus.rollbackFailed,
                 StackStatus.deleteFailed:
                return .failed(reason: stackStatus)

            default:
                let outputs = try await getStackOutputs(name: stackName)
                return .deployed(outputs: outputs)
            }
        } catch {
            let errorMessage = error.localizedDescription

            if DeploymentError.isCredentialError(errorMessage) {
                throw DeploymentError.credentialExpired(message: errorMessage)
            } else if DeploymentError.isStackNotFoundError(errorMessage) {
                return .notDeployed
            } else {
                throw DeploymentError.unknown(message: errorMessage)
            }
        }
    }

    /// Monitor a CloudFormation stack and return a stream of state updates.
    /// The stream completes when the stack operation finishes (success or failure).
    /// - Parameters:
    ///   - stackName: The stack name to monitor
    ///   - pollInterval: How often to poll for updates (default: 2 seconds)
    /// - Returns: AsyncThrowingStream that yields CloudFormationState updates
    public nonisolated func monitorStream(
        stackName: String,
        pollInterval: Duration = .seconds(2)
    ) -> AsyncThrowingStream<CloudFormationState, Error> {
        AsyncThrowingStream { continuation in
            Task {
                await self.runMonitorStreamLoop(
                    stackName: stackName,
                    pollInterval: pollInterval,
                    continuation: continuation
                )
            }
        }
    }

    /// Internal method to run the monitoring loop for monitorStream
    private func runMonitorStreamLoop(
        stackName: String,
        pollInterval: Duration,
        continuation: AsyncThrowingStream<CloudFormationState, Error>.Continuation
    ) async {
        var pollCount = 0
        var startTime: Date?
        var operation: String = "Updating"

        // Get initial state to determine operation type and start time
        do {
            let initialState = try await queryStateOnce(stackName: stackName)
            startTime = initialState.operationStartTime ?? Date()
            operation = initialState.operationName ?? "Updating"
            continuation.yield(initialState)

            // If not in progress, we're done
            if !initialState.isBusy {
                continuation.finish()
                return
            }
        } catch {
            continuation.finish(throwing: error)
            return
        }

        let operationStartTime = startTime ?? Date()

        // Poll until complete
        while !Task.isCancelled {
            pollCount += 1

            do {
                try await Task.sleep(for: pollInterval)

                let events = try await getStackEvents(name: stackName, limit: 50)
                let newProgress = DeploymentProgress.from(
                    events: events,
                    since: nil,
                    pollCount: pollCount
                )

                // Check current status
                let status = try await getStackStatus(name: stackName)

                if StackStatus.isInProgress(status) {
                    // Still in progress - yield updated state
                    let state: CloudFormationState
                    if StackStatus.isDeleting(status) {
                        state = .destroying(progress: newProgress, startTime: operationStartTime)
                    } else {
                        state = .deploying(operation: operation, progress: newProgress, startTime: operationStartTime)
                    }
                    continuation.yield(state)
                } else {
                    // Operation complete - get final state and finish
                    let finalState = try await queryStateOnce(stackName: stackName)
                    continuation.yield(finalState)
                    continuation.finish()
                    return
                }
            } catch {
                // On error, try to finish gracefully
                continuation.finish(throwing: error)
                return
            }
        }

        // Task was cancelled
        continuation.finish()
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

