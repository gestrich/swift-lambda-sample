import Foundation

/// Error type for use case execution
public enum UseCaseError: Error, LocalizedError {
    case noStateYielded

    public var errorDescription: String? {
        switch self {
        case .noStateYielded:
            return "Use case completed without yielding any state"
        }
    }
}
