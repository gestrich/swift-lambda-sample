import Foundation
import DeployLocalService
import CLISDK
import Uniflow

/// Workflow for starting local services for Xcode development.
public struct XcodeStartServicesWorkflow: StreamingWorkflow {
    private let service: XcodeLocalDevelopmentService

    public init(service: XcodeLocalDevelopmentService) {
        self.service = service
    }

    /// State updates from the start services workflow.
    public struct State: Sendable {
        public let step: Step
        public let detail: Detail?

        public enum Step: Sendable, Equatable {
            case startingDatabase
            case startingS3
            case creatingBucket
            case startingDynamoDB
            case complete
        }

        public enum Detail: Sendable {
            case output(String)
            case serviceStarted(LocalServiceType)
        }

        public init(step: Step, detail: Detail? = nil) {
            self.step = step
            self.detail = detail
        }
    }

    public typealias Result = State

    /// Options for the start services workflow.
    public struct Options: Sendable {
        public let services: Set<LocalServiceType>

        public init(services: Set<LocalServiceType>) {
            self.services = services
        }

        public static let all = Options(services: [.database, .s3, .dynamodb])

        public static func only(_ services: LocalServiceType...) -> Options {
            Options(services: Set(services))
        }
    }

    /// Stream the start services workflow.
    /// - Parameter options: Service options specifying which services to start
    /// - Returns: AsyncThrowingStream that yields State updates
    public func stream(options: Options) -> AsyncThrowingStream<State, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    try await runWorkflow(options: options, continuation: continuation)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func runWorkflow(
        options: Options,
        continuation: AsyncThrowingStream<State, Error>.Continuation
    ) async throws {
        // Start PostgreSQL
        if options.services.contains(.database) {
            continuation.yield(State(step: .startingDatabase))
            try await service.startDatabase()
            continuation.yield(State(step: .startingDatabase, detail: .serviceStarted(.database)))
        }

        // Start MinIO S3
        if options.services.contains(.s3) {
            continuation.yield(State(step: .startingS3))
            try await service.startS3()
            continuation.yield(State(step: .startingS3, detail: .serviceStarted(.s3)))

            // Create bucket after S3 is running
            continuation.yield(State(step: .creatingBucket))
            try await service.createBucket(bucketName: nil)
        }

        // Start DynamoDB Local
        if options.services.contains(.dynamodb) {
            continuation.yield(State(step: .startingDynamoDB))
            try await service.startDynamoDB()
            continuation.yield(State(step: .startingDynamoDB, detail: .serviceStarted(.dynamodb)))
        }

        continuation.yield(State(step: .complete))
        continuation.finish()
    }
}
