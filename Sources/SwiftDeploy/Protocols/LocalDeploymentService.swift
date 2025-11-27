import Foundation

/// Protocol for local Lambda deployment services
/// Both XcodeLocalService and LinuxLocalService conform to this protocol,
/// enabling polymorphic usage and consistent CLI/UI experiences.
public protocol LocalDeploymentService {
    /// The port where Lambda listens for requests
    var port: Int { get }

    /// The local endpoint URL for invoking Lambda
    var localEndpoint: String { get }

    // MARK: - Build

    /// Build Lambda for the target platform
    /// - Parameter clean: Whether to clean build artifacts first
    func buildLambda(clean: Bool) async throws

    /// Check if Lambda is already built
    func isLambdaBuilt() -> Bool

    // MARK: - Lifecycle

    /// Start Lambda process/container only
    func startLambda() async throws

    /// Stop Lambda process/container only
    func stopLambda() async throws

    /// Start Lambda with all supporting services (PostgreSQL + MinIO)
    func startWithServices() async throws

    /// Stop Lambda and all supporting services
    func stopWithServices() async throws

    // MARK: - Testing

    /// Test Lambda endpoints
    func testLambda() async throws

    /// Wait for Lambda to be ready
    /// - Parameter maxAttempts: Maximum number of seconds to wait (default 30)
    func waitForReady(maxAttempts: Int) async throws
}

// MARK: - Default Implementations

extension LocalDeploymentService {
    /// Default implementation with standard timeout
    public func waitForReady() async throws {
        try await waitForReady(maxAttempts: 30)
    }

    /// Default implementation for buildLambda without clean parameter
    public func buildLambda() async throws {
        try await buildLambda(clean: false)
    }
}
