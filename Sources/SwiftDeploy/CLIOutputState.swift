import Foundation

// MARK: - CLI Output Status Protocol

/// Protocol for status types that can be displayed in the unified output view
public protocol CLIOutputStatus: Equatable, Sendable {
    /// Whether the status indicates an active/transitioning state
    /// (e.g., building, starting, stopping)
    var isActive: Bool { get }

    /// Icon name (SF Symbol) for the status
    var iconName: String { get }

    /// Display text for the status
    var displayText: String { get }

    /// Color name for the status (e.g., "blue", "green", "orange", "red", "secondary")
    var colorName: String { get }

    /// Whether to show a progress indicator instead of the icon
    var showProgress: Bool { get }

    /// Optional help text (e.g., for failure reasons)
    var helpText: String? { get }
}

// MARK: - CLI Output State Protocol

/// Protocol for observable state classes that can be displayed in the unified output view.
/// Both `BuildState` and `LambdaState` conform to this protocol.
@MainActor
public protocol CLIOutputState: AnyObject, Observable {
    /// The status type for this state
    associatedtype Status: CLIOutputStatus

    /// Output lines to display
    var outputLines: [String] { get }

    /// Current status
    var status: Status { get }

    /// Clear all output and reset status
    func clear()
}

// MARK: - BuildStatus Conformance

extension BuildStatus: CLIOutputStatus {
    public var isActive: Bool {
        isBuilding
    }

    public var iconName: String {
        switch self {
        case .notBuilt:
            return "minus.circle"
        case .available:
            return "checkmark.circle"
        case .building:
            return "hammer"
        case .success:
            return "checkmark.circle.fill"
        case .failed:
            return "xmark.circle.fill"
        }
    }

    public var displayText: String {
        switch self {
        case .notBuilt:
            return "Not Built"
        case .available:
            return "Available"
        case .building:
            return "Building..."
        case .success:
            return "Success"
        case .failed:
            return "Failed"
        }
    }

    public var colorName: String {
        switch self {
        case .notBuilt:
            return "secondary"
        case .available:
            return "blue"
        case .building:
            return "orange"
        case .success:
            return "green"
        case .failed:
            return "red"
        }
    }

    public var showProgress: Bool {
        isBuilding
    }

    public var helpText: String? {
        nil
    }
}

// MARK: - LambdaStatus Conformance

extension LambdaStatus: CLIOutputStatus {
    public var isActive: Bool {
        isTransitioning
    }

    public var iconName: String {
        switch self {
        case .stopped:
            return "stop.circle"
        case .starting:
            return "play.circle"
        case .running:
            return "play.circle.fill"
        case .stopping:
            return "stop.circle"
        case .failed:
            return "xmark.circle.fill"
        }
    }

    public var displayText: String {
        switch self {
        case .stopped:
            return "Stopped"
        case .starting:
            return "Starting..."
        case .running:
            return "Running"
        case .stopping:
            return "Stopping..."
        case .failed:
            return "Failed"
        }
    }

    public var colorName: String {
        switch self {
        case .stopped:
            return "secondary"
        case .starting:
            return "orange"
        case .running:
            return "green"
        case .stopping:
            return "orange"
        case .failed:
            return "red"
        }
    }

    public var showProgress: Bool {
        isTransitioning
    }

    public var helpText: String? {
        if case .failed(let reason) = self {
            return reason
        }
        return nil
    }
}
