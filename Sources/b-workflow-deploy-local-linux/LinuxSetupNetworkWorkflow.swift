import Foundation
import c_service_deploy_local
import CLISDK

/// Workflow for setting up Docker network for container communication.
public struct LinuxSetupNetworkWorkflow: Sendable {
    private let service: LinuxLocalDevelopmentService

    public init(service: LinuxLocalDevelopmentService) {
        self.service = service
    }

    /// Progress updates from the setup network workflow.
    public struct Progress: Sendable {
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

    /// Run the setup network workflow.
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
        continuation.yield(Progress(step: .creatingNetwork))

        try await service.setupDockerNetwork()

        continuation.yield(Progress(step: .creatingNetwork, detail: .networkCreated("lambda-linux")))

        continuation.yield(Progress(step: .connectingContainers))
        continuation.yield(Progress(step: .connectingContainers, detail: .containerConnected("postgres-linux")))
        continuation.yield(Progress(step: .connectingContainers, detail: .containerConnected("minio-linux")))
        continuation.yield(Progress(step: .connectingContainers, detail: .containerConnected("dynamodb-linux")))

        continuation.yield(Progress(step: .complete))
        continuation.finish()
    }
}
