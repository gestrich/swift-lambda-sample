import Foundation

/// Error type for workflow execution
public enum WorkflowError: Error, LocalizedError {
    case noStateYielded

    public var errorDescription: String? {
        switch self {
        case .noStateYielded:
            return "Workflow completed without yielding any state"
        }
    }
}
