import Foundation
import DeployCoreService
import DeployLocalService

// MARK: - LinuxSnapshot (Stable State)

/// Represents stable deployment state when not operating.
/// This is the service-layer state type that use cases yield on completion.
/// Parallel to `DeploymentSnapshot` in DeployRemoteFeature.
public struct LinuxSnapshot: Sendable, Equatable {
    public let serviceStatus: DeploymentStatus
    public let buildStatus: BuildStatus

    public init(
        serviceStatus: DeploymentStatus,
        buildStatus: BuildStatus
    ) {
        self.serviceStatus = serviceStatus
        self.buildStatus = buildStatus
    }

    // MARK: - Convenience Accessors

    public var lambdaState: ServiceState { serviceStatus.lambdaState }
    public var s3State: ServiceState { serviceStatus.s3State }
    public var postgresState: ServiceState { serviceStatus.postgresState }
    public var dynamodbState: ServiceState { serviceStatus.dynamodbState }

    public var isAllRunning: Bool {
        lambdaState == .running &&
        s3State == .running &&
        postgresState == .running &&
        dynamodbState == .running
    }

    public var isAllStopped: Bool {
        lambdaState == .stopped &&
        s3State == .stopped &&
        postgresState == .stopped &&
        dynamodbState == .stopped
    }

    public var canStart: Bool {
        !lambdaState.isTransitioning &&
        !s3State.isTransitioning &&
        !postgresState.isTransitioning &&
        !dynamodbState.isTransitioning &&
        !isAllRunning
    }

    public var canStop: Bool {
        !lambdaState.isTransitioning &&
        !s3State.isTransitioning &&
        !postgresState.isTransitioning &&
        !dynamodbState.isTransitioning &&
        !isAllStopped
    }

    public var canBuild: Bool {
        switch buildStatus {
        case .notBuilt, .available:
            return true
        case .building, .failed:
            return false
        }
    }

    public var isBuilt: Bool {
        if case .available = buildStatus { return true }
        return false
    }

    public var errorMessage: String? {
        if case .failed(let reason) = buildStatus {
            return reason
        }
        return nil
    }

    // MARK: - Factory Methods

    /// Create a snapshot with all services stopped and not built
    public static var initial: LinuxSnapshot {
        LinuxSnapshot(
            serviceStatus: .stopped,
            buildStatus: .notBuilt
        )
    }

    /// Create a failed snapshot preserving prior state
    public static func failed(reason: String, preserving prior: LinuxSnapshot?) -> LinuxSnapshot {
        LinuxSnapshot(
            serviceStatus: prior?.serviceStatus ?? .stopped,
            buildStatus: .failed(reason: reason)
        )
    }

    // MARK: - Build Status

    public enum BuildStatus: Sendable, Equatable {
        case notBuilt
        case building
        case available
        case failed(reason: String)

        public var isBuilding: Bool {
            if case .building = self { return true }
            return false
        }
    }
}

// MARK: - LinuxUseCaseState (What use cases yield)

/// State yielded by a running use case.
/// Use cases capture `startTime` internally; the app layer adds `prior` when constructing ModelState.
/// Parallel to `UseCaseState` in DeployRemoteFeature.
public enum LinuxUseCaseState: Sendable, Equatable {
    case building(BuildProgress)
    case startingServices(ServicesProgress)
    case stoppingServices(ServicesProgress)
    case settingUpNetwork(NetworkProgress)
    case startingLambda(LambdaProgress)
    case stoppingLambda(LambdaProgress)
    case checkingStatus(StatusProgress)
    case testing(TestProgress)
    case completed(LinuxSnapshot)

    // MARK: - Build Progress

    /// Progress info for build operations
    public struct BuildProgress: Sendable, Equatable {
        public let step: Step
        public let startTime: Date
        public let output: String?

        public enum Step: Sendable, Equatable {
            case cleaning
            case building
        }

        public init(step: Step, startTime: Date, output: String? = nil) {
            self.step = step
            self.startTime = startTime
            self.output = output
        }
    }

    // MARK: - Services Progress

    /// Progress info for starting/stopping services (PostgreSQL, MinIO, DynamoDB)
    public struct ServicesProgress: Sendable, Equatable {
        public let step: Step
        public let startTime: Date
        public let currentService: LocalServiceType?

        public enum Step: Sendable, Equatable {
            case starting
            case stopping
            case checkingStatus
            case creatingBucket
        }

        public init(step: Step, startTime: Date, currentService: LocalServiceType? = nil) {
            self.step = step
            self.startTime = startTime
            self.currentService = currentService
        }
    }

    // MARK: - Network Progress

    /// Progress info for Docker network setup operations
    public struct NetworkProgress: Sendable, Equatable {
        public let step: Step
        public let startTime: Date
        public let message: String?

        public enum Step: Sendable, Equatable {
            case creatingNetwork
            case connectingContainers
        }

        public init(step: Step, startTime: Date, message: String? = nil) {
            self.step = step
            self.startTime = startTime
            self.message = message
        }
    }

    // MARK: - Lambda Progress

    /// Progress info for Lambda container operations
    public struct LambdaProgress: Sendable, Equatable {
        public let step: Step
        public let startTime: Date

        public enum Step: Sendable, Equatable {
            case starting
            case stopping
            case waitingForReady
        }

        public init(step: Step, startTime: Date) {
            self.step = step
            self.startTime = startTime
        }
    }

    // MARK: - Status Progress

    /// Progress info for status check operations
    public struct StatusProgress: Sendable, Equatable {
        public let step: Step
        public let startTime: Date
        public let serviceStatus: LocalServiceType?
        public let lambdaStatus: ServiceState?

        public enum Step: Sendable, Equatable {
            case checkingLambda
            case checkingS3
            case checkingDatabase
            case checkingDynamoDB
        }

        public init(
            step: Step,
            startTime: Date,
            serviceStatus: LocalServiceType? = nil,
            lambdaStatus: ServiceState? = nil
        ) {
            self.step = step
            self.startTime = startTime
            self.serviceStatus = serviceStatus
            self.lambdaStatus = lambdaStatus
        }
    }

    // MARK: - Test Progress

    /// Progress info for test operations
    public struct TestProgress: Sendable, Equatable {
        public let step: Step
        public let startTime: Date
        public let result: Result?

        public enum Step: Sendable, Equatable {
            case checkingLambda
            case testingFileUpload
            case testingFileList
            case testingFileDownload
            case testingDatabaseInit
        }

        public enum Result: Sendable, Equatable {
            case passed(String)
            case failed(String, String)
            case message(String)
        }

        public init(step: Step, startTime: Date, result: Result? = nil) {
            self.step = step
            self.startTime = startTime
            self.result = result
        }
    }

    // MARK: - Convenience Accessors

    /// Start time extracted from any in-progress state
    public var startTime: Date? {
        switch self {
        case .building(let p): return p.startTime
        case .startingServices(let p): return p.startTime
        case .stoppingServices(let p): return p.startTime
        case .settingUpNetwork(let p): return p.startTime
        case .startingLambda(let p): return p.startTime
        case .stoppingLambda(let p): return p.startTime
        case .checkingStatus(let p): return p.startTime
        case .testing(let p): return p.startTime
        case .completed: return nil
        }
    }

    /// Final snapshot if completed
    public var completedSnapshot: LinuxSnapshot? {
        if case .completed(let snapshot) = self { return snapshot }
        return nil
    }

    /// Whether this is a build operation
    public var isBuilding: Bool {
        if case .building = self { return true }
        return false
    }

    /// Whether this is a start operation
    public var isStarting: Bool {
        switch self {
        case .startingServices, .startingLambda: return true
        default: return false
        }
    }

    /// Whether this is a stop operation
    public var isStopping: Bool {
        switch self {
        case .stoppingServices, .stoppingLambda: return true
        default: return false
        }
    }

    /// Whether this is a status check operation
    public var isCheckingStatus: Bool {
        if case .checkingStatus = self { return true }
        return false
    }

    /// Whether this is a test operation
    public var isTesting: Bool {
        if case .testing = self { return true }
        return false
    }
}
