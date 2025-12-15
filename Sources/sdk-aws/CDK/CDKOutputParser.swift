import Foundation

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
