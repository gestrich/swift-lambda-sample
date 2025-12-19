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

        for try await progress in components.workflow.stream() {
            if case .complete = progress.step,
               case .status(let status)? = progress.detail {
                result = status
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
