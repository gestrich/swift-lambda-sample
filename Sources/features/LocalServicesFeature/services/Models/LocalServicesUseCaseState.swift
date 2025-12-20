import Foundation
import DeployLocalService

/// State yielded by local services use cases during execution.
/// This is the unified use case state for Docker service operations.
/// Replaces the duplicate `ServicesProgress` types in `LinuxUseCaseState` and `XcodeUseCaseState`.
public enum LocalServicesUseCaseState: Sendable, Equatable {
    case starting(ServicesProgress)
    case stopping(ServicesProgress)
    case checkingStatus(StatusProgress)
    case completed(LocalServicesSnapshot)

    // MARK: - Services Progress

    /// Progress info for starting/stopping services (PostgreSQL, MinIO, DynamoDB)
    public struct ServicesProgress: Sendable, Equatable {
        public let step: Step
        public let startTime: Date
        public let currentService: LocalServiceType?

        public enum Step: Sendable, Equatable {
            case starting
            case stopping
            case creatingBucket
        }

        public init(step: Step, startTime: Date, currentService: LocalServiceType? = nil) {
            self.step = step
            self.startTime = startTime
            self.currentService = currentService
        }
    }

    // MARK: - Status Progress

    /// Progress info for status check operations
    public struct StatusProgress: Sendable, Equatable {
        public let step: Step
        public let startTime: Date

        public enum Step: Sendable, Equatable {
            case checkingS3
            case checkingDatabase
            case checkingDynamoDB
        }

        public init(step: Step, startTime: Date) {
            self.step = step
            self.startTime = startTime
        }
    }

    // MARK: - Convenience Accessors

    /// Start time extracted from any in-progress state
    public var startTime: Date? {
        switch self {
        case .starting(let p): return p.startTime
        case .stopping(let p): return p.startTime
        case .checkingStatus(let p): return p.startTime
        case .completed: return nil
        }
    }

    /// Final snapshot if completed
    public var completedSnapshot: LocalServicesSnapshot? {
        if case .completed(let snapshot) = self { return snapshot }
        return nil
    }

    /// Whether this is a start operation
    public var isStarting: Bool {
        if case .starting = self { return true }
        return false
    }

    /// Whether this is a stop operation
    public var isStopping: Bool {
        if case .stopping = self { return true }
        return false
    }

    /// Whether this is a status check operation
    public var isCheckingStatus: Bool {
        if case .checkingStatus = self { return true }
        return false
    }
}
