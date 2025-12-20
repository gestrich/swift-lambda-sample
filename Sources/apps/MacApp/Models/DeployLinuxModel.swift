import CLISDK
import ClientService
import Foundation
import StorageService
import DeployLocalService
import DeployCoreService
import DockerCLISDK
import LambdaBuildService
import DeployLinuxFeature
import LocalServicesFeature

/// Observable model for Linux container development workflow
/// Holds UI state and delegates operations to workflow factories
/// Conforms to LocalService for polymorphic usage
@MainActor
public class DeployLinuxModel: LocalService {
    public let cliClient: CLIClient

    /// Child model for managing Docker services (PostgreSQL, MinIO, DynamoDB).
    /// Views can access this directly for service-specific operations.
    public let servicesModel: LocalServicesModel

    // SDK clients for direct service operations
    private let dockerClient: DockerClient
    private let config: LinuxContainerConfig

    // Working directory and paths
    private let workingDirectory: String
    private let paths: LambdaPaths

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

    // MARK: - Derived Properties (Convenience Accessors)

    /// Whether the model is idle (not loading or operating).
    public var isIdle: Bool { state.isIdle }

    /// Whether a start operation can be performed.
    public var canStart: Bool { state.canStart }

    /// Whether a stop operation can be performed.
    public var canStop: Bool { state.canStop }

    /// Whether a build operation can be performed.
    public var canBuild: Bool { state.canBuild }

    /// Current deployment snapshot (from ready state or prior state during loading/operation).
    public var snapshot: LinuxSnapshot? { state.snapshot }

    /// The active use case state, if operating.
    public var useCaseState: LinuxUseCaseState? { state.useCaseState }

    /// Start time of the current operation, if any.
    public var operationStartTime: Date? { state.operationStartTime }

    // MARK: - Build State (Protocol Requirement - Derived from Unified State)

    /// Build state derived from unified `state` property.
    /// Required by `LocalService` protocol for UI compatibility.
    public var buildState: BuildState {
        get {
            // Derive from unified state
            if let useCaseState = state.useCaseState, useCaseState.isBuilding {
                return BuildState(status: .building)
            }
            if let snapshot = state.snapshot {
                switch snapshot.buildStatus {
                case .notBuilt:
                    return BuildState(status: .notBuilt)
                case .building:
                    return BuildState(status: .building)
                case .available:
                    return BuildState(status: .available)
                case .failed:
                    return BuildState(status: .failed(1))
                }
            }
            return BuildState(status: .notBuilt)
        }
        set {
            // Protocol requirement - external mutations are ignored.
            // Build state is managed through the unified state machine.
        }
    }

    // MARK: - Lambda State (Protocol Requirement - Derived from Unified State)

    /// Lambda state derived from unified `state` property.
    /// Required by `LocalService` protocol for UI compatibility.
    public var lambdaState: LambdaState {
        get {
            // Derive from use case state first (in-progress operations)
            if let useCaseState = state.useCaseState {
                if useCaseState.isStarting {
                    return LambdaState(status: .starting)
                }
                if useCaseState.isStopping {
                    return LambdaState(status: .stopping)
                }
            }
            // Fall back to snapshot (stable state)
            if let snapshot = state.snapshot {
                switch snapshot.lambdaState {
                case .running:
                    return LambdaState(status: .running)
                case .stopped:
                    return LambdaState(status: .stopped)
                case .starting:
                    return LambdaState(status: .starting)
                case .stopping:
                    return LambdaState(status: .stopping)
                }
            }
            return LambdaState(status: .stopped)
        }
        set {
            // Protocol requirement - external mutations are ignored.
            // Lambda state is managed through the unified state machine.
        }
    }

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
        self.paths = LambdaPaths(workingDirectory: workingDirectory)
        self.cliClient = CLIClient(defaultWorkingDirectory: workingDirectory)
        self.config = LinuxContainerConfig.default(workingDirectory: workingDirectory)

        let dockerClient = DockerClient(cliClient: cliClient)
        self.dockerClient = dockerClient

        self.servicesModel = LocalServicesModel(
            workingDirectory: workingDirectory,
            configuration: .linux
        )
        Task { await refresh() }
    }

    // MARK: - Service Management (Delegated to LocalServicesModel)

    /// Start all supporting services (S3, PostgreSQL, DynamoDB).
    /// Delegates to child LocalServicesModel.
    public func startAllServices() async throws {
        try await servicesModel.startAllServices()
    }

    /// Stop all supporting services (S3, PostgreSQL, DynamoDB).
    /// Delegates to child LocalServicesModel.
    public func stopAllServices() async throws {
        try await servicesModel.stopAllServices()
    }

    /// Start S3 service (MinIO).
    /// Delegates to child LocalServicesModel.
    public func startS3() async throws {
        try await servicesModel.startS3()
    }

    /// Create S3 bucket in MinIO.
    /// Delegates to child LocalServicesModel.
    public func createBucket(bucketName: String? = nil) async throws {
        try await servicesModel.createBucket(bucketName: bucketName)
    }

    /// Stop S3 service (MinIO).
    /// Delegates to child LocalServicesModel.
    public func stopS3() async throws {
        try await servicesModel.stopS3()
    }

    /// Start PostgreSQL database service.
    /// Delegates to child LocalServicesModel.
    public func startDatabase() async throws {
        try await servicesModel.startDatabase()
    }

    /// Stop PostgreSQL database service.
    /// Delegates to child LocalServicesModel.
    public func stopDatabase() async throws {
        try await servicesModel.stopDatabase()
    }

    /// Start DynamoDB Local service.
    /// Delegates to child LocalServicesModel.
    public func startDynamoDB() async throws {
        try await servicesModel.startDynamoDB()
    }

    /// Stop DynamoDB Local service.
    /// Delegates to child LocalServicesModel.
    public func stopDynamoDB() async throws {
        try await servicesModel.stopDynamoDB()
    }

    /// Data directory for S3 (MinIO).
    /// Delegates to child LocalServicesModel.
    public var s3DataDirectory: String {
        servicesModel.s3DataDirectory
    }

    /// Data directory for PostgreSQL.
    /// Delegates to child LocalServicesModel.
    public var postgresDataDirectory: String {
        servicesModel.postgresDataDirectory
    }

    /// Data directory for DynamoDB Local.
    /// Delegates to child LocalServicesModel.
    public var dynamodbDataDirectory: String {
        servicesModel.dynamodbDataDirectory
    }

    // MARK: - Build

    /// Build Lambda for Linux container.
    /// Uses use case-driven state updates instead of manual buildState marking.
    /// - Parameters:
    ///   - clean: Whether to clean build artifacts first
    ///   - output: Ignored - provided for protocol conformance (will be removed in Phase 11)
    public func build(clean: Bool = false, output: CLIOutputStream? = nil) async throws {
        guard canBuild else { return }
        let prior = snapshot

        let components = LinuxBuildUseCase.create(workingDirectory: workingDirectory)
        let options = LinuxBuildUseCase.Options(clean: clean)

        do {
            for try await useCaseState in components.useCase.stream(options: options) {
                state = ModelState(from: useCaseState, prior: prior)
            }
        } catch {
            state = ModelState(error: error, preserving: prior)
            throw error
        }
    }

    public func isLambdaBuilt() -> Bool {
        paths.isLinuxBuildComplete()
    }

    public func deleteBuild() async throws {
        let components = LinuxBuildUseCase.create(workingDirectory: workingDirectory)
        try await components.useCase.deleteBuild()
        // Reset to initial state with notBuilt status
        // The snapshot's buildStatus will be .notBuilt when we refresh
        if let snapshot = state.snapshot {
            state = .ready(LinuxSnapshot(
                serviceStatus: snapshot.serviceStatus,
                buildStatus: .notBuilt
            ))
        } else {
            state = .ready(LinuxSnapshot.initial)
        }
    }

    // MARK: - Lambda Lifecycle

    /// Start Lambda container.
    /// Uses use case-driven state updates instead of manual lambdaState marking.
    /// - Parameter output: Ignored - provided for protocol conformance (will be removed in Phase 11)
    public func startLambda(output: CLIOutputStream? = nil) async throws {
        guard isIdle else { return }
        let prior = snapshot

        let components = LinuxStartLambdaUseCase.create(workingDirectory: workingDirectory)

        do {
            for try await useCaseState in components.useCase.stream() {
                state = ModelState(from: useCaseState, prior: prior)
            }
        } catch {
            state = ModelState(error: error, preserving: prior)
            throw error
        }
    }

    /// Stop Lambda container.
    /// Uses use case-driven state updates instead of manual lambdaState marking.
    /// - Parameter output: Ignored - provided for protocol conformance (will be removed in Phase 11)
    public func stopLambda(output: CLIOutputStream? = nil) async throws {
        guard isIdle else { return }
        let prior = snapshot

        let components = LinuxStopLambdaUseCase.create(workingDirectory: workingDirectory)

        do {
            for try await useCaseState in components.useCase.stream() {
                state = ModelState(from: useCaseState, prior: prior)
            }
        } catch {
            state = ModelState(error: error, preserving: prior)
            throw error
        }
    }

    /// Start Lambda container with all supporting services.
    /// Uses model composition: calls servicesModel for services, then network setup, then lambda use case.
    /// - Parameter output: Ignored - provided for protocol conformance (will be removed in Phase 11)
    public func startWithServices(output: CLIOutputStream? = nil) async throws {
        guard state.canStart else { return }
        let prior = snapshot
        let startTime = Date()

        do {
            // Phase 1: Start services via child model (model composition)
            state = .operating(.startingServices(LinuxUseCaseState.ServicesProgress(
                step: .starting,
                startTime: startTime
            )), prior: prior)
            try await servicesModel.startAllServices()

            // Phase 2: Setup Docker network (Linux-specific)
            state = .operating(.settingUpNetwork(LinuxUseCaseState.NetworkProgress(
                step: .creatingNetwork,
                startTime: startTime
            )), prior: prior)
            let networkComponents = LinuxSetupNetworkUseCase.create(workingDirectory: workingDirectory)
            for try await networkState in networkComponents.useCase.stream() {
                let networkStep = mapNetworkStep(networkState.step)
                let message = mapNetworkDetail(networkState.detail)
                state = .operating(.settingUpNetwork(LinuxUseCaseState.NetworkProgress(
                    step: networkStep,
                    startTime: startTime,
                    message: message
                )), prior: prior)
            }

            // Phase 3: Start Lambda via use case
            state = .operating(.startingLambda(LinuxUseCaseState.LambdaProgress(
                step: .starting,
                startTime: startTime
            )), prior: prior)
            let lambdaComponents = LinuxStartLambdaUseCase.create(workingDirectory: workingDirectory)
            for try await useCaseState in lambdaComponents.useCase.stream() {
                state = ModelState(from: useCaseState, prior: prior)
            }
        } catch {
            state = ModelState(error: error, preserving: prior)
            throw error
        }
    }

    /// Stop Lambda container and all supporting services.
    /// Uses model composition: calls lambda use case first, then servicesModel for services.
    /// - Parameter output: Ignored - provided for protocol conformance (will be removed in Phase 11)
    public func stopWithServices(output: CLIOutputStream? = nil) async throws {
        guard state.canStop else { return }
        let prior = snapshot
        let startTime = Date()

        do {
            // Phase 1: Stop Lambda via use case
            state = .operating(.stoppingLambda(LinuxUseCaseState.LambdaProgress(
                step: .stopping,
                startTime: startTime
            )), prior: prior)
            let lambdaComponents = LinuxStopLambdaUseCase.create(workingDirectory: workingDirectory)
            for try await useCaseState in lambdaComponents.useCase.stream() {
                // Continue processing until completed, don't transition to ready yet
                if case .completed = useCaseState {
                    // Lambda stopped, continue to services
                } else {
                    state = .operating(useCaseState, prior: prior)
                }
            }

            // Phase 2: Stop services via child model (model composition)
            state = .operating(.stoppingServices(LinuxUseCaseState.ServicesProgress(
                step: .stopping,
                startTime: startTime
            )), prior: prior)
            try await servicesModel.stopAllServices()

            // Complete with snapshot
            let status = DeploymentStatus(
                lambdaState: .stopped,
                s3State: .stopped,
                postgresState: .stopped,
                dynamodbState: .stopped
            )
            let snapshot = LinuxSnapshot(
                serviceStatus: status,
                buildStatus: prior?.buildStatus ?? .notBuilt
            )
            state = .ready(snapshot)
        } catch {
            state = ModelState(error: error, preserving: prior)
            throw error
        }
    }

    // MARK: - Network Step Mapping Helpers

    private func mapNetworkStep(_ step: LinuxSetupNetworkUseCase.State.Step) -> LinuxUseCaseState.NetworkProgress.Step {
        switch step {
        case .creatingNetwork: return .creatingNetwork
        case .connectingContainers: return .connectingContainers
        case .complete: return .connectingContainers
        }
    }

    private func mapNetworkDetail(_ detail: LinuxSetupNetworkUseCase.State.Detail?) -> String? {
        switch detail {
        case .output(let msg): return msg
        case .networkCreated(let name): return "Network '\(name)' created"
        case .containerConnected(let name): return "Connected \(name)"
        case .containerSkipped(let name, let reason): return "Skipped \(name) (\(reason))"
        case nil: return nil
        }
    }

    /// Start services if needed based on current state.
    /// Refreshes status first, then starts services if any are stopped.
    /// Uses use case-driven state updates - errors are captured in state.
    public func startIfNecessary() async {
        guard isIdle else { return }

        await refresh()

        guard let snapshot = snapshot, snapshot.canStart else { return }

        try? await startWithServices()
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
        let components = LinuxTestUseCase.create(workingDirectory: workingDirectory)
        for try await _ in components.useCase.stream(options: ()) {
            // Consume use case progress
        }
    }

    // MARK: - Status

    public func status() async throws -> DeploymentStatus {
        let components = LinuxStatusUseCase.create(workingDirectory: workingDirectory)
        var result: DeploymentStatus = .stopped

        for try await progress in components.useCase.stream() {
            if case .completed(let snapshot) = progress {
                result = snapshot.serviceStatus
            }
        }
        return result
    }

    /// Refresh deployment status from Docker.
    /// Uses use case-driven state updates - the unified `state` property is the source of truth.
    @discardableResult
    public func refresh() async -> DeploymentStatus? {
        guard isIdle else { return nil }

        let prior = snapshot
        state = .loading(prior: prior)

        let components = LinuxStatusUseCase.create(workingDirectory: workingDirectory)

        do {
            for try await useCaseState in components.useCase.stream() {
                state = ModelState(from: useCaseState, prior: prior)
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
        let components = LinuxSetupNetworkUseCase.create(workingDirectory: workingDirectory)
        for try await _ in components.useCase.stream() {
            // Consume progress - could be extended to report to UI
        }
    }

    /// Run Lambda in interactive container
    public func runInteractive() async throws {
        let components = LinuxRunInteractiveUseCase.create(workingDirectory: workingDirectory)
        for try await _ in components.useCase.stream() {
            // Consume progress - could be extended to report to UI
        }
    }
}

// MARK: - Model State

extension DeployLinuxModel {
    /// Unified state machine for Linux development model.
    /// Mirrors `DeployRemoteModel.ModelState` for consistency.
    /// Uses `LinuxUseCaseState` and `LinuxSnapshot` from the service layer.
    public enum ModelState: Equatable {
        /// Initial state before any operation
        case uninitialized

        /// Loading/refreshing state from Docker (preserves prior state if available)
        case loading(prior: LinuxSnapshot?)

        /// Ready state with current deployment info
        case ready(LinuxSnapshot)

        /// Active use case in progress (uses LinuxUseCaseState from service layer)
        case operating(LinuxUseCaseState, prior: LinuxSnapshot?)

        // MARK: - Convenience Initializers

        /// Construct ModelState from a use case state plus app-layer prior.
        /// This is the key integration point between use cases and the model.
        public init(from useCaseState: LinuxUseCaseState, prior: LinuxSnapshot?) {
            if let snapshot = useCaseState.completedSnapshot {
                self = .ready(snapshot)
            } else {
                self = .operating(useCaseState, prior: prior)
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

        /// The active use case state, if operating
        public var useCaseState: LinuxUseCaseState? {
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
            useCaseState?.startTime
        }
    }
}
