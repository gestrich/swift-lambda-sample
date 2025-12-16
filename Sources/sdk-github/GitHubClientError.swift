import Foundation

/// Errors specific to GitHub SDK operations
public enum GitHubClientError: Error, LocalizedError, Sendable {
    /// Command failed with exit code
    case commandFailed(command: String, exitCode: Int32, output: String)

    /// Invalid output from command
    case invalidOutput(reason: String)

    /// Workflow run not found
    case workflowRunNotFound

    /// Git operation failed
    case gitOperationFailed(reason: String)

    /// Timeout waiting for operation
    case timeout(operation: String, duration: TimeInterval)

    public var errorDescription: String? {
        switch self {
        case .commandFailed(let command, let exitCode, let output):
            let errorOutput = output.isEmpty ? "No error output" : output.trimmingCharacters(in: .whitespacesAndNewlines)
            return "GitHub command '\(command)' failed with exit code \(exitCode): \(errorOutput)"

        case .invalidOutput(let reason):
            return "Invalid GitHub output: \(reason)"

        case .workflowRunNotFound:
            return "No workflow run found"

        case .gitOperationFailed(let reason):
            return "Git operation failed: \(reason)"

        case .timeout(let operation, let duration):
            return "Timeout after \(Int(duration))s waiting for: \(operation)"
        }
    }
}
