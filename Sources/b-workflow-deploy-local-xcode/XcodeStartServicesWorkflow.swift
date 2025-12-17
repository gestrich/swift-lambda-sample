import Foundation
import c_service_deploy_local
import d_sdk_cli

/// Workflow for starting local services for Xcode development.
public struct XcodeStartServicesWorkflow: Sendable {
    private let service: XcodeLocalDevelopmentService

    public init(service: XcodeLocalDevelopmentService) {
        self.service = service
    }

    /// Progress updates from the start services workflow.
    public struct Progress: Sendable {
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

    /// Run the start services workflow.
    /// - Parameter options: Service options specifying which services to start
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
        // Start PostgreSQL
        if options.services.contains(.database) {
            continuation.yield(Progress(step: .startingDatabase))
            try await service.startDatabase()
            continuation.yield(Progress(step: .startingDatabase, detail: .serviceStarted(.database)))
        }

        // Start MinIO S3
        if options.services.contains(.s3) {
            continuation.yield(Progress(step: .startingS3))
            try await service.startS3()
            continuation.yield(Progress(step: .startingS3, detail: .serviceStarted(.s3)))

            // Create bucket after S3 is running
            continuation.yield(Progress(step: .creatingBucket))
            try await service.createBucket(bucketName: nil)
        }

        // Start DynamoDB Local
        if options.services.contains(.dynamodb) {
            continuation.yield(Progress(step: .startingDynamoDB))
            try await service.startDynamoDB()
            continuation.yield(Progress(step: .startingDynamoDB, detail: .serviceStarted(.dynamodb)))
        }

        continuation.yield(Progress(step: .complete))
        continuation.finish()
    }
}
