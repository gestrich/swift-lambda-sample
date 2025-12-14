import CLIKit
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
    
    public var isActive: Bool {
        isBuilding
    }

    public var iconName: String {
        switch self {
        case .notBuilt:
            return "minus.circle"
        case .available:
            return "checkmark.circle"
        case .building:
            return "hammer"
        case .success:
            return "checkmark.circle.fill"
        case .failed:
            return "xmark.circle.fill"
        }
    }

    public var displayText: String {
        switch self {
        case .notBuilt:
            return "Not Built"
        case .available:
            return "Available"
        case .building:
            return "Building..."
        case .success:
            return "Success"
        case .failed:
            return "Failed"
        }
    }

    public var colorName: String {
        switch self {
        case .notBuilt:
            return "secondary"
        case .available:
            return "blue"
        case .building:
            return "orange"
        case .success:
            return "green"
        case .failed:
            return "red"
        }
    }

    public var showProgress: Bool {
        isBuilding
    }

    public var helpText: String? {
        nil
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

// MARK: - Lambda State

/// Encapsulates all Lambda lifecycle state with streaming output
@MainActor
@Observable
public class LambdaState {
    /// Lambda output lines
    public private(set) var outputLines: [String] = []

    /// Current Lambda status
    public private(set) var status: LambdaStatus = .stopped

    public init() {}

    /// Start Lambda - clears output and sets status to starting
    public func startLambda() {
        outputLines = []
        status = .starting
    }

    /// Begin stopping Lambda
    public func beginStop() {
        status = .stopping
    }

    /// Set status to running (for remote services that are always running when deployed)
    public func setRunning() {
        status = .running
    }

    /// Clear all output and reset to stopped
    public func clear() {
        outputLines = []
        status = .stopped
    }

    /// Mark Lambda as running
    public func markRunning() {
        appendOutput("\n✅ Lambda is running\n")
        status = .running
    }

    /// Mark Lambda as stopped
    public func markStopped() {
        appendOutput("\n✅ Lambda stopped\n")
        status = .stopped
    }

    /// Mark Lambda as failed
    public func markFailed(reason: String) {
        appendOutput("\n❌ Lambda failed: \(reason)\n")
        status = .failed(reason)
    }

    /// Append text to Lambda output, splitting by newlines
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

// MARK: - Lambda Status

/// Lambda lifecycle status
public enum LambdaStatus: Equatable, Sendable {
    case stopped
    case starting
    case running
    case stopping
    case failed(String)

    public var isTransitioning: Bool {
        switch self {
        case .starting, .stopping:
            return true
        default:
            return false
        }
    }

    public var isRunning: Bool {
        if case .running = self { return true }
        return false
    }
    
    public var isActive: Bool {
        isTransitioning
    }

    public var iconName: String {
        switch self {
        case .stopped:
            return "stop.circle"
        case .starting:
            return "play.circle"
        case .running:
            return "play.circle.fill"
        case .stopping:
            return "stop.circle"
        case .failed:
            return "xmark.circle.fill"
        }
    }

    public var displayText: String {
        switch self {
        case .stopped:
            return "Stopped"
        case .starting:
            return "Starting..."
        case .running:
            return "Running"
        case .stopping:
            return "Stopping..."
        case .failed:
            return "Failed"
        }
    }

    public var colorName: String {
        switch self {
        case .stopped:
            return "secondary"
        case .starting:
            return "orange"
        case .running:
            return "green"
        case .stopping:
            return "orange"
        case .failed:
            return "red"
        }
    }

    public var showProgress: Bool {
        isTransitioning
    }

    public var helpText: String? {
        if case .failed(let reason) = self {
            return reason
        }
        return nil
    }
}
