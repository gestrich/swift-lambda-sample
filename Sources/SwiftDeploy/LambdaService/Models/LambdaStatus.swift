import Foundation

/// Lambda lifecycle status
public enum LambdaStatus: Equatable, Sendable {
    case stopped
    case starting
    case running
    case stopping
    case failed(String)

    public var isTransitioning: Bool {
        switch self {
        case .starting, .stopping:
            return true
        default:
            return false
        }
    }

    public var isRunning: Bool {
        if case .running = self { return true }
        return false
    }

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
