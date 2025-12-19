import CLISDK
import LambdaBuildService
import Foundation
import DeployCoreService

/// Combined protocol for local Lambda services (Xcode and Linux)
/// Both DeployXcodeModel and DeployLocalModel conform to this protocol.
/// Remote AWS deployments use DeployRemoteModel (in app-mac) which uses workflows.
@MainActor
public protocol LocalService: AnyObject, LambdaService {
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

    /// Start DynamoDB Local
    func startDynamoDB() async throws

    /// Stop DynamoDB Local
    func stopDynamoDB() async throws

    /// Data directory for S3 (MinIO) - for UI to show "Open in Finder" button
    var s3DataDirectory: String { get }

    /// Data directory for PostgreSQL - for UI to show "Open in Finder" button
    var postgresDataDirectory: String { get }

    /// Data directory for DynamoDB Local - for UI to show "Open in Finder" button
    var dynamodbDataDirectory: String { get }

    // MARK: - Build

    /// Build state for UI tracking
    var buildState: BuildState { get set }

    /// Build Lambda for the target platform, updating buildState
    /// - Parameters:
    ///   - clean: Whether to clean build artifacts first
    ///   - output: Optional client-owned stream to receive output (in addition to global stream)
    /// - Throws: BuildError.failed if the build fails
    func build(clean: Bool, output: CLIOutputStream?) async throws

    /// Check if Lambda is already built
    func isLambdaBuilt() -> Bool

    /// Delete build artifacts and reset build state
    func deleteBuild() async throws

    /// Refresh build status by checking if artifacts exist on disk
    func refreshBuildStatus()

    // MARK: - Lambda Lifecycle

    /// Lambda state for UI tracking
    var lambdaState: LambdaState { get set }

    /// Start Lambda process/container only
    /// - Parameter output: Optional client-owned stream to receive output (in addition to global stream)
    func startLambda(output: CLIOutputStream?) async throws

    /// Stop Lambda process/container only
    /// - Parameter output: Optional client-owned stream to receive output (in addition to global stream)
    func stopLambda(output: CLIOutputStream?) async throws

    /// Start Lambda with all supporting services (PostgreSQL + S3)
    /// - Parameter output: Optional client-owned stream to receive output (in addition to global stream)
    func startWithServices(output: CLIOutputStream?) async throws

    /// Stop Lambda and all supporting services
    /// - Parameter output: Optional client-owned stream to receive output (in addition to global stream)
    func stopWithServices(output: CLIOutputStream?) async throws

    /// Start services if not already running, then refresh status
    func startIfNecessary() async
}

// MARK: - Default Implementations

extension LocalService {
    /// Default implementation for build without clean or output parameters
    public func build() async throws {
        try await build(clean: false, output: nil)
    }

    /// Default implementation for build with clean but no output parameter
    public func build(clean: Bool) async throws {
        try await build(clean: clean, output: nil)
    }

    /// Default implementation for startLambda without output parameter
    public func startLambda() async throws {
        try await startLambda(output: nil)
    }

    /// Default implementation for stopLambda without output parameter
    public func stopLambda() async throws {
        try await stopLambda(output: nil)
    }

    /// Default implementation for startWithServices without output parameter
    public func startWithServices() async throws {
        try await startWithServices(output: nil)
    }

    /// Default implementation for stopWithServices without output parameter
    public func stopWithServices() async throws {
        try await stopWithServices(output: nil)
    }

    /// Default implementation for refreshing build status
    public func refreshBuildStatus() {
        buildState.updateFromDisk(buildExists: isLambdaBuilt())
    }

    /// Default implementation: check status, start if any service is stopped, then refresh
    public func startIfNecessary() async {
        print("🔄 startIfNecessary called")
        do {
            let currentStatus = try await status()
            print("🔄 Lambda state: \(currentStatus.lambdaState), S3: \(currentStatus.s3State), Postgres: \(currentStatus.postgresState), DynamoDB: \(currentStatus.dynamodbState)")

            // Start if any service is stopped
            let anyServiceStopped = currentStatus.lambdaState == .stopped ||
                                    currentStatus.s3State == .stopped ||
                                    currentStatus.postgresState == .stopped ||
                                    currentStatus.dynamodbState == .stopped

            if anyServiceStopped {
                print("🔄 Starting services (some are stopped)...")
                try await startWithServices(output: nil)
            } else {
                print("🔄 All services already running, skipping start")
            }
        } catch {
            print("⚠️ Failed to start services: \(error)")
        }
        await refresh()
    }
}
