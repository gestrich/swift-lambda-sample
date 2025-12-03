import CLIKit
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

    /// Display name for the service (used in UI)
    static var displayName: String { get }

    /// Detail text describing the service (used in UI)
    static var detailText: String { get }

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

    // MARK: - CLI Service

    /// The CLI service instance for this service.
    /// Each service has its own dedicated CLIService to isolate output streams.
    var cliService: CLIService { get }

    // MARK: - Unified Output

    /// Unified output state that collects all CLI output (build, lambda, etc.)
    var unifiedOutput: UnifiedOutputState { get }

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
