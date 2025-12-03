import Foundation

/// Combined protocol for local Lambda services (Xcode and Linux)
/// Both XcodeLocalService and LinuxLocalService conform to this protocol.
/// RemoteService does NOT conform - it only conforms to LambdaService.
@MainActor
public protocol LocalService: LambdaService {
    // MARK: - Docker Services (PostgreSQL + MinIO/S3)

    /// Start all services (PostgreSQL + MinIO)
    func startAllServices() async throws

    /// Stop all services
    func stopAllServices() async throws

    /// Start MinIO S3 service
    func startS3() async throws

    /// Create S3 bucket in MinIO
    func createBucket(bucketName: String?) async throws

    /// Stop MinIO S3 service
    func stopS3() async throws

    /// Start PostgreSQL database
    func startDatabase() async throws

    /// Stop PostgreSQL database
    func stopDatabase() async throws

    /// Data directory for S3 (MinIO) - for UI to show "Open in Finder" button
    var s3DataDirectory: String { get }

    /// Data directory for PostgreSQL - for UI to show "Open in Finder" button
    var postgresDataDirectory: String { get }

    // MARK: - Build

    /// Observable build state for UI
    var buildState: BuildState { get }

    /// Build Lambda for the target platform, updating buildState
    /// - Parameter clean: Whether to clean build artifacts first
    /// - Throws: BuildError.failed if the build fails
    func build(clean: Bool) async throws

    /// Check if Lambda is already built
    func isLambdaBuilt() -> Bool

    /// Delete build artifacts and reset build state
    func deleteBuild() async throws

    /// Refresh build status by checking if artifacts exist on disk
    func refreshBuildStatus()

    // MARK: - Lambda Lifecycle

    /// Observable Lambda state for UI (streaming lifecycle output)
    var lambdaState: LambdaState { get }

    /// Start Lambda process/container only
    func startLambda() async throws

    /// Stop Lambda process/container only
    func stopLambda() async throws

    /// Start Lambda with all supporting services (PostgreSQL + S3)
    func startWithServices() async throws

    /// Stop Lambda and all supporting services
    func stopWithServices() async throws
}

// MARK: - Default Implementations

extension LocalService {
    /// Default implementation for build without clean parameter
    public func build() async throws {
        try await build(clean: false)
    }

    /// Default implementation for refreshing build status
    public func refreshBuildStatus() {
        buildState.updateFromDisk(buildExists: isLambdaBuilt())
    }
}
