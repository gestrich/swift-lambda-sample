import Foundation
import DeployLocalService
import CLISDK
import Uniflow

/// Workflow for stopping local services for Linux development.
public struct LinuxStopServicesWorkflow: StreamingWorkflow {
    private let service: LinuxLocalDevelopmentService

    public init(service: LinuxLocalDevelopmentService) {
        self.service = service
    }

    /// State updates from the stop services workflow.
    public struct State: Sendable {
        public let step: Step
        public let detail: Detail?

        public enum Step: Sendable, Equatable {
            case stoppingDatabase
            case stoppingS3
            case stoppingDynamoDB
            case complete
        }

        public enum Detail: Sendable {
            case output(String)
            case serviceStopped(LocalServiceType)
        }

        public init(step: Step, detail: Detail? = nil) {
            self.step = step
            self.detail = detail
        }
    }

    public typealias Result = State

    /// Options for the stop services workflow.
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

    /// Stream the stop services workflow.
    /// - Parameter options: Service options specifying which services to stop
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
        // Stop PostgreSQL
        if options.services.contains(.database) {
            continuation.yield(State(step: .stoppingDatabase))
            try await service.stopDatabase()
            continuation.yield(State(step: .stoppingDatabase, detail: .serviceStopped(.database)))
        }

        // Stop MinIO S3
        if options.services.contains(.s3) {
            continuation.yield(State(step: .stoppingS3))
            try await service.stopS3()
            continuation.yield(State(step: .stoppingS3, detail: .serviceStopped(.s3)))
        }

        // Stop DynamoDB Local
        if options.services.contains(.dynamodb) {
            continuation.yield(State(step: .stoppingDynamoDB))
            try await service.stopDynamoDB()
            continuation.yield(State(step: .stoppingDynamoDB, detail: .serviceStopped(.dynamodb)))
        }

        continuation.yield(State(step: .complete))
        continuation.finish()
    }
}
