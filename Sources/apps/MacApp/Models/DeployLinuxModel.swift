import CLISDK
import ClientService
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

    // MARK: - Unified State

    /// Unified state machine for all deployment operations.
    /// Replaces scattered properties: currentStatus, isLoadingStatus, isTransitioning
    public private(set) var state: ModelState = .uninitialized

    // MARK: - Derived Properties (Protocol Compatibility)

    /// Current deployment status derived from unified state.
    /// Required by LambdaService protocol.
    public var currentStatus: DeploymentStatus {
        state.snapshot?.serviceStatus ?? .stopped
    }

    /// Whether a status refresh is in progress.
    /// Derived from unified state for backward compatibility.
    public var isLoadingStatus: Bool {
        if case .loading = state { return true }
        return false
    }

    /// Whether a transition operation is in progress.
    /// Derived from unified state. Used by refresh() to avoid conflicting updates.
    /// Will be removed when operations are refactored to use state machine (Phases 4-9).
    private var isTransitioning: Bool {
        if case .operating = state { return true }
        return false
    }

    // MARK: - Build State (Protocol Requirement)

    public var buildState = BuildState()

    // MARK: - Lambda State (Protocol Requirement)

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
        let prior = state.snapshot

        let components = LinuxStartAllWorkflow.create(workingDirectory: workingDirectory)
        for try await workflowState in components.workflow.stream() {
            state = ModelState(from: workflowState, prior: prior)
        }
        lambdaState.markRunning()
    }

    public func stopWithServices(output: CLIOutputStream? = nil) async throws {
        let prior = state.snapshot

        let components = LinuxStopAllWorkflow.create(workingDirectory: workingDirectory)
        for try await workflowState in components.workflow.stream() {
            state = ModelState(from: workflowState, prior: prior)
        }
        lambdaState.markStopped()
    }

    public func startIfNecessary() async {
        print("🔄 DeployLocalModel.startIfNecessary called")
        guard state.isIdle else { return }

        await refresh()

        guard let snapshot = state.snapshot else { return }

        print("🔄 Lambda state: \(snapshot.lambdaState), S3: \(snapshot.s3State), Postgres: \(snapshot.postgresState), DynamoDB: \(snapshot.dynamodbState)")

        if snapshot.canStart {
            print("🔄 Starting services (some are stopped)...")
            do {
                try await startWithServices()
            } catch {
                print("⚠️ Failed to start services: \(error)")
                state = ModelState(error: error, preserving: snapshot)
            }
        } else {
            print("🔄 All services already running, skipping start")
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

    @discardableResult
    public func refresh() async -> DeploymentStatus? {
        guard state.isIdle else { return nil }

        let prior = state.snapshot
        state = .loading(prior: prior)

        let components = LinuxStatusWorkflow.create(workingDirectory: workingDirectory)

        do {
            for try await workflowState in components.workflow.stream() {
                state = ModelState(from: workflowState, prior: prior)
            }

            // Sync lambdaState with actual running state (for app restart scenarios)
            if let snapshot = state.snapshot {
                if snapshot.lambdaState == .running && lambdaState.status == .stopped {
                    lambdaState.setRunning()
                } else if snapshot.lambdaState == .stopped && lambdaState.status == .running {
                    lambdaState.clear()
                }
            }

            return state.snapshot?.serviceStatus
        } catch {
            state = ModelState(error: error, preserving: prior)
            return nil
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

// MARK: - Model State

extension DeployLinuxModel {
    /// Unified state machine for Linux development model.
    /// Mirrors `DeployRemoteModel.ModelState` for consistency.
    /// Uses `LinuxWorkflowState` and `LinuxSnapshot` from the service layer.
    public enum ModelState: Equatable {
        /// Initial state before any operation
        case uninitialized

        /// Loading/refreshing state from Docker (preserves prior state if available)
        case loading(prior: LinuxSnapshot?)

        /// Ready state with current deployment info
        case ready(LinuxSnapshot)

        /// Active workflow in progress (uses LinuxWorkflowState from service layer)
        case operating(LinuxWorkflowState, prior: LinuxSnapshot?)

        // MARK: - Convenience Initializers

        /// Construct ModelState from a workflow state plus app-layer prior.
        /// This is the key integration point between workflows and the model.
        public init(from workflowState: LinuxWorkflowState, prior: LinuxSnapshot?) {
            if let snapshot = workflowState.completedSnapshot {
                self = .ready(snapshot)
            } else {
                self = .operating(workflowState, prior: prior)
            }
        }

        /// Construct a failed ModelState from a caught error.
        public init(error: Error, preserving prior: LinuxSnapshot?) {
            self = .ready(.failed(reason: error.localizedDescription, preserving: prior))
        }

        // MARK: - Convenience Accessors

        /// Current deployment info (from ready state or prior state during loading/operation)
        public var snapshot: LinuxSnapshot? {
            switch self {
            case .uninitialized:
                return nil
            case .loading(let prior):
                return prior
            case .ready(let snapshot):
                return snapshot
            case .operating(_, let prior):
                return prior
            }
        }

        /// The active workflow state, if operating
        public var workflowState: LinuxWorkflowState? {
            guard case .operating(let state, _) = self else { return nil }
            return state
        }

        /// Whether the model is idle (not loading or operating)
        public var isIdle: Bool {
            switch self {
            case .uninitialized, .ready:
                return true
            case .loading, .operating:
                return false
            }
        }

        /// Whether a start operation can be performed
        public var canStart: Bool {
            switch self {
            case .ready(let snapshot):
                return snapshot.canStart
            case .uninitialized:
                return true
            case .loading, .operating:
                return false
            }
        }

        /// Whether a stop operation can be performed
        public var canStop: Bool {
            switch self {
            case .ready(let snapshot):
                return snapshot.canStop
            case .uninitialized, .loading, .operating:
                return false
            }
        }

        /// Whether a build operation can be performed
        public var canBuild: Bool {
            switch self {
            case .ready(let snapshot):
                return snapshot.canBuild
            case .uninitialized:
                return true
            case .loading, .operating:
                return false
            }
        }

        /// Start time of the current operation, if any
        public var operationStartTime: Date? {
            workflowState?.startTime
        }
    }
}
