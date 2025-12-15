import Foundation

/// Progress snapshot during deployment/destroy operations.
public struct DeploymentProgress: Sendable, Equatable {
    public let resources: [ResourceProgress]
    public let pollCount: Int
    public let isComplete: Bool

    public var completedCount: Int {
        resources.filter { $0.status.isComplete }.count
    }

    public var inProgressCount: Int {
        resources.filter { $0.status.isInProgress }.count
    }

    public var hasFailures: Bool {
        resources.contains { $0.status.isFailed }
    }

    public var hasPolled: Bool { pollCount > 0 }
    public var hasPolledEnough: Bool { pollCount >= 5 }

    public init(resources: [ResourceProgress] = [], pollCount: Int = 0, isComplete: Bool = false) {
        self.resources = resources
        self.pollCount = pollCount
        self.isComplete = isComplete
    }

    /// Create progress snapshot from CloudFormation events
    public static func from(
        events: [CloudFormationStackEvent],
        since: Date?,
        pollCount: Int,
        isComplete: Bool = false
    ) -> DeploymentProgress {
        let relevantEvents = events.filter { event in
            guard let since = since else { return true }
            return event.timestamp >= since
        }

        var latestByResource: [String: CloudFormationStackEvent] = [:]
        for event in relevantEvents {
            if event.resourceType == "AWS::CloudFormation::Stack" { continue }

            if let existing = latestByResource[event.logicalResourceId] {
                if event.timestamp > existing.timestamp {
                    latestByResource[event.logicalResourceId] = event
                }
            } else {
                latestByResource[event.logicalResourceId] = event
            }
        }

        let resources = latestByResource.values
            .sorted { $0.timestamp > $1.timestamp }
            .map { ResourceProgress(from: $0) }

        return DeploymentProgress(resources: resources, pollCount: pollCount, isComplete: isComplete)
    }
}

/// Progress snapshot for a single resource.
public struct ResourceProgress: Sendable, Equatable, Identifiable {
    public let resourceId: String
    public let displayName: String
    public let resourceType: String
    public let status: ResourceStatus
    public let statusReason: String?
    public let timestamp: Date

    public var id: String { resourceId }

    public init(
        resourceId: String,
        displayName: String,
        resourceType: String,
        status: ResourceStatus,
        statusReason: String?,
        timestamp: Date
    ) {
        self.resourceId = resourceId
        self.displayName = displayName
        self.resourceType = resourceType
        self.status = status
        self.statusReason = statusReason
        self.timestamp = timestamp
    }

    public init(from event: CloudFormationStackEvent) {
        self.resourceId = event.logicalResourceId
        self.displayName = event.displayName
        self.resourceType = event.displayType
        self.status = ResourceStatus(from: event.resourceStatus)
        self.statusReason = event.resourceStatusReason
        self.timestamp = event.timestamp
    }
}

/// Status of a resource during deployment.
public enum ResourceStatus: Sendable, Equatable {
    case pending
    case inProgress
    case complete
    case failed(reason: String?)

    public var isInProgress: Bool {
        if case .inProgress = self { return true }
        return false
    }

    public var isComplete: Bool {
        if case .complete = self { return true }
        return false
    }

    public var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }

    public init(from status: String) {
        if status.contains("COMPLETE") && !status.contains("CLEANUP") && !status.contains("ROLLBACK") {
            self = .complete
        } else if status.contains("IN_PROGRESS") {
            self = .inProgress
        } else if status.contains("FAILED") || status.contains("ROLLBACK") {
            self = .failed(reason: nil)
        } else {
            self = .pending
        }
    }
}
