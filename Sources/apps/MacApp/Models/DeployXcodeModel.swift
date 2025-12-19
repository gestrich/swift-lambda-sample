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

    // MARK: - Observable State

    /// Current deployment status (observable via @Observable on class when migrated)
    public private(set) var currentStatus: DeploymentStatus = .stopped

    /// Whether a status refresh is in progress
    public private(set) var isLoadingStatus: Bool = false

    /// Flag to prevent refresh from overwriting transitional states (starting/stopping)
    private var isTransitioning = false

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

        // Check for existing build artifacts
        refreshBuildStatus()
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

    public func build(clean: Bool = false, output: CLIOutputStream? = nil) async throws {
        buildState.startBuild()

        do {
            let components = XcodeBuildWorkflow.create(workingDirectory: workingDirectory)
            let options = XcodeBuildWorkflow.Options(clean: clean)
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

    public func startWithServices(output: CLIOutputStream? = nil) async throws {
        isTransitioning = true
        defer { isTransitioning = false }

        currentStatus = .starting

        let components = XcodeStartAllWorkflow.create(workingDirectory: workingDirectory)
        for try await _ in components.workflow.stream() {
            // Workflow progress is consumed
        }
        lambdaState.markRunning()

        await refresh()
    }

    public func stopWithServices(output: CLIOutputStream? = nil) async throws {
        isTransitioning = true
        defer { isTransitioning = false }

        currentStatus = .stopping

        let components = XcodeStopAllWorkflow.create(workingDirectory: workingDirectory)
        for try await _ in components.workflow.stream() {
            // Workflow progress is consumed
        }
        lambdaState.markStopped()

        await refresh()
    }

    public func startIfNecessary() async {
        print("🔄 DeployXcodeModel.startIfNecessary called")

        isTransitioning = true

        do {
            let statusResult = try await status()
            print("🔄 Lambda state: \(statusResult.lambdaState), S3: \(statusResult.s3State), Postgres: \(statusResult.postgresState), DynamoDB: \(statusResult.dynamodbState)")

            let anyServiceStopped = statusResult.lambdaState == .stopped ||
                                    statusResult.s3State == .stopped ||
                                    statusResult.postgresState == .stopped ||
                                    statusResult.dynamodbState == .stopped

            if anyServiceStopped {
                print("🔄 Starting services (some are stopped)...")
                try await startWithServices()
            } else {
                print("🔄 All services already running, skipping start")
                isTransitioning = false
                await refresh()
            }
        } catch {
            print("⚠️ Failed to start services: \(error)")
            isTransitioning = false
            await refresh()
        }
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

    @discardableResult
    public func refresh() async -> DeploymentStatus? {
        guard !isTransitioning else { return nil }

        isLoadingStatus = true
        defer { isLoadingStatus = false }

        do {
            let newStatus = try await self.status()
            currentStatus = newStatus

            // Sync lambdaState with actual running state (for app restart scenarios)
            if newStatus.lambdaState == .running && lambdaState.status == .stopped {
                lambdaState.setRunning()
            } else if newStatus.lambdaState == .stopped && lambdaState.status == .running {
                lambdaState.clear()
            }

            return newStatus
        } catch {
            currentStatus = .stopped
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
