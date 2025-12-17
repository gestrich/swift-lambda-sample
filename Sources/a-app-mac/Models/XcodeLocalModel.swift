import CLISDK
import ClientService
import Combine
import Foundation
import StorageService
import DeployLocalService
import DeployCoreService
import LambdaBuildService
import b_workflow_deploy_local_xcode

/// Observable model for native macOS Xcode development workflow
/// Holds UI state and delegates operations to XcodeLocalDevelopmentService
/// Conforms to LocalService for polymorphic usage
@MainActor
public class XcodeLocalModel: LocalService {
    private let developmentService: XcodeLocalDevelopmentService
    public let cliClient: CLIClient
    private let storageService: LocalStorageService

    // Lambda configuration (for endpoint display)
    private let lambdaHostPort = 8080

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
        self.developmentService = XcodeLocalDevelopmentService(workingDirectory: workingDirectory)
        self.storageService = LocalStorageService()

        // Check for existing build artifacts
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
            let workflow = XcodeBuildWorkflow(service: developmentService)
            let options = XcodeBuildWorkflow.Options(clean: clean)
            for try await _ in workflow.run(options: options) {
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
            let executablePath = "\(debugDir)/\(item)/debug/app-lambda"
            if FileManager.default.fileExists(atPath: executablePath) {
                return true
            }
        }
        return false
    }

    public func deleteBuild() async throws {
        try await developmentService.deleteBuild()
        buildState.clear()
    }

    // MARK: - Lambda Lifecycle

    public func startLambda(output: CLIOutputStream? = nil) async throws {
        lambdaState.startLambda()

        do {
            let workflow = XcodeStartLambdaWorkflow(service: developmentService)
            for try await _ in workflow.run() {
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
            let workflow = XcodeStopLambdaWorkflow(service: developmentService)
            for try await _ in workflow.run() {
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

        let workflow = XcodeStartAllWorkflow(service: developmentService)
        for try await _ in workflow.run() {
            // Workflow progress is consumed; UI updates via statusSubject
        }
        lambdaState.markRunning()

        refreshStatus()
    }

    public func stopWithServices(output: CLIOutputStream? = nil) async throws {
        isTransitioning = true
        defer { isTransitioning = false }

        statusSubject.send(.stopping)

        let workflow = XcodeStopAllWorkflow(service: developmentService)
        for try await _ in workflow.run() {
            // Workflow progress is consumed; UI updates via statusSubject
        }
        lambdaState.markStopped()

        refreshStatus()
    }

    public func startIfNecessary() async {
        print("🔄 XcodeLocalModel.startIfNecessary called")

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
        let workflow = XcodeStatusWorkflow(service: developmentService)
        var result: DeploymentStatus = .stopped

        for try await progress in workflow.run() {
            if case .complete = progress.step,
               case .status(let status)? = progress.detail {
                result = status
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
}
