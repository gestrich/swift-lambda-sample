import Foundation

// MARK: - Build Error

public enum BuildError: Error, LocalizedError {
    case failed(exitCode: Int32)

    public var errorDescription: String? {
        switch self {
        case .failed(let exitCode):
            return "Build failed with exit code \(exitCode)"
        }
    }
}

// MARK: - Build Status

/// Build status for Lambda
public enum BuildStatus: Equatable, Sendable {
    case notBuilt
    case available
    case building
    case success
    case failed(Int32)

    public var isBuilding: Bool {
        if case .building = self { return true }
        return false
    }

    /// Whether a build artifact exists (available or just built successfully)
    public var hasArtifact: Bool {
        switch self {
        case .available, .success:
            return true
        default:
            return false
        }
    }
}

// MARK: - Build State

/// Encapsulates all build-related state
@MainActor
@Observable
public class BuildState {
    /// Build output lines
    public private(set) var outputLines: [String] = []

    /// Current build status
    public private(set) var status: BuildStatus = .notBuilt

    public init() {}

    /// Start a new build - clears output and sets status to building
    public func startBuild() {
        outputLines = []
        status = .building
    }

    /// Clear all build output and reset to notBuilt
    public func clear() {
        outputLines = []
        status = .notBuilt
    }

    /// Update status based on whether a build artifact exists
    /// - Parameter exists: Whether a build artifact exists on disk
    public func updateFromDisk(buildExists: Bool) {
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
    public func markSuccess() {
        appendOutput("\n✅ Build completed successfully\n")
        status = .success
    }

    /// Mark build as failed
    public func markFailed(exitCode: Int32) {
        appendOutput("\n❌ Build failed with exit code \(exitCode)\n")
        status = .failed(exitCode)
    }

    /// Append text to build output, splitting by newlines
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
