import Client
import Combine
import Foundation

// MARK: - Protocol

/// Protocol for Lambda services (local and remote)
/// XcodeLocalService, LinuxLocalService, and RemoteService conform to this protocol,
/// enabling polymorphic usage and consistent CLI/UI experiences.
@MainActor
public protocol LambdaService {
    /// Unique key for persistence (used for saving/restoring mode selection)
    static var persistenceKey: String { get }

    /// The port where Lambda listens for requests
    var port: Int { get }

    /// The endpoint URL for invoking Lambda
    var endpoint: String { get }

    /// Label for the endpoint field in UI
    var endpointLabel: String { get }

    /// Help text for the endpoint field in UI
    var endpointHelpText: String { get }

    /// API client for making requests to this service
    var apiClient: APIClient { get }

    /// Whether the service is configured and ready to use
    var isConfigured: Bool { get }

    // MARK: - Build

    /// Observable build state for UI
    var buildState: BuildState { get }

    /// Build Lambda for the target platform
    /// - Parameter clean: Whether to clean build artifacts first
    func buildLambda(clean: Bool) async throws

    /// Build Lambda with streaming output, updating buildState
    /// - Parameter clean: Whether to clean build artifacts first
    func buildWithStreaming(clean: Bool) async

    /// Check if Lambda is already built
    func isLambdaBuilt() -> Bool

    // MARK: - Lifecycle

    /// Start Lambda process/container only
    func startLambda() async throws

    /// Stop Lambda process/container only
    func stopLambda() async throws

    /// Start Lambda with all supporting services (PostgreSQL + S3)
    func startWithServices() async throws

    /// Stop Lambda and all supporting services
    func stopWithServices() async throws

    // MARK: - Testing

    /// Test Lambda endpoints
    func testLambda() async throws

    /// Wait for Lambda to be ready
    /// - Parameter maxAttempts: Maximum number of seconds to wait (default 30)
    func waitForReady(maxAttempts: Int) async throws

    // MARK: - Status

    /// Get the status of all services (Lambda, S3, PostgreSQL)
    func status() async throws -> DeploymentStatus

    // MARK: - Combine Publishers

    /// Publisher that emits status updates
    var statusPublisher: AnyPublisher<DeploymentStatus, Never> { get }

    /// Publisher that emits loading state updates
    var isLoadingStatusPublisher: AnyPublisher<Bool, Never> { get }

    /// Trigger a status refresh (results published via statusPublisher)
    func refreshStatus()
}

// MARK: - Default Implementations

extension LambdaService {
    /// Default implementation with standard timeout
    public func waitForReady() async throws {
        try await waitForReady(maxAttempts: 30)
    }

    /// Default implementation for buildLambda without clean parameter
    public func buildLambda() async throws {
        try await buildLambda(clean: false)
    }

    /// Default implementation for buildWithStreaming without clean parameter
    public func buildWithStreaming() async {
        await buildWithStreaming(clean: false)
    }
}

// MARK: - Build State

/// Build status for Lambda
public enum BuildStatus: Equatable, Sendable {
    case idle
    case building
    case success
    case failed(String)

    public var isBuilding: Bool {
        if case .building = self { return true }
        return false
    }
}

/// Encapsulates all build-related state
@MainActor
@Observable
public class BuildState {
    /// Build output lines (capped at maxOutputLines)
    public private(set) var outputLines: [String] = []

    /// Current build status
    public private(set) var status: BuildStatus = .idle

    /// Maximum number of output lines to keep
    public let maxOutputLines: Int

    public init(maxOutputLines: Int = 500) {
        self.maxOutputLines = maxOutputLines
    }

    /// Reset state for a new build
    public func reset() {
        outputLines = []
        status = .building
    }

    /// Clear all build output and reset to idle
    public func clear() {
        outputLines = []
        status = .idle
    }

    /// Mark build as successful
    public func markSuccess() {
        appendOutput("\n✅ Build completed successfully\n")
        status = .success
    }

    /// Mark build as failed
    public func markFailed(exitCode: Int32) {
        appendOutput("\n❌ Build failed with exit code \(exitCode)\n")
        status = .failed("Exit code: \(exitCode)")
    }

    /// Append text to build output, splitting by newlines and capping at maxOutputLines
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

        // Cap at maxOutputLines
        if outputLines.count > maxOutputLines {
            let overflow = outputLines.count - maxOutputLines
            outputLines.removeFirst(overflow)
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

// MARK: - Service State

/// State of a service component
public enum ServiceState: String, Sendable, CustomStringConvertible {
    case stopped
    case stopping
    case starting
    case running

    public var description: String {
        rawValue
    }

    /// Whether the service is in a transitional state (starting or stopping)
    public var isTransitioning: Bool {
        self == .starting || self == .stopping
    }
}

/// Status of all deployment services
public struct DeploymentStatus: Sendable {
    public let lambdaState: ServiceState
    public let s3State: ServiceState
    public let postgresState: ServiceState

    public init(lambdaState: ServiceState, s3State: ServiceState, postgresState: ServiceState) {
        self.lambdaState = lambdaState
        self.s3State = s3State
        self.postgresState = postgresState
    }

    /// All services stopped
    public static let stopped = DeploymentStatus(
        lambdaState: .stopped,
        s3State: .stopped,
        postgresState: .stopped
    )

    /// All services stopping
    public static let stopping = DeploymentStatus(
        lambdaState: .stopping,
        s3State: .stopping,
        postgresState: .stopping
    )

    /// All services starting
    public static let starting = DeploymentStatus(
        lambdaState: .starting,
        s3State: .starting,
        postgresState: .starting
    )
}
