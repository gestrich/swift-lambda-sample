import CLISDK
import ClientService
import Combine
import Foundation
import StorageService
import DeployLocalService
import DeployCoreService
import DockerCLISDK
import DynamoDBSDK
import LambdaBuildService
import MinioSDK
import PostgreSQLSDK
import DeployLinuxFeature

/// Observable model for Linux container development workflow
/// Holds UI state and delegates operations to workflow factories
/// Conforms to LocalService for polymorphic usage
@MainActor
public class DeployLinuxModel: LocalService {
    public let cliClient: CLIClient
    private let storageService: LocalStorageService

    // SDK clients for direct service operations
    private let dockerClient: DockerClient
    private let postgresClient: PostgreSQLClient
    private let minioClient: MinIOClient
    private let dynamodbClient: DynamoDBClient
    private let config: LinuxContainerConfig

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

    public var port: Int { config.hostPort }

    public var endpoint: String {
        "http://localhost:\(config.hostPort)/invoke"
    }

    public var endpointLabel: String { "Local Lambda Endpoint" }

    public var endpointHelpText: String {
        "Make sure local Lambda container is running on port \(config.hostPort)"
    }

    public var apiClient: APIClient {
        APIClient(localPort: config.hostPort, serviceName: Self.displayName)
    }

    public var isConfigured: Bool { true }

    public init(workingDirectory: String) {
        self.workingDirectory = workingDirectory
        self.cliClient = CLIClient(defaultWorkingDirectory: workingDirectory)
        self.storageService = LocalStorageService()
        self.config = LinuxContainerConfig.default(workingDirectory: workingDirectory)

        let dockerClient = DockerClient(cliClient: cliClient)
        self.dockerClient = dockerClient

        self.postgresClient = PostgreSQLClient(
            dockerClient: dockerClient,
            config: .linux,
            dataDirectory: storageService.dataDirectory(for: PostgreSQLLinuxStorageKey.self)
        )
        self.minioClient = MinIOClient(
            dockerClient: dockerClient,
            networkName: config.networkName,
            config: .linux,
            dataDirectory: storageService.dataDirectory(for: MinIOLinuxStorageKey.self)
        )
        self.dynamodbClient = DynamoDBClient(
            dockerClient: dockerClient,
            config: .linux,
            dataDirectory: storageService.dataDirectory(for: DynamoDBLocalLinuxStorageKey.self)
        )

        refreshBuildStatus()
    }

    // MARK: - Service Management

    public func startAllServices() async throws {
        let components = LinuxStartServicesWorkflow.create(workingDirectory: workingDirectory)
        for try await _ in components.workflow.stream(options: .all) {
            // Consume workflow progress
        }
    }

    public func stopAllServices() async throws {
        let components = LinuxStopServicesWorkflow.create(workingDirectory: workingDirectory)
        for try await _ in components.workflow.stream(options: .all) {
            // Consume workflow progress
        }
    }

    public func startS3() async throws {
        let components = LinuxStartServicesWorkflow.create(workingDirectory: workingDirectory)
        for try await _ in components.workflow.stream(options: .only(.s3)) {
            // Consume workflow progress
        }
    }

    public func createBucket(bucketName: String? = nil) async throws {
        try await minioClient.createBucket(bucketName: bucketName)
    }

    public func stopS3() async throws {
        let components = LinuxStopServicesWorkflow.create(workingDirectory: workingDirectory)
        for try await _ in components.workflow.stream(options: .only(.s3)) {
            // Consume workflow progress
        }
    }

    public func startDatabase() async throws {
        let components = LinuxStartServicesWorkflow.create(workingDirectory: workingDirectory)
        for try await _ in components.workflow.stream(options: .only(.database)) {
            // Consume workflow progress
        }
    }

    public func stopDatabase() async throws {
        let components = LinuxStopServicesWorkflow.create(workingDirectory: workingDirectory)
        for try await _ in components.workflow.stream(options: .only(.database)) {
            // Consume workflow progress
        }
    }

    public func startDynamoDB() async throws {
        let components = LinuxStartServicesWorkflow.create(workingDirectory: workingDirectory)
        for try await _ in components.workflow.stream(options: .only(.dynamodb)) {
            // Consume workflow progress
        }
    }

    public func stopDynamoDB() async throws {
        let components = LinuxStopServicesWorkflow.create(workingDirectory: workingDirectory)
        for try await _ in components.workflow.stream(options: .only(.dynamodb)) {
            // Consume workflow progress
        }
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
            let components = LinuxBuildWorkflow.create(workingDirectory: workingDirectory)
            let options = LinuxBuildWorkflow.Options(clean: clean)
            for try await _ in components.workflow.stream(options: options) {
                // Workflow progress is consumed; UI updates via buildState
            }
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
        let components = LinuxBuildWorkflow.create(workingDirectory: workingDirectory)
        try await components.workflow.deleteBuild()
        buildState.clear()
    }

    // MARK: - Lambda Lifecycle

    public func startLambda(output: CLIOutputStream? = nil) async throws {
        lambdaState.startLambda()

        do {
            let components = LinuxStartLambdaWorkflow.create(workingDirectory: workingDirectory)
            for try await _ in components.workflow.stream() {
                // Workflow progress is consumed; UI updates via lambdaState
            }
            lambdaState.markRunning()
        } catch {
            lambdaState.markFailed(reason: error.localizedDescription)
            throw error
        }
    }

    public func stopLambda(output: CLIOutputStream? = nil) async throws {
        lambdaState.beginStop()

        do {
            let components = LinuxStopLambdaWorkflow.create(workingDirectory: workingDirectory)
            for try await _ in components.workflow.stream() {
                // Workflow progress is consumed; UI updates via lambdaState
            }
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

        let components = LinuxStartAllWorkflow.create(workingDirectory: workingDirectory)
        for try await _ in components.workflow.stream() {
            // Workflow progress is consumed; UI updates via statusSubject
        }
        lambdaState.markRunning()

        refreshStatus()
    }

    public func stopWithServices(output: CLIOutputStream? = nil) async throws {
        isTransitioning = true
        defer { isTransitioning = false }

        statusSubject.send(.stopping)

        let components = LinuxStopAllWorkflow.create(workingDirectory: workingDirectory)
        for try await _ in components.workflow.stream() {
            // Workflow progress is consumed; UI updates via statusSubject
        }
        lambdaState.markStopped()

        refreshStatus()
    }

    public func startIfNecessary() async {
        print("🔄 DeployLocalModel.startIfNecessary called")

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
        let isRunning = try await dockerClient.containerIsRunning(name: config.containerName)
        guard isRunning else {
            throw DeployError.testFailed(message: "Lambda container '\(config.containerName)' is not running")
        }

        var attempts = 0
        var ready = false

        while attempts < maxAttempts && !ready {
            let portCheck = try await cliClient.executeForResult(
                Lsof(port: ":\(config.hostPort)"),
                printCommand: false
            )

            if portCheck.isSuccess && !portCheck.stdout.isEmpty {
                ready = true
                break
            }

            try await Task.sleep(for: .seconds(1))
            attempts += 1
        }

        if !ready {
            let logsResult = try await cliClient.execute(
                command: "docker",
                arguments: ["logs", config.containerName],
                printCommand: false
            )
            throw DeployError.testFailed(
                message: "Lambda failed to be ready on port \(config.hostPort) after \(maxAttempts) seconds. Logs: \(logsResult.stdout) \(logsResult.stderr)"
            )
        }
    }

    public func testLambda() async throws {
        let components = LinuxTestWorkflow.create(workingDirectory: workingDirectory)
        for try await _ in components.workflow.stream(options: ()) {
            // Consume workflow progress
        }
    }

    // MARK: - Status

    public func status() async throws -> DeploymentStatus {
        let components = LinuxStatusWorkflow.create(workingDirectory: workingDirectory)
        var result: DeploymentStatus = .stopped

        for try await progress in components.workflow.stream() {
            if case .completed(let snapshot) = progress {
                result = snapshot.serviceStatus
            }
        }
        return result
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
        let components = LinuxSetupNetworkWorkflow.create(workingDirectory: workingDirectory)
        for try await _ in components.workflow.stream() {
            // Consume progress - could be extended to report to UI
        }
    }

    /// Run Lambda in interactive container
    public func runInteractive() async throws {
        let components = LinuxRunInteractiveWorkflow.create(workingDirectory: workingDirectory)
        for try await _ in components.workflow.stream() {
            // Consume progress - could be extended to report to UI
        }
    }
}
