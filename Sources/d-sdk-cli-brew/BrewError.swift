import Foundation

public enum BrewError: Error, LocalizedError, Sendable {
    case commandFailed(command: String, exitCode: Int32, output: String)

    public var errorDescription: String? {
        switch self {
        case .commandFailed(let command, let exitCode, let output):
            let errorOutput = output.isEmpty ? "No error output" : output.trimmingCharacters(in: .whitespacesAndNewlines)
            return "Homebrew command '\(command)' failed with exit code \(exitCode): \(errorOutput)"
        }
    }
}
