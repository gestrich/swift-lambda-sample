import d_sdk_client
import d_sdk_cli
import Combine
import Foundation
import c_service_deploy_local
import c_service_deploy_core
import c_service_lambda_build

/// Model that wraps a LocalService, providing @Observable properties for SwiftUI.
/// Subscribes to the underlying service's publishers and updates observable properties.
/// Used by LocalServiceView - one instance for Xcode, another for Linux.
@MainActor
@Observable
class LocalServicesModel: LocalService {
    // MARK: - Underlying Service

    private let service: any LocalService

    // MARK: - Observable State (for SwiftUI)

    private(set) var status: DeploymentStatus = .stopped
    private(set) var isLoadingStatus: Bool = false

    // MARK: - Private

    private var cancellables = Set<AnyCancellable>()

    // Own publishers for protocol conformance
    private let statusSubject = CurrentValueSubject<DeploymentStatus, Never>(.stopped)
    private let isLoadingStatusSubject = CurrentValueSubject<Bool, Never>(false)

    // MARK: - Init

    init(service: any LocalService) {
        self.service = service
        subscribeToService()
    }

    private func subscribeToService() {
        // Relay status updates to @Observable property and own publisher
        service.statusPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newStatus in
                print("📊 LocalServicesModel received status: Lambda=\(newStatus.lambdaState), S3=\(newStatus.s3State), Postgres=\(newStatus.postgresState), DynamoDB=\(newStatus.dynamodbState)")
                self?.status = newStatus
                self?.statusSubject.send(newStatus)
            }
            .store(in: &cancellables)

        // Relay loading state updates
        service.isLoadingStatusPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isLoading in
                self?.isLoadingStatus = isLoading
                self?.isLoadingStatusSubject.send(isLoading)
            }
            .store(in: &cancellables)
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

    public var statusPublisher: AnyPublisher<DeploymentStatus, Never> {
        statusSubject.eraseToAnyPublisher()
    }

    public var isLoadingStatusPublisher: AnyPublisher<Bool, Never> {
        isLoadingStatusSubject.eraseToAnyPublisher()
    }

    public func testLambda() async throws {
        try await service.testLambda()
    }

    public func waitForReady(maxAttempts: Int) async throws {
        try await service.waitForReady(maxAttempts: maxAttempts)
    }

    public func status() async throws -> DeploymentStatus {
        try await service.status()
    }

    public func refreshStatus() {
        service.refreshStatus()
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
