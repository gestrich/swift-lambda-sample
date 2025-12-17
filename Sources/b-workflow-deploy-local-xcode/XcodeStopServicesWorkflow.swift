import Foundation
import c_service_deploy_local
import CLISDK

/// Workflow for stopping local services for Xcode development.
public struct XcodeStopServicesWorkflow: Sendable {
    private let service: XcodeLocalDevelopmentService

    public init(service: XcodeLocalDevelopmentService) {
        self.service = service
    }

    /// Progress updates from the stop services workflow.
    public struct Progress: Sendable {
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

    /// Run the stop services workflow.
    /// - Parameter options: Service options specifying which services to stop
    /// - Returns: AsyncThrowingStream that yields Progress updates
    public func run(options: Options = .all) -> AsyncThrowingStream<Progress, Error> {
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
        continuation: AsyncThrowingStream<Progress, Error>.Continuation
    ) async throws {
        // Stop PostgreSQL
        if options.services.contains(.database) {
            continuation.yield(Progress(step: .stoppingDatabase))
            try await service.stopDatabase()
            continuation.yield(Progress(step: .stoppingDatabase, detail: .serviceStopped(.database)))
        }

        // Stop MinIO S3
        if options.services.contains(.s3) {
            continuation.yield(Progress(step: .stoppingS3))
            try await service.stopS3()
            continuation.yield(Progress(step: .stoppingS3, detail: .serviceStopped(.s3)))
        }

        // Stop DynamoDB Local
        if options.services.contains(.dynamodb) {
            continuation.yield(Progress(step: .stoppingDynamoDB))
            try await service.stopDynamoDB()
            continuation.yield(Progress(step: .stoppingDynamoDB, detail: .serviceStopped(.dynamodb)))
        }

        continuation.yield(Progress(step: .complete))
        continuation.finish()
    }
}
