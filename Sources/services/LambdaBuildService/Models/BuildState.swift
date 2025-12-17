import CLISDK
import Foundation

/// Simple data container for build-related state
/// Models own and mutate this struct directly
public struct BuildState: Equatable, Sendable {
    /// Build output lines
    public var outputLines: [String] = []

    /// Current build status
    public var status: BuildStatus = .notBuilt

    public init(outputLines: [String] = [], status: BuildStatus = .notBuilt) {
        self.outputLines = outputLines
        self.status = status
    }

    /// Start a new build - clears output and sets status to building
    public mutating func startBuild() {
        outputLines = []
        status = .building
    }

    /// Clear all build output and reset to notBuilt
    public mutating func clear() {
        outputLines = []
        status = .notBuilt
    }

    /// Update status based on whether a build artifact exists
    /// - Parameter exists: Whether a build artifact exists on disk
    public mutating func updateFromDisk(buildExists: Bool) {
        // Only update if not currently building
        guard !status.isBuilding else { return }

        if buildExists {
            // If we just successfully built, keep .success status
            // Otherwise show .available
            if case .success = status {
                return
            }
            status = .available
        } else {
            status = .notBuilt
        }
    }

    /// Mark build as successful
    public mutating func markSuccess() {
        appendOutput("\n✅ Build completed successfully\n")
        status = .success
    }

    /// Mark build as failed
    public mutating func markFailed(exitCode: Int32) {
        appendOutput("\n❌ Build failed with exit code \(exitCode)\n")
        status = .failed(exitCode)
    }

    /// Append text to build output, splitting by newlines
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
