import Foundation

public enum NodeError: Error, LocalizedError, Sendable {
    case commandFailed(command: String, exitCode: Int32, output: String)

    public var errorDescription: String? {
        switch self {
        case .commandFailed(let command, let exitCode, let output):
            let errorOutput = output.isEmpty ? "No error output" : output.trimmingCharacters(in: .whitespacesAndNewlines)
            return "Node/npm command '\(command)' failed with exit code \(exitCode): \(errorOutput)"
        }
    }
}
