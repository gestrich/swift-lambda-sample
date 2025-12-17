import Foundation
import DeployLocalService
import DeployCoreService

/// Workflow for checking the status of local development services (Linux mode).
public struct LinuxStatusWorkflow: Sendable {
    private let service: LinuxLocalDevelopmentService

    public init(service: LinuxLocalDevelopmentService) {
        self.service = service
    }

    /// Progress updates from the status workflow.
    public struct Progress: Sendable {
        public let step: Step
        public let detail: Detail?

        public enum Step: Sendable, Equatable {
            case checkingLambda
            case checkingS3
            case checkingDatabase
            case checkingDynamoDB
            case complete
        }

        public enum Detail: Sendable {
            case serviceStatus(LocalServiceType, ServiceState)
            case lambdaStatus(ServiceState)
            case status(DeploymentStatus)
        }

        public init(step: Step, detail: Detail? = nil) {
            self.step = step
            self.detail = detail
        }
    }

    /// Run the status workflow.
    /// - Returns: AsyncThrowingStream that yields Progress updates
    public func run() -> AsyncThrowingStream<Progress, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    try await runWorkflow(continuation: continuation)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func runWorkflow(
        continuation: AsyncThrowingStream<Progress, Error>.Continuation
    ) async throws {
        continuation.yield(Progress(step: .checkingLambda))
        continuation.yield(Progress(step: .checkingS3))
        continuation.yield(Progress(step: .checkingDatabase))
        continuation.yield(Progress(step: .checkingDynamoDB))

        let status = try await service.status()

        continuation.yield(Progress(step: .complete, detail: .status(status)))
        continuation.finish()
    }
}
