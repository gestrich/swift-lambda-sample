import sdk_cli
import Foundation

/// Generic state machine for monitoring CloudFormation stack deployments.
/// This actor provides state observation and polling for CloudFormation operations
/// without any app-specific logic.
public actor DeploymentMonitor {

    // MARK: - Private State

    private var state: DeploymentState = .unknown
    private var continuations: [UUID: AsyncStream<DeploymentState>.Continuation] = [:]
    private let stackName: String

    // MARK: - Services

    private let cloudFormation: CloudFormationClient

    // MARK: - Initialization

    public init(
        stackName: String,
        cloudFormation: CloudFormationClient
    ) {
        self.stackName = stackName
        self.cloudFormation = cloudFormation
    }

    // MARK: - State Observation

    /// Stream of state changes. Immediately yields current state upon subscription.
    /// If state is `.unknown`, automatically triggers a refresh.
    public func states() -> AsyncStream<DeploymentState> {
        if state == .unknown {
            Task { await refresh() }
        }

        return AsyncStream { continuation in
            let id = UUID()
            self.continuations[id] = continuation
            continuation.yield(self.state)

            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeContinuation(id) }
            }
        }
    }

    /// Get the current state without subscribing to updates
    public func currentState() -> DeploymentState {
        state
    }

    private func removeContinuation(_ id: UUID) {
        continuations.removeValue(forKey: id)
    }

    /// Publish a new state to all observers
    public func publish(_ newState: DeploymentState) {
        state = newState
        for continuation in continuations.values {
            continuation.yield(newState)
        }
    }

    // MARK: - Public Operations

    /// Refresh state from AWS CloudFormation
    public func refresh() async {
        guard !state.isBusy else { return }

        publish(.loading)

        do {
            let newState = try await queryCurrentState()
            publish(newState)

            if newState.isBusy {
                await monitorExistingOperation()
            }
        } catch DeploymentError.credentialExpired(let message) {
            publish(.credentialExpired(message: message))
        } catch {
            publish(.failed(reason: error.localizedDescription))
        }
    }

    // MARK: - CloudFormation Queries

    /// Get the current stack status
    public func getStackStatus() async throws -> String {
        try await cloudFormation.getStackStatus(name: stackName)
    }

    /// Get stack outputs as a dictionary
    public func getStackOutputs() async throws -> [String: String] {
        try await cloudFormation.getStackOutputs(name: stackName)
    }

    /// Get stack resources
    public func getStackResources() async throws -> [CloudFormationStackResource] {
        try await cloudFormation.describeStackResources(name: stackName)
    }

    /// Get stack events for progress tracking
    public func getStackEvents(limit: Int = 50) async throws -> [CloudFormationStackEvent] {
        try await cloudFormation.getStackEvents(name: stackName, limit: limit)
    }

    /// Get the start time of the current operation from CloudFormation events.
    /// Returns the earliest IN_PROGRESS timestamp for the stack resource itself.
    public func getOperationStartTime() async -> Date? {
        guard let events = try? await getStackEvents() else { return nil }

        return events
            .filter { $0.logicalResourceId == stackName && $0.resourceStatus.contains("IN_PROGRESS") }
            .map { $0.timestamp }
            .min()
    }

    // MARK: - State Query

    /// Query the current deployment state from CloudFormation
    public func queryCurrentState() async throws -> DeploymentState {
        do {
            let stackStatus = try await getStackStatus()

            switch stackStatus {
            case StackStatus.createComplete,
                 StackStatus.updateComplete:
                let outputs = try await getStackOutputs()
                return .deployed(outputs: outputs)

            case StackStatus.createInProgress,
                 StackStatus.updateInProgress,
                 StackStatus.updateCompleteCleanupInProgress:
                let startTime = await getOperationStartTime() ?? Date()
                return .deploying(operation: "Updating", progress: DeploymentProgress(), startTime: startTime)

            case StackStatus.deleteInProgress:
                let startTime = await getOperationStartTime() ?? Date()
                return .destroying(progress: DeploymentProgress(), startTime: startTime)

            case StackStatus.createFailed,
                 StackStatus.updateFailed,
                 StackStatus.rollbackComplete,
                 StackStatus.rollbackFailed,
                 StackStatus.deleteFailed:
                return .failed(reason: stackStatus)

            default:
                let outputs = try await getStackOutputs()
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

    // MARK: - Progress Monitoring

    /// Monitor an existing in-progress operation by polling CloudFormation
    public func monitorExistingOperation() async {
        var pollCount = 0
        let startTime = state.operationStartTime ?? Date()

        while !Task.isCancelled {
            pollCount += 1

            do {
                let events = try await getStackEvents()
                let progress = DeploymentProgress.from(
                    events: events,
                    since: nil,
                    pollCount: pollCount
                )

                if case .deploying(let op, _, _) = state {
                    publish(.deploying(operation: op, progress: progress, startTime: startTime))
                } else if case .destroying = state {
                    publish(.destroying(progress: progress, startTime: startTime))
                }

                let status = try await getStackStatus()

                if !StackStatus.isInProgress(status) {
                    let finalState = try await queryCurrentState()
                    publish(finalState)
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
    }

}

// MARK: - CDK Output Parsing

/// Parser for CDK CLI output lines to extract deployment events
public class CDKOutputParser {
    private let resourcePattern = #"(\S+)\s*\|\s*(\d+\/\d+)\s*\|\s*(\S+)\s*\|\s*(\S+(?:\s+\S+)*)\s*\|\s*(.+)"#
    private var regex: NSRegularExpression?

    public init() {
        regex = try? NSRegularExpression(pattern: resourcePattern, options: [])
    }

    public func parse(_ line: String) -> CDKResourceEvent? {
        guard let regex = regex else { return nil }
        let range = NSRange(line.startIndex..., in: line)

        guard let match = regex.firstMatch(in: line, options: [], range: range) else {
            return nil
        }

        func extractGroup(_ index: Int) -> String? {
            guard index < match.numberOfRanges,
                  let range = Range(match.range(at: index), in: line) else {
                return nil
            }
            return String(line[range])
        }

        guard let timestamp = extractGroup(1),
              let progress = extractGroup(2),
              let action = extractGroup(3),
              let resourceType = extractGroup(4),
              let resourceName = extractGroup(5) else {
            return nil
        }

        return CDKResourceEvent(
            timestamp: timestamp,
            progress: progress,
            action: action,
            resourceType: resourceType,
            resourceName: resourceName.trimmingCharacters(in: .whitespaces)
        )
    }
}

/// A single resource event parsed from CDK output
public struct CDKResourceEvent: Sendable {
    public let timestamp: String
    public let progress: String
    public let action: String
    public let resourceType: String
    public let resourceName: String

    public var isComplete: Bool {
        action.lowercased().contains("complete")
    }

    public var isInProgress: Bool {
        action.lowercased().contains("progress") || action.lowercased().contains("creating") || action.lowercased().contains("updating")
    }

    public var isFailed: Bool {
        action.lowercased().contains("failed") || action.lowercased().contains("rollback")
    }
}

/// Accumulator for tracking CDK deployment progress from output stream
public class CDKProgressAccumulator: @unchecked Sendable {
    private var resources: [String: CDKResourceEvent] = [:]
    private var totalResources: Int?
    private let lock = NSLock()

    public init() {}

    public func update(with event: CDKResourceEvent) {
        lock.lock()
        defer { lock.unlock() }

        resources[event.resourceName] = event

        if let progressParts = event.progress.split(separator: "/").map({ Int($0) }) as? [Int?],
           progressParts.count == 2,
           let total = progressParts[1] {
            totalResources = total
        }
    }

    public func snapshot() -> CDKProgressSnapshot {
        lock.lock()
        defer { lock.unlock() }

        let completed = resources.values.filter { $0.isComplete }.count
        let inProgress = resources.values.filter { $0.isInProgress }.count
        let failed = resources.values.filter { $0.isFailed }.count
        let total = totalResources ?? resources.count

        return CDKProgressSnapshot(
            completedCount: completed,
            inProgressCount: inProgress,
            failedCount: failed,
            totalCount: total,
            resources: Array(resources.values)
        )
    }
}

/// Snapshot of CDK deployment progress
public struct CDKProgressSnapshot: Sendable {
    public let completedCount: Int
    public let inProgressCount: Int
    public let failedCount: Int
    public let totalCount: Int
    public let resources: [CDKResourceEvent]

    public func toDeploymentProgress() -> DeploymentProgress {
        let resourceProgresses = resources.map { event -> ResourceProgress in
            let status: ResourceStatus
            if event.isComplete {
                status = .complete
            } else if event.isFailed {
                status = .failed(reason: nil)
            } else if event.isInProgress {
                status = .inProgress
            } else {
                status = .pending
            }

            return ResourceProgress(
                resourceId: event.resourceName,
                displayName: event.resourceName,
                resourceType: event.resourceType,
                status: status,
                statusReason: nil,
                timestamp: Date()
            )
        }

        return DeploymentProgress(
            resources: resourceProgresses,
            pollCount: 1,
            isComplete: completedCount == totalCount && totalCount > 0
        )
    }
}
