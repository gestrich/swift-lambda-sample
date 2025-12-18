import Foundation
import DeployLocalService
import DeployCoreService
import Uniflow

/// Workflow for checking the status of local development services (Xcode mode).
public struct XcodeStatusWorkflow: StreamingWorkflow {
    private let service: XcodeLocalDevelopmentService

    public init(service: XcodeLocalDevelopmentService) {
        self.service = service
    }

    /// State updates from the status workflow.
    public struct State: Sendable {
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

    public typealias Result = State
    public typealias Options = Void

    /// Stream the status workflow.
    /// - Returns: AsyncThrowingStream that yields State updates
    public func stream(options: Void) -> AsyncThrowingStream<State, Error> {
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
        continuation: AsyncThrowingStream<State, Error>.Continuation
    ) async throws {
        continuation.yield(State(step: .checkingLambda))
        continuation.yield(State(step: .checkingS3))
        continuation.yield(State(step: .checkingDatabase))
        continuation.yield(State(step: .checkingDynamoDB))

        let status = try await service.status()

        continuation.yield(State(step: .complete, detail: .status(status)))
        continuation.finish()
    }
}
