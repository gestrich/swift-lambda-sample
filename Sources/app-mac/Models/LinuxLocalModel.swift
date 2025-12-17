import d_sdk_cli
import d_sdk_client
import Combine
import Foundation
import c_service_storage
import c_service_deploy_local
import c_service_deploy_core
import c_service_lambda_build

/// Observable model for Linux container development workflow
/// Holds UI state and delegates operations to LinuxLocalDevelopmentService
/// Conforms to LocalService for polymorphic usage
@MainActor
public class LinuxLocalModel: LocalService {
    private let developmentService: LinuxLocalDevelopmentService
    public let cliClient: CLIClient
    private let storageService: LocalStorageService

    // Lambda configuration (for endpoint display)
    private let lambdaHostPort = 8081

    // Working directory
    private let workingDirectory: String

    // MARK: - Combine Publishers

    private let statusSubject = CurrentValueSubject<DeploymentStatus, Never>(.stopped)
    private let isLoadingStatusSubject = CurrentValueSubject<Bool, Never>(false)

    /// Flag to prevent refreshStatus from overwriting transitional states (starting/stopping)
    private var isTransitioning = false

    public var statusPublisher: AnyPublisher<DeploymentStatus, Never> {
        statusSubject.eraseToAnyPublisher()
    }

    public var isLoadingStatusPublisher: AnyPublisher<Bool, Never> {
        isLoadingStatusSubject.eraseToAnyPublisher()
    }

    // MARK: - Build State

    public var buildState = BuildState()

    // MARK: - Lambda State

    public var lambdaState = LambdaState()

    // MARK: - LambdaService Protocol

    public static let persistenceKey = "localLinux"

    public static let displayName = "Local Linux (Container)"

    public static let detailText = "Docker container build - matches AWS Lambda environment"

    public var port: Int { lambdaHostPort }

    public var endpoint: String {
        "http://localhost:\(lambdaHostPort)/invoke"
    }

    public var endpointLabel: String { "Local Lambda Endpoint" }

    public var endpointHelpText: String {
        "Make sure local Lambda container is running on port \(lambdaHostPort)"
    }

    public var apiClient: APIClient {
        APIClient(localPort: lambdaHostPort, serviceName: Self.displayName)
    }

    public var isConfigured: Bool { true }

    public init(workingDirectory: String) {
        self.workingDirectory = workingDirectory
        self.cliClient = CLIClient(defaultWorkingDirectory: workingDirectory)
        self.developmentService = LinuxLocalDevelopmentService(workingDirectory: workingDirectory)
        self.storageService = LocalStorageService()

        refreshBuildStatus()
    }

    // MARK: - Service Management

    public func startAllServices() async throws {
        try await developmentService.startAllServices()
    }

    public func stopAllServices() async throws {
        try await developmentService.stopAllServices()
    }

    public func startS3() async throws {
        try await developmentService.startS3()
    }

    public func createBucket(bucketName: String? = nil) async throws {
        try await developmentService.createBucket(bucketName: bucketName)
    }

    public func stopS3() async throws {
        try await developmentService.stopS3()
    }

    public func startDatabase() async throws {
        try await developmentService.startDatabase()
    }

    public func stopDatabase() async throws {
        try await developmentService.stopDatabase()
    }

    public func startDynamoDB() async throws {
        try await developmentService.startDynamoDB()
    }

    public func stopDynamoDB() async throws {
        try await developmentService.stopDynamoDB()
    }

    public var s3DataDirectory: String {
        storageService.dataDirectory(for: MinIOLinuxStorageKey.self)
    }

    public var postgresDataDirectory: String {
        storageService.dataDirectory(for: PostgreSQLLinuxStorageKey.self)
    }

    public var dynamodbDataDirectory: String {
        storageService.dataDirectory(for: DynamoDBLocalLinuxStorageKey.self)
    }

    // MARK: - Build

    public func build(clean: Bool = false, output: CLIOutputStream? = nil) async throws {
        buildState.startBuild()

        do {
            try await developmentService.build(clean: clean, output: output)
            buildState.markSuccess()
        } catch {
            buildState.markFailed(exitCode: 1)
            throw error
        }
    }

    public func isLambdaBuilt() -> Bool {
        let lambdaDir = "\(workingDirectory)/lambda"
        let bootstrapPath = "\(lambdaDir)/bootstrap"
        let lambdaZipPath = "\(workingDirectory)/lambda.zip"

        return FileManager.default.fileExists(atPath: lambdaDir) &&
               FileManager.default.fileExists(atPath: bootstrapPath) &&
               FileManager.default.fileExists(atPath: lambdaZipPath)
    }

    public func deleteBuild() async throws {
        try await developmentService.deleteBuild()
        buildState.clear()
    }

    // MARK: - Lambda Lifecycle

    public func startLambda(output: CLIOutputStream? = nil) async throws {
        lambdaState.startLambda()

        do {
            try await developmentService.startLambda(output: output)
            lambdaState.markRunning()
        } catch {
            lambdaState.markFailed(reason: error.localizedDescription)
            throw error
        }
    }

    public func stopLambda(output: CLIOutputStream? = nil) async throws {
        lambdaState.beginStop()

        do {
            try await developmentService.stopLambda(output: output)
            lambdaState.markStopped()
        } catch {
            lambdaState.markFailed(reason: error.localizedDescription)
            throw error
        }
    }

    public func startWithServices(output: CLIOutputStream? = nil) async throws {
        isTransitioning = true
        defer { isTransitioning = false }

        statusSubject.send(.starting)

        try await developmentService.startWithServices(output: output)
        lambdaState.markRunning()

        refreshStatus()
    }

    public func stopWithServices(output: CLIOutputStream? = nil) async throws {
        isTransitioning = true
        defer { isTransitioning = false }

        statusSubject.send(.stopping)

        try await developmentService.stopWithServices(output: output)
        lambdaState.markStopped()

        refreshStatus()
    }

    public func startIfNecessary() async {
        print("🔄 LinuxLocalModel.startIfNecessary called")

        isTransitioning = true

        do {
            let currentStatus = try await status()
            print("🔄 Lambda state: \(currentStatus.lambdaState), S3: \(currentStatus.s3State), Postgres: \(currentStatus.postgresState), DynamoDB: \(currentStatus.dynamodbState)")

            let anyServiceStopped = currentStatus.lambdaState == .stopped ||
                                    currentStatus.s3State == .stopped ||
                                    currentStatus.postgresState == .stopped ||
                                    currentStatus.dynamodbState == .stopped

            if anyServiceStopped {
                print("🔄 Starting services (some are stopped)...")
                try await startWithServices()
            } else {
                print("🔄 All services already running, skipping start")
                isTransitioning = false
                refreshStatus()
            }
        } catch {
            print("⚠️ Failed to start services: \(error)")
            isTransitioning = false
            refreshStatus()
        }
    }

    // MARK: - Testing

    public func waitForReady(maxAttempts: Int = 30) async throws {
        try await developmentService.waitForReady(maxAttempts: maxAttempts)
    }

    public func testLambda() async throws {
        try await developmentService.testLambda()
    }

    // MARK: - Status

    public func status() async throws -> DeploymentStatus {
        try await developmentService.status()
    }

    public func refreshStatus() {
        guard !isTransitioning else { return }

        let statusSubject = self.statusSubject
        let isLoadingStatusSubject = self.isLoadingStatusSubject

        isLoadingStatusSubject.send(true)
        Task {
            do {
                let newStatus = try await self.status()
                statusSubject.send(newStatus)

                // Sync lambdaState with actual running state (for app restart scenarios)
                if newStatus.lambdaState == .running && lambdaState.status == .stopped {
                    lambdaState.setRunning()
                } else if newStatus.lambdaState == .stopped && lambdaState.status == .running {
                    lambdaState.clear()
                }
            } catch {
                statusSubject.send(.stopped)
            }
            isLoadingStatusSubject.send(false)
        }
    }

    // MARK: - Linux-Specific Methods

    /// Setup Docker network for Lambda container
    public func setupDockerNetwork() async throws {
        try await developmentService.setupDockerNetwork()
    }

    /// Run Lambda in interactive container
    public func runInteractive() async throws {
        try await developmentService.runInteractive()
    }
}
