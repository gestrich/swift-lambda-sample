import Foundation

/// Parser for CDK CLI output lines to extract deployment events
///
/// CDK output format (6 pipe-separated fields):
/// ```
/// SwiftLambdaSampleStack | 23/30 | 4:13:09 PM | CREATE_IN_PROGRESS | AWS::ApiGateway::Stage | ApiGateway/Api/...
/// SwiftLambdaSampleStack |   0   | 4:18:44 PM | DELETE_IN_PROGRESS | AWS::Lambda::Function  | Lambda/Function
/// ```
/// Fields: stackName | progress | timestamp | status | resourceType | resourceName
///
/// Note: Progress format differs between operations:
/// - Deploy: "X/Y" (e.g., "23/30")
/// - Destroy: single number (e.g., "0", "1", "2")
public class CDKOutputParser {
    // Match 6 pipe-separated fields:
    // 1. Stack name (non-whitespace)
    // 2. Progress (X/Y or just X for destroy)
    // 3. Timestamp (H:MM:SS AM/PM)
    // 4. Status (e.g., CREATE_IN_PROGRESS, DELETE_COMPLETE)
    // 5. Resource type (e.g., AWS::ApiGateway::Stage)
    // 6. Resource name (everything else)
    private let resourcePattern = #"(\S+)\s*\|\s*(\d+(?:\/\d+)?)\s*\|\s*(\d+:\d+:\d+\s*[AP]M)\s*\|\s*(\S+)\s*\|\s*([^|]+)\s*\|\s*(.+)"#
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

        guard let stackName = extractGroup(1),
              let progress = extractGroup(2),
              let timestamp = extractGroup(3),
              let status = extractGroup(4),
              let resourceType = extractGroup(5),
              let resourceName = extractGroup(6) else {
            return nil
        }

        return CDKResourceEvent(
            stackName: stackName,
            progress: progress,
            timestamp: timestamp,
            status: status,
            resourceType: resourceType.trimmingCharacters(in: .whitespaces),
            resourceName: resourceName.trimmingCharacters(in: .whitespaces)
        )
    }
}

/// A single resource event parsed from CDK output
public struct CDKResourceEvent: Sendable {
    public let stackName: String
    public let progress: String
    public let timestamp: String
    public let status: String
    public let resourceType: String
    public let resourceName: String

    public var isComplete: Bool {
        status.contains("COMPLETE") && !status.contains("ROLLBACK")
    }

    public var isInProgress: Bool {
        status.contains("IN_PROGRESS")
    }

    public var isFailed: Bool {
        status.contains("FAILED") || status.contains("ROLLBACK")
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
