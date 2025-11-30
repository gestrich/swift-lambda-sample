import Foundation

/// Unified output state that collects CLI output from all operations (build, lambda, etc.)
@MainActor
@Observable
public class UnifiedOutputState {
    /// All output lines
    public private(set) var outputLines: [String] = []

    /// Whether an operation is currently active
    public private(set) var isActive: Bool = false

    public init() {}

    /// Mark that an operation is starting
    public func startOperation() {
        isActive = true
    }

    /// Mark that an operation has completed
    public func endOperation() {
        isActive = false
    }

    /// Clear all output
    public func clear() {
        outputLines = []
    }

    /// Append text to output, splitting by newlines
    public func appendOutput(_ text: String) {
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
    /// - Returns: Exit code if the event was an exit, nil otherwise
    public func processStreamOutput(_ output: StreamOutput) -> Int32? {
        switch output {
        case .stdout(let text):
            appendOutput(text)
            return nil
        case .stderr(let text):
            appendOutput(text)
            return nil
        case .exit(let code):
            return code
        case .error(let error):
            appendOutput("Error: \(error.localizedDescription)\n")
            return 1
        }
    }
}
