import Foundation

/// Build status for Lambda
public enum BuildStatus: Equatable, Sendable {
    case notBuilt
    case available
    case building
    case success
    case failed(Int32)

    public var isBuilding: Bool {
        if case .building = self { return true }
        return false
    }

    /// Whether a build artifact exists (available or just built successfully)
    public var hasArtifact: Bool {
        switch self {
        case .available, .success:
            return true
        default:
            return false
        }
    }

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
