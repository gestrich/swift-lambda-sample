import Foundation

/// Result of executing a CLI command
public struct ExecutionResult: Sendable {
    /// Exit code of the process (0 typically means success)
    public let exitCode: Int32

    /// Standard output captured from the process
    public let stdout: String

    /// Standard error captured from the process
    public let stderr: String

    /// Time taken to execute the command
    public let duration: TimeInterval

    /// Whether the command succeeded (exit code 0)
    public var isSuccess: Bool {
        exitCode == 0
    }

    /// Combined output (stdout + stderr)
    public var output: String {
        let combined = stdout + (stderr.isEmpty ? "" : "\n" + stderr)
        return combined.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public init(exitCode: Int32, stdout: String, stderr: String, duration: TimeInterval) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.duration = duration
    }
}

// MARK: - CustomStringConvertible

extension ExecutionResult: CustomStringConvertible {
    public var description: String {
        """
        ExecutionResult(
            exitCode: \(exitCode),
            duration: \(String(format: "%.3f", duration))s,
            stdout: \(stdout.isEmpty ? "<empty>" : "\(stdout.count) chars"),
            stderr: \(stderr.isEmpty ? "<empty>" : "\(stderr.count) chars")
        )
        """
    }
}
