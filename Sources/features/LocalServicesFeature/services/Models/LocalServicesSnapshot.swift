import Foundation
import DeployCoreService

/// Represents stable services state when not operating.
/// This is the unified snapshot type for local Docker services (PostgreSQL, MinIO, DynamoDB).
/// Replaces the duplicate service status portions of `LinuxSnapshot` and `XcodeSnapshot`.
public struct LocalServicesSnapshot: Sendable, Equatable {
    public let s3State: ServiceState
    public let postgresState: ServiceState
    public let dynamodbState: ServiceState

    public init(
        s3State: ServiceState,
        postgresState: ServiceState,
        dynamodbState: ServiceState
    ) {
        self.s3State = s3State
        self.postgresState = postgresState
        self.dynamodbState = dynamodbState
    }

    // MARK: - Convenience Accessors

    public var isAllRunning: Bool {
        s3State == .running &&
        postgresState == .running &&
        dynamodbState == .running
    }

    public var isAllStopped: Bool {
        s3State == .stopped &&
        postgresState == .stopped &&
        dynamodbState == .stopped
    }

    public var canStart: Bool {
        !s3State.isTransitioning &&
        !postgresState.isTransitioning &&
        !dynamodbState.isTransitioning &&
        !isAllRunning
    }

    public var canStop: Bool {
        !s3State.isTransitioning &&
        !postgresState.isTransitioning &&
        !dynamodbState.isTransitioning &&
        !isAllStopped
    }

    // MARK: - Factory Methods

    /// Create a snapshot with all services stopped
    public static var stopped: LocalServicesSnapshot {
        LocalServicesSnapshot(
            s3State: .stopped,
            postgresState: .stopped,
            dynamodbState: .stopped
        )
    }

    /// Create a snapshot with all services running
    public static var running: LocalServicesSnapshot {
        LocalServicesSnapshot(
            s3State: .running,
            postgresState: .running,
            dynamodbState: .running
        )
    }

    /// Create a snapshot from specific service states
    public static func from(
        s3Running: Bool,
        postgresRunning: Bool,
        dynamodbRunning: Bool
    ) -> LocalServicesSnapshot {
        LocalServicesSnapshot(
            s3State: s3Running ? .running : .stopped,
            postgresState: postgresRunning ? .running : .stopped,
            dynamodbState: dynamodbRunning ? .running : .stopped
        )
    }
}
