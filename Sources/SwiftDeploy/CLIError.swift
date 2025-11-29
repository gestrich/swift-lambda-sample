import Foundation
import CLIKit

// Re-export CLIKit types that are needed by SwiftDeploy clients
public typealias CLIService = CLIKit.CLIService
public typealias CLIServiceError = CLIKit.CLIServiceError
public typealias ExecutionResult = CLIKit.ExecutionResult
public typealias StreamOutput = CLIKit.StreamOutput

/// Application-specific errors for deployment operations
public enum DeployError: Error, LocalizedError, Sendable {
    /// Deployment failed
    case deploymentFailed(reason: String)

    /// Git operation failed
    case gitOperationFailed(reason: String)

    /// Test failed
    case testFailed(message: String)

    /// Command failed with exit code
    case commandFailed(command: String, exitCode: Int32, stderr: String)

    /// Invalid configuration
    case invalidConfiguration(String)

    public var errorDescription: String? {
        switch self {
        case .deploymentFailed(let reason):
            return "Deployment failed: \(reason)"

        case .gitOperationFailed(let reason):
            return "Git operation failed: \(reason)"

        case .testFailed(let message):
            return "Test failed: \(message)"

        case .commandFailed(let command, let exitCode, let stderr):
            let errorOutput = stderr.isEmpty ? "No error output" : stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return "Command '\(command)' failed with exit code \(exitCode): \(errorOutput)"

        case .invalidConfiguration(let reason):
            return "Invalid configuration: \(reason)"
        }
    }
}
