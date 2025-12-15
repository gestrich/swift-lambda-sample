import Foundation

/// Parser for extracting progress information from CDK CLI output
/// Handles both deploy and destroy operations
///
/// CDK output format:
/// `StackName | current/total | timestamp | STATUS | ResourceType | ResourceName (LogicalId)`
///
/// Examples:
/// - `SwiftLambdaSampleStack | 28/30 | 5:25:24 AM | CREATE_COMPLETE | AWS::Events::Rule | Monitoring/ScheduleRule (MonitoringScheduleRuleFEFA758D)`
/// - `SwiftLambdaSampleStack | 18 | 5:20:37 AM | DELETE_IN_PROGRESS | AWS::ApiGateway::Resource | ApiGateway/Api/Default/api`
public struct CDKOutputParser {

    public init() {}

    /// Parse a single line of CDK output
    /// - Parameter line: Raw output line from CDK CLI
    /// - Returns: Parsed event if the line matches the expected format, nil otherwise
    public func parse(_ line: String) -> CDKOutputEvent? {
        // Split by " | " separator
        let parts = line.components(separatedBy: " | ")
        guard parts.count >= 5 else { return nil }

        // Parse progress (e.g., "28/30" or just "28")
        let progressPart = parts[1].trimmingCharacters(in: .whitespaces)
        let progressComponents = progressPart.components(separatedBy: "/")

        guard let current = Int(progressComponents[0]) else { return nil }
        let total = progressComponents.count > 1 ? Int(progressComponents[1]) : nil

        // Parse status (e.g., "CREATE_COMPLETE", "DELETE_IN_PROGRESS")
        let status = parts[3].trimmingCharacters(in: .whitespaces)

        // Parse resource type (e.g., "AWS::Events::Rule")
        let resourceType = parts[4].trimmingCharacters(in: .whitespaces)

        // Parse resource name and logical ID if present
        let resourcePart = parts.count > 5 ? parts[5].trimmingCharacters(in: .whitespaces) : ""
        let (resourceName, logicalId) = parseResourceName(resourcePart)

        return CDKOutputEvent(
            currentStep: current,
            totalSteps: total,
            status: status,
            resourceType: resourceType,
            resourceName: resourceName,
            logicalResourceId: logicalId
        )
    }

    /// Extract resource name and logical ID from the resource part
    /// Format: "ResourcePath (LogicalId)" or just "ResourcePath"
    private func parseResourceName(_ resourcePart: String) -> (name: String, logicalId: String?) {
        // Check for pattern: "Name (LogicalId)"
        if let parenStart = resourcePart.lastIndex(of: "("),
           let parenEnd = resourcePart.lastIndex(of: ")"),
           parenStart < parenEnd {
            let name = String(resourcePart[..<parenStart]).trimmingCharacters(in: .whitespaces)
            let startIndex = resourcePart.index(after: parenStart)
            let logicalId = String(resourcePart[startIndex..<parenEnd])
            return (name, logicalId)
        }
        return (resourcePart, nil)
    }
}

/// A parsed event from CDK output
public struct CDKOutputEvent: Sendable, Equatable {
    /// Current step number (e.g., 28 in "28/30")
    public let currentStep: Int

    /// Total steps if known (e.g., 30 in "28/30")
    public let totalSteps: Int?

    /// CloudFormation status (e.g., "CREATE_COMPLETE", "DELETE_IN_PROGRESS")
    public let status: String

    /// AWS resource type (e.g., "AWS::Events::Rule")
    public let resourceType: String

    /// Human-readable resource name/path
    public let resourceName: String

    /// CloudFormation logical resource ID
    public let logicalResourceId: String?

    /// Whether this is a create operation
    public var isCreate: Bool {
        status.hasPrefix("CREATE")
    }

    /// Whether this is a delete operation
    public var isDelete: Bool {
        status.hasPrefix("DELETE")
    }

    /// Whether this is an update operation
    public var isUpdate: Bool {
        status.hasPrefix("UPDATE")
    }

    /// Whether this represents an in-progress state
    public var isInProgress: Bool {
        status.contains("IN_PROGRESS")
    }

    /// Whether this represents a completed state
    public var isComplete: Bool {
        status.contains("COMPLETE") && !status.contains("CLEANUP")
    }

    /// Whether this represents a failed state
    public var isFailed: Bool {
        status.contains("FAILED") || status.contains("ROLLBACK")
    }

    /// Simplified display type (e.g., "Events Rule" from "AWS::Events::Rule")
    public var displayType: String {
        resourceType
            .replacingOccurrences(of: "AWS::", with: "")
            .replacingOccurrences(of: "::", with: " ")
    }
}

/// Accumulator for building progress from parsed CDK output events
public final class CDKProgressAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var _currentStep: Int = 0
    private var _totalSteps: Int?
    private var _resources: [String: CDKOutputEvent] = [:]

    public init() {}

    /// Update progress with a new event
    public func update(with event: CDKOutputEvent) {
        lock.lock()
        defer { lock.unlock() }

        _currentStep = event.currentStep
        if let total = event.totalSteps {
            _totalSteps = total
        }

        // Track latest event per resource
        let key = event.logicalResourceId ?? event.resourceName
        _resources[key] = event
    }

    /// Get current progress snapshot
    public func snapshot() -> CDKParsedProgress {
        lock.lock()
        defer { lock.unlock() }

        let resourceSnapshots = _resources.values.map { event in
            ResourceProgressSnapshot(
                resourceId: event.logicalResourceId ?? event.resourceName,
                displayName: event.resourceName,
                resourceType: event.displayType,
                status: ResourceStatusSnapshot(from: event.status),
                statusReason: nil,
                timestamp: Date()
            )
        }.sorted { $0.resourceId < $1.resourceId }

        return CDKParsedProgress(
            currentStep: _currentStep,
            totalSteps: _totalSteps,
            resources: resourceSnapshots
        )
    }

    /// Reset the accumulator
    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        _currentStep = 0
        _totalSteps = nil
        _resources.removeAll()
    }
}

/// Progress snapshot built from parsed CDK output
public struct CDKParsedProgress: Sendable, Equatable {
    public let currentStep: Int
    public let totalSteps: Int?
    public let resources: [ResourceProgressSnapshot]

    /// Convert to CDKDeploymentProgress for compatibility with existing UI
    public func toDeploymentProgress(isComplete: Bool = false) -> CDKDeploymentProgress {
        CDKDeploymentProgress(
            resources: resources,
            pollCount: currentStep, // Use step count as poll count for UI logic
            isComplete: isComplete
        )
    }
}

