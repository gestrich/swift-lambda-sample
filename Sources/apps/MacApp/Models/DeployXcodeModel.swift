import CLISDK
import ClientService
import Foundation
import StorageService
import DeployLocalService
import DeployCoreService
import LambdaBuildService
import DeployXcodeFeature

/// Observable model for native macOS Xcode development workflow
/// Holds UI state and delegates operations to Xcode use cases
/// Conforms to LocalService for polymorphic usage
@MainActor
public class DeployXcodeModel: LocalService {
    public let cliClient: CLIClient
    private let storageService: LocalStorageService

    // Lambda configuration (for endpoint display)
    private let lambdaHostPort = 8080

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
    public var snapshot: XcodeSnapshot? { state.snapshot }

    /// The active use case state, if operating.
    public var useCaseState: XcodeUseCaseState? { state.useCaseState }

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

    public static let persistenceKey = "localXcode"

    public static let displayName = "Local Xcode (Native)"

    public static let detailText = "Native macOS build - fast iteration, best for development"

    public var port: Int { lambdaHostPort }

    public var endpoint: String {
        "http://localhost:\(lambdaHostPort)/invoke"
    }

    public var endpointLabel: String { "Local Lambda Endpoint" }

    public var endpointHelpText: String {
        "Make sure local Lambda is running on port \(lambdaHostPort)"
    }

    public var apiClient: APIClient {
        APIClient(localPort: lambdaHostPort, serviceName: Self.displayName)
    }

    public var isConfigured: Bool { true }

    public init(workingDirectory: String) {
        self.workingDirectory = workingDirectory
        self.cliClient = CLIClient(defaultWorkingDirectory: workingDirectory)
        self.storageService = LocalStorageService()
        Task { await refresh() }
    }

    // MARK: - Service Management

    /// Start all local services (PostgreSQL, MinIO S3, DynamoDB Local).
    /// Uses use case-driven state updates.
    public func startAllServices() async throws {
        guard isIdle else { return }
        let prior = snapshot

        let components = XcodeStartServicesUseCase.create(workingDirectory: workingDirectory)

        do {
            for try await useCaseState in components.useCase.stream(options: .all) {
                state = ModelState(from: useCaseState, prior: prior)
            }
        } catch {
            state = ModelState(error: error, preserving: prior)
            throw error
        }
    }

    /// Stop all local services (PostgreSQL, MinIO S3, DynamoDB Local).
    /// Uses use case-driven state updates.
    public func stopAllServices() async throws {
        guard isIdle else { return }
        let prior = snapshot

        let components = XcodeStopServicesUseCase.create(workingDirectory: workingDirectory)

        do {
            for try await useCaseState in components.useCase.stream(options: .all) {
                state = ModelState(from: useCaseState, prior: prior)
            }
        } catch {
            state = ModelState(error: error, preserving: prior)
            throw error
        }
    }

    /// Start MinIO S3 service.
    /// Uses use case-driven state updates.
    public func startS3() async throws {
        guard isIdle else { return }
        let prior = snapshot

        let components = XcodeStartServicesUseCase.create(workingDirectory: workingDirectory)

        do {
            for try await useCaseState in components.useCase.stream(options: .only(.s3)) {
                state = ModelState(from: useCaseState, prior: prior)
            }
        } catch {
            state = ModelState(error: error, preserving: prior)
            throw error
        }
    }

    public func createBucket(bucketName: String? = nil) async throws {
        let components = XcodeStartServicesUseCase.create(workingDirectory: workingDirectory)
        try await components.minioClient.createBucket(bucketName: bucketName)
    }

    /// Stop MinIO S3 service.
    /// Uses use case-driven state updates.
    public func stopS3() async throws {
        guard isIdle else { return }
        let prior = snapshot

        let components = XcodeStopServicesUseCase.create(workingDirectory: workingDirectory)

        do {
            for try await useCaseState in components.useCase.stream(options: .only(.s3)) {
                state = ModelState(from: useCaseState, prior: prior)
            }
        } catch {
            state = ModelState(error: error, preserving: prior)
            throw error
        }
    }

    /// Start PostgreSQL database service.
    /// Uses use case-driven state updates.
    public func startDatabase() async throws {
        guard isIdle else { return }
        let prior = snapshot

        let components = XcodeStartServicesUseCase.create(workingDirectory: workingDirectory)

        do {
            for try await useCaseState in components.useCase.stream(options: .only(.database)) {
                state = ModelState(from: useCaseState, prior: prior)
            }
        } catch {
            state = ModelState(error: error, preserving: prior)
            throw error
        }
    }

    /// Stop PostgreSQL database service.
    /// Uses use case-driven state updates.
    public func stopDatabase() async throws {
        guard isIdle else { return }
        let prior = snapshot

        let components = XcodeStopServicesUseCase.create(workingDirectory: workingDirectory)

        do {
            for try await useCaseState in components.useCase.stream(options: .only(.database)) {
                state = ModelState(from: useCaseState, prior: prior)
            }
        } catch {
            state = ModelState(error: error, preserving: prior)
            throw error
        }
    }

    /// Start DynamoDB Local service.
    /// Uses use case-driven state updates.
    public func startDynamoDB() async throws {
        guard isIdle else { return }
        let prior = snapshot

        let components = XcodeStartServicesUseCase.create(workingDirectory: workingDirectory)

        do {
            for try await useCaseState in components.useCase.stream(options: .only(.dynamodb)) {
                state = ModelState(from: useCaseState, prior: prior)
            }
        } catch {
            state = ModelState(error: error, preserving: prior)
            throw error
        }
    }

    /// Stop DynamoDB Local service.
    /// Uses use case-driven state updates.
    public func stopDynamoDB() async throws {
        guard isIdle else { return }
        let prior = snapshot

        let components = XcodeStopServicesUseCase.create(workingDirectory: workingDirectory)

        do {
            for try await useCaseState in components.useCase.stream(options: .only(.dynamodb)) {
                state = ModelState(from: useCaseState, prior: prior)
            }
        } catch {
            state = ModelState(error: error, preserving: prior)
            throw error
        }
    }

    public var s3DataDirectory: String {
        storageService.dataDirectory(for: MinIOXcodeStorageKey.self)
    }

    public var postgresDataDirectory: String {
        storageService.dataDirectory(for: PostgreSQLXcodeStorageKey.self)
    }

    public var dynamodbDataDirectory: String {
        storageService.dataDirectory(for: DynamoDBLocalXcodeStorageKey.self)
    }

    // MARK: - Build

    /// Build Lambda for macOS.
    /// Uses use case-driven state updates.
    /// - Parameters:
    ///   - clean: Whether to perform a clean build
    ///   - output: Ignored - provided for protocol conformance
    public func build(clean: Bool = false, output: CLIOutputStream? = nil) async throws {
        guard canBuild else { return }
        let prior = snapshot

        let components = XcodeBuildUseCase.create(workingDirectory: workingDirectory)
        let options = XcodeBuildUseCase.Options(clean: clean)

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
        // Check synchronously using a known path pattern
        let debugDir = "\(workingDirectory)/.build"
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: debugDir) else {
            return false
        }

        for item in contents {
            let executablePath = "\(debugDir)/\(item)/debug/LambdaApp"
            if FileManager.default.fileExists(atPath: executablePath) {
                return true
            }
        }
        return false
    }

    public func deleteBuild() async throws {
        let components = XcodeBuildUseCase.create(workingDirectory: workingDirectory)
        try await components.useCase.deleteBuild()
        // Reset state to reflect build deletion
        let serviceStatus = snapshot?.serviceStatus ?? .stopped
        state = .ready(XcodeSnapshot(serviceStatus: serviceStatus, buildStatus: .notBuilt))
    }

    // MARK: - Lambda Lifecycle

    /// Start Lambda as a native macOS process.
    /// Uses use case-driven state updates.
    /// - Parameter output: Ignored - provided for protocol conformance
    public func startLambda(output: CLIOutputStream? = nil) async throws {
        guard isIdle else { return }
        let prior = snapshot

        let components = XcodeStartLambdaUseCase.create(workingDirectory: workingDirectory)

        do {
            for try await useCaseState in components.useCase.stream() {
                state = ModelState(from: useCaseState, prior: prior)
            }
        } catch {
            state = ModelState(error: error, preserving: prior)
            throw error
        }
    }

    /// Stop Lambda process.
    /// Uses use case-driven state updates.
    /// - Parameter output: Ignored - provided for protocol conformance
    public func stopLambda(output: CLIOutputStream? = nil) async throws {
        guard isIdle else { return }
        let prior = snapshot

        let components = XcodeStopLambdaUseCase.create()

        do {
            for try await useCaseState in components.useCase.stream() {
                state = ModelState(from: useCaseState, prior: prior)
            }
        } catch {
            state = ModelState(error: error, preserving: prior)
            throw error
        }
    }

    /// Start Lambda process with all supporting services.
    /// Uses use case-driven state updates.
    /// - Parameter output: Ignored - provided for protocol conformance
    public func startWithServices(output: CLIOutputStream? = nil) async throws {
        guard state.canStart else { return }
        let prior = snapshot

        let components = XcodeStartAllUseCase.create(workingDirectory: workingDirectory)

        do {
            for try await useCaseState in components.useCase.stream() {
                state = ModelState(from: useCaseState, prior: prior)
            }
        } catch {
            state = ModelState(error: error, preserving: prior)
            throw error
        }
    }

    /// Stop Lambda process and all supporting services.
    /// Uses use case-driven state updates.
    /// - Parameter output: Ignored - provided for protocol conformance
    public func stopWithServices(output: CLIOutputStream? = nil) async throws {
        guard state.canStop else { return }
        let prior = snapshot

        let components = XcodeStopAllUseCase.create(workingDirectory: workingDirectory)

        do {
            for try await useCaseState in components.useCase.stream() {
                state = ModelState(from: useCaseState, prior: prior)
            }
        } catch {
            state = ModelState(error: error, preserving: prior)
            throw error
        }
    }

    /// Start services if needed based on current state.
    /// Refreshes status first, then starts services if any are stopped.
    /// Uses use case-driven state updates - errors are captured in state.
    public func startIfNecessary() async {
        guard state.isIdle else { return }

        await refresh()

        guard let snapshot = snapshot, snapshot.canStart else { return }

        try? await startWithServices()
    }

    // MARK: - Testing

    public func waitForReady(maxAttempts: Int = 30) async throws {
        // Use XcodeStatusUseCase to check if Lambda is running
        let statusComponents = XcodeStatusUseCase.create()
        var attempts = 0
        var ready = false

        while attempts < maxAttempts && !ready {
            if await statusComponents.useCase.isLambdaRunning() {
                ready = true
                break
            }
            try await Task.sleep(for: .seconds(1))
            attempts += 1
        }

        if !ready {
            throw DeployError.testFailed(
                message: "Lambda failed to be ready on port \(lambdaHostPort) after \(maxAttempts) seconds"
            )
        }
    }

    public func testLambda() async throws {
        let components = XcodeTestUseCase.create(workingDirectory: workingDirectory)
        for try await _ in components.useCase.stream(options: ()) {
            // Use case progress is consumed
        }
    }

    // MARK: - Status

    public func status() async throws -> DeploymentStatus {
        let components = XcodeStatusUseCase.create()
        var result: DeploymentStatus = .stopped

        for try await useCaseState in components.useCase.stream() {
            if let snapshot = useCaseState.completedSnapshot {
                result = snapshot.serviceStatus
            }
        }
        return result
    }

    /// Refresh deployment status from system.
    /// Uses use case-driven state updates - the unified `state` property is the source of truth.
    @discardableResult
    public func refresh() async -> DeploymentStatus? {
        guard state.isIdle else { return nil }

        let prior = snapshot
        state = .loading(prior: prior)

        let components = XcodeStatusUseCase.create()

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
}

// MARK: - Model State

extension DeployXcodeModel {
    /// Unified state machine for Xcode development model.
    /// Mirrors `DeployRemoteModel.ModelState` and `DeployLinuxModel.ModelState` for consistency.
    /// Uses `XcodeUseCaseState` and `XcodeSnapshot` from the service layer.
    public enum ModelState: Equatable {
        /// Initial state before any operation
        case uninitialized

        /// Loading/refreshing state (preserves prior state if available)
        case loading(prior: XcodeSnapshot?)

        /// Ready state with current deployment info
        case ready(XcodeSnapshot)

        /// Active use case in progress (uses XcodeUseCaseState from service layer)
        case operating(XcodeUseCaseState, prior: XcodeSnapshot?)

        // MARK: - Convenience Initializers

        /// Construct ModelState from a use case state plus app-layer prior.
        /// This is the key integration point between use cases and the model.
        public init(from useCaseState: XcodeUseCaseState, prior: XcodeSnapshot?) {
            if let snapshot = useCaseState.completedSnapshot {
                self = .ready(snapshot)
            } else {
                self = .operating(useCaseState, prior: prior)
            }
        }

        /// Construct a failed ModelState from a caught error.
        public init(error: Error, preserving prior: XcodeSnapshot?) {
            self = .ready(.failed(reason: error.localizedDescription, preserving: prior))
        }

        // MARK: - Convenience Accessors

        /// Current deployment info (from ready state or prior state during loading/operation)
        public var snapshot: XcodeSnapshot? {
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
        public var useCaseState: XcodeUseCaseState? {
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
