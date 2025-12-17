import Foundation

public enum DockerError: Error, LocalizedError, Sendable {
    case commandFailed(command: String, exitCode: Int32, output: String)
    case daemonNotRunning
    case daemonStartTimeout(seconds: Int)
    case containerNotFound(name: String)
    case networkNotFound(name: String)

    public var errorDescription: String? {
        switch self {
        case .commandFailed(let command, let exitCode, let output):
            let errorOutput = output.isEmpty ? "No error output" : output.trimmingCharacters(in: .whitespacesAndNewlines)
            return "Docker command '\(command)' failed with exit code \(exitCode): \(errorOutput)"
        case .daemonNotRunning:
            return "Docker daemon is not running"
        case .daemonStartTimeout(let seconds):
            return "Docker daemon did not start within \(seconds) seconds"
        case .containerNotFound(let name):
            return "Container '\(name)' not found"
        case .networkNotFound(let name):
            return "Network '\(name)' not found"
        }
    }
}
