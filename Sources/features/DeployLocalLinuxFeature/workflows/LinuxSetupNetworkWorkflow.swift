import Foundation
import DeployLocalService
import CLISDK
import Uniflow

/// Workflow for setting up Docker network for container communication.
public struct LinuxSetupNetworkWorkflow: StreamingWorkflow {
    private let service: LinuxLocalDevelopmentService

    public init(service: LinuxLocalDevelopmentService) {
        self.service = service
    }

    /// State updates from the setup network workflow.
    public struct State: Sendable {
        public let step: Step
        public let detail: Detail?

        public enum Step: Sendable, Equatable {
            case creatingNetwork
            case connectingContainers
            case complete
        }

        public enum Detail: Sendable {
            case output(String)
            case networkCreated(String)
            case containerConnected(String)
        }

        public init(step: Step, detail: Detail? = nil) {
            self.step = step
            self.detail = detail
        }
    }

    public typealias Result = State
    public typealias Options = Void

    /// Stream the setup network workflow.
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
        continuation.yield(State(step: .creatingNetwork))

        try await service.setupDockerNetwork()

        continuation.yield(State(step: .creatingNetwork, detail: .networkCreated("lambda-linux")))

        continuation.yield(State(step: .connectingContainers))
        continuation.yield(State(step: .connectingContainers, detail: .containerConnected("postgres-linux")))
        continuation.yield(State(step: .connectingContainers, detail: .containerConnected("minio-linux")))
        continuation.yield(State(step: .connectingContainers, detail: .containerConnected("dynamodb-linux")))

        continuation.yield(State(step: .complete))
        continuation.finish()
    }
}
