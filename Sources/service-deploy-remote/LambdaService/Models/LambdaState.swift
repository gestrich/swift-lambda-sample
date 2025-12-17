import sdk_cli
import Foundation

/// Simple data container for Lambda lifecycle state
/// Models own and mutate this struct directly
public struct LambdaState: Equatable, Sendable {
    /// Lambda output lines
    public var outputLines: [String] = []

    /// Current Lambda status
    public var status: LambdaStatus = .stopped

    public init(outputLines: [String] = [], status: LambdaStatus = .stopped) {
        self.outputLines = outputLines
        self.status = status
    }

    /// Start Lambda - clears output and sets status to starting
    public mutating func startLambda() {
        outputLines = []
        status = .starting
    }

    /// Begin stopping Lambda
    public mutating func beginStop() {
        status = .stopping
    }

    /// Set status to running (for remote services that are always running when deployed)
    public mutating func setRunning() {
        status = .running
    }

    /// Clear all output and reset to stopped
    public mutating func clear() {
        outputLines = []
        status = .stopped
    }

    /// Mark Lambda as running
    public mutating func markRunning() {
        appendOutput("\n✅ Lambda is running\n")
        status = .running
    }

    /// Mark Lambda as stopped
    public mutating func markStopped() {
        appendOutput("\n✅ Lambda stopped\n")
        status = .stopped
    }

    /// Mark Lambda as failed
    public mutating func markFailed(reason: String) {
        appendOutput("\n❌ Lambda failed: \(reason)\n")
        status = .failed(reason)
    }

    /// Append text to Lambda output, splitting by newlines
    public mutating func appendOutput(_ text: String) {
        // Split text into lines, preserving empty lines
        let newLines = text.components(separatedBy: "\n")

        // If the last line in outputLines is incomplete (no trailing newline),
        // append the first part of new text to it
        if !outputLines.isEmpty && !text.isEmpty {
            let lastIndex = outputLines.count - 1
            outputLines[lastIndex] += newLines[0]

            // Add remaining lines
            if newLines.count > 1 {
                outputLines.append(contentsOf: newLines.dropFirst())
            }
        } else {
            outputLines.append(contentsOf: newLines)
        }
    }

    /// Process a stream output event
    public mutating func processStreamOutput(_ output: StreamOutput) -> Int32? {
        switch output {
        case .command(_, let text):
            appendOutput(text)
            return nil
        case .stdout(_, let text):
            appendOutput(text)
            return nil
        case .stderr(_, let text):
            appendOutput(text)
            return nil
        case .exit(_, let code):
            return code
        case .error(_, let error):
            appendOutput("Error: \(error.localizedDescription)\n")
            return 1
        }
    }
}
