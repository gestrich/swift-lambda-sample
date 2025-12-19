import ClientService
import CLISDK
import Foundation
import DeployLocalService
import DeployCoreService
import LambdaBuildService

/// Model that wraps a LocalService, providing @Observable properties for SwiftUI.
/// Observes the underlying service's currentStatus and isLoadingStatus properties.
/// Used by LocalServiceView - one instance for Xcode, another for Linux.
@MainActor
@Observable
class LocalServicesModel: LocalService {
    // MARK: - Underlying Service

    private let service: any LocalService

    // MARK: - Observable State (for SwiftUI)
    // These mirror the underlying service's state for views that use LocalServicesModel directly

    var status: DeploymentStatus {
        service.currentStatus
    }

    public var currentStatus: DeploymentStatus {
        service.currentStatus
    }

    public var isLoadingStatus: Bool {
        service.isLoadingStatus
    }

    // MARK: - Init

    init(service: any LocalService) {
        self.service = service
    }

    // MARK: - LambdaService Protocol

    public static let persistenceKey = "localServicesModel"

    public static let displayName = "Local Services"

    public static let detailText = "Manages local service modes (Xcode or Linux)"

    public var port: Int { service.port }

    public var endpoint: String { service.endpoint }

    public var endpointLabel: String { service.endpointLabel }

    public var endpointHelpText: String { service.endpointHelpText }

    public var apiClient: APIClient { service.apiClient }

    public var isConfigured: Bool { service.isConfigured }

    public var cliClient: CLIClient { service.cliClient }

    public func testLambda() async throws {
        try await service.testLambda()
    }

    public func waitForReady(maxAttempts: Int) async throws {
        try await service.waitForReady(maxAttempts: maxAttempts)
    }

    public func status() async throws -> DeploymentStatus {
        try await service.status()
    }

    @discardableResult
    public func refresh() async -> DeploymentStatus? {
        await service.refresh()
    }

    // MARK: - Docker Services

    public func startAllServices() async throws {
        try await service.startAllServices()
    }

    public func stopAllServices() async throws {
        try await service.stopAllServices()
    }

    public func startS3() async throws {
        try await service.startS3()
    }

    public func createBucket(bucketName: String?) async throws {
        try await service.createBucket(bucketName: bucketName)
    }

    public func stopS3() async throws {
        try await service.stopS3()
    }

    public func startDatabase() async throws {
        try await service.startDatabase()
    }

    public func stopDatabase() async throws {
        try await service.stopDatabase()
    }

    public func startDynamoDB() async throws {
        try await service.startDynamoDB()
    }

    public func stopDynamoDB() async throws {
        try await service.stopDynamoDB()
    }

    public var s3DataDirectory: String { service.s3DataDirectory }

    public var postgresDataDirectory: String { service.postgresDataDirectory }

    public var dynamodbDataDirectory: String { service.dynamodbDataDirectory }

    // MARK: - Build

    public var buildState: BuildState {
        get { service.buildState }
        set { service.buildState = newValue }
    }

    public func build(clean: Bool, output: CLIOutputStream?) async throws {
        try await service.build(clean: clean, output: output)
    }

    public func isLambdaBuilt() -> Bool {
        service.isLambdaBuilt()
    }

    public func deleteBuild() async throws {
        try await service.deleteBuild()
    }

    // MARK: - Lambda Lifecycle

    public var lambdaState: LambdaState {
        get { service.lambdaState }
        set { service.lambdaState = newValue }
    }

    public func startLambda(output: CLIOutputStream?) async throws {
        try await service.startLambda(output: output)
    }

    public func stopLambda(output: CLIOutputStream?) async throws {
        try await service.stopLambda(output: output)
    }

    public func startWithServices(output: CLIOutputStream?) async throws {
        try await service.startWithServices(output: output)
    }

    public func stopWithServices(output: CLIOutputStream?) async throws {
        try await service.stopWithServices(output: output)
    }

    public func startIfNecessary() async {
        print("🔄 LocalServicesModel.startIfNecessary delegating to service")
        await service.startIfNecessary()
        print("🔄 LocalServicesModel.startIfNecessary completed")
    }
}
