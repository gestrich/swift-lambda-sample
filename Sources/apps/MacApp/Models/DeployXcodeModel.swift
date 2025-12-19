import CLISDK
import ClientService
import Foundation
import StorageService
import DeployLocalService
import DeployCoreService
import LambdaBuildService
import DeployXcodeFeature

/// Observable model for native macOS Xcode development workflow
/// Holds UI state and delegates operations to Xcode workflows
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

    /// Flag to prevent refresh from overwriting transitional states (starting/stopping).
    /// Derived from unified state for backward compatibility during migration.
    private var isTransitioning: Bool {
        if case .operating = state { return true }
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

    /// The active workflow state, if operating.
    public var workflowState: XcodeWorkflowState? { state.workflowState }

    /// Start time of the current operation, if any.
    public var operationStartTime: Date? { state.operationStartTime }

    // MARK: - Build State

    public var buildState = BuildState()

    // MARK: - Lambda State

    public var lambdaState = LambdaState()

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
        // State starts as .uninitialized - caller should call refresh() to populate
    }

    // MARK: - Service Management

    public func startAllServices() async throws {
        let components = XcodeStartServicesWorkflow.create(workingDirectory: workingDirectory)
        for try await _ in components.workflow.stream(options: .all) {
            // Workflow progress is consumed
        }
    }

    public func stopAllServices() async throws {
        let components = XcodeStopServicesWorkflow.create(workingDirectory: workingDirectory)
        for try await _ in components.workflow.stream(options: .all) {
            // Workflow progress is consumed
        }
    }

    public func startS3() async throws {
        let components = XcodeStartServicesWorkflow.create(workingDirectory: workingDirectory)
        for try await _ in components.workflow.stream(options: .only(.s3)) {
            // Workflow progress is consumed
        }
    }

    public func createBucket(bucketName: String? = nil) async throws {
        let components = XcodeStartServicesWorkflow.create(workingDirectory: workingDirectory)
        try await components.minioClient.createBucket(bucketName: bucketName)
    }

    public func stopS3() async throws {
        let components = XcodeStopServicesWorkflow.create(workingDirectory: workingDirectory)
        for try await _ in components.workflow.stream(options: .only(.s3)) {
            // Workflow progress is consumed
        }
    }

    public func startDatabase() async throws {
        let components = XcodeStartServicesWorkflow.create(workingDirectory: workingDirectory)
        for try await _ in components.workflow.stream(options: .only(.database)) {
            // Workflow progress is consumed
        }
    }

    public func stopDatabase() async throws {
        let components = XcodeStopServicesWorkflow.create(workingDirectory: workingDirectory)
        for try await _ in components.workflow.stream(options: .only(.database)) {
            // Workflow progress is consumed
        }
    }

    public func startDynamoDB() async throws {
        let components = XcodeStartServicesWorkflow.create(workingDirectory: workingDirectory)
        for try await _ in components.workflow.stream(options: .only(.dynamodb)) {
            // Workflow progress is consumed
        }
    }

    public func stopDynamoDB() async throws {
        let components = XcodeStopServicesWorkflow.create(workingDirectory: workingDirectory)
        for try await _ in components.workflow.stream(options: .only(.dynamodb)) {
            // Workflow progress is consumed
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
    /// Uses workflow-driven state updates.
    /// - Parameters:
    ///   - clean: Whether to perform a clean build
    ///   - output: Ignored - provided for protocol conformance
    public func build(clean: Bool = false, output: CLIOutputStream? = nil) async throws {
        guard canBuild else { return }
        let prior = snapshot

        let components = XcodeBuildWorkflow.create(workingDirectory: workingDirectory)
        let options = XcodeBuildWorkflow.Options(clean: clean)

        do {
            for try await workflowState in components.workflow.stream(options: options) {
                state = ModelState(from: workflowState, prior: prior)
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
        let components = XcodeBuildWorkflow.create(workingDirectory: workingDirectory)
        try await components.workflow.deleteBuild()
        buildState.clear()
    }

    // MARK: - Lambda Lifecycle

    public func startLambda(output: CLIOutputStream? = nil) async throws {
        lambdaState.startLambda()

        do {
            let components = XcodeStartLambdaWorkflow.create(workingDirectory: workingDirectory)
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
            let components = XcodeStopLambdaWorkflow.create()
            for try await _ in components.workflow.stream() {
                // Workflow progress is consumed; UI updates via lambdaState
            }
            lambdaState.markStopped()
        } catch {
            lambdaState.markFailed(reason: error.localizedDescription)
            throw error
        }
    }

    /// Start Lambda process with all supporting services.
    /// Uses workflow-driven state updates.
    /// - Parameter output: Ignored - provided for protocol conformance
    public func startWithServices(output: CLIOutputStream? = nil) async throws {
        guard state.canStart else { return }
        let prior = snapshot

        let components = XcodeStartAllWorkflow.create(workingDirectory: workingDirectory)

        do {
            for try await workflowState in components.workflow.stream() {
                state = ModelState(from: workflowState, prior: prior)
            }
        } catch {
            state = ModelState(error: error, preserving: prior)
            throw error
        }
    }

    /// Stop Lambda process and all supporting services.
    /// Uses workflow-driven state updates.
    /// - Parameter output: Ignored - provided for protocol conformance
    public func stopWithServices(output: CLIOutputStream? = nil) async throws {
        guard state.canStop else { return }
        let prior = snapshot

        let components = XcodeStopAllWorkflow.create(workingDirectory: workingDirectory)

        do {
            for try await workflowState in components.workflow.stream() {
                state = ModelState(from: workflowState, prior: prior)
            }
        } catch {
            state = ModelState(error: error, preserving: prior)
            throw error
        }
    }

    /// Start services if needed based on current state.
    /// Refreshes status first, then starts services if any are stopped.
    /// Uses workflow-driven state updates - errors are captured in state.
    public func startIfNecessary() async {
        guard state.isIdle else { return }

        await refresh()

        guard let snapshot = snapshot, snapshot.canStart else { return }

        try? await startWithServices()
    }

    // MARK: - Testing

    public func waitForReady(maxAttempts: Int = 30) async throws {
        // Use XcodeStatusWorkflow to check if Lambda is running
        let statusComponents = XcodeStatusWorkflow.create()
        var attempts = 0
        var ready = false

        while attempts < maxAttempts && !ready {
            if await statusComponents.workflow.isLambdaRunning() {
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
        let components = XcodeTestWorkflow.create(workingDirectory: workingDirectory)
        for try await _ in components.workflow.stream(options: ()) {
            // Workflow progress is consumed
        }
    }

    // MARK: - Status

    public func status() async throws -> DeploymentStatus {
        let components = XcodeStatusWorkflow.create()
        var result: DeploymentStatus = .stopped

        for try await workflowState in components.workflow.stream() {
            if let snapshot = workflowState.completedSnapshot {
                result = snapshot.serviceStatus
            }
        }
        return result
    }

    /// Refresh deployment status from system.
    /// Uses workflow-driven state updates - the unified `state` property is the source of truth.
    @discardableResult
    public func refresh() async -> DeploymentStatus? {
        guard state.isIdle else { return nil }

        let prior = snapshot
        state = .loading(prior: prior)

        let components = XcodeStatusWorkflow.create()

        do {
            for try await workflowState in components.workflow.stream() {
                state = ModelState(from: workflowState, prior: prior)
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
    /// Uses `XcodeWorkflowState` and `XcodeSnapshot` from the service layer.
    public enum ModelState: Equatable {
        /// Initial state before any operation
        case uninitialized

        /// Loading/refreshing state (preserves prior state if available)
        case loading(prior: XcodeSnapshot?)

        /// Ready state with current deployment info
        case ready(XcodeSnapshot)

        /// Active workflow in progress (uses XcodeWorkflowState from service layer)
        case operating(XcodeWorkflowState, prior: XcodeSnapshot?)

        // MARK: - Convenience Initializers

        /// Construct ModelState from a workflow state plus app-layer prior.
        /// This is the key integration point between workflows and the model.
        public init(from workflowState: XcodeWorkflowState, prior: XcodeSnapshot?) {
            if let snapshot = workflowState.completedSnapshot {
                self = .ready(snapshot)
            } else {
                self = .operating(workflowState, prior: prior)
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

        /// The active workflow state, if operating
        public var workflowState: XcodeWorkflowState? {
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
