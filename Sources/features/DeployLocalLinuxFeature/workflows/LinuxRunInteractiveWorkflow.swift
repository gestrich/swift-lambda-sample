import Foundation
import DeployLocalService
import CLISDK
import Uniflow

/// Workflow for running interactive container shell.
public struct LinuxRunInteractiveWorkflow: StreamingWorkflow {
    private let service: LinuxLocalDevelopmentService

    public init(service: LinuxLocalDevelopmentService) {
        self.service = service
    }

    /// State updates from the run interactive workflow.
    public struct State: Sendable {
        public let step: Step
        public let detail: Detail?

        public enum Step: Sendable, Equatable {
            case preparing
            case launching
            case complete
        }

        public enum Detail: Sendable {
            case output(String)
            case command(String)
        }

        public init(step: Step, detail: Detail? = nil) {
            self.step = step
            self.detail = detail
        }
    }

    public typealias Result = State
    public typealias Options = Void

    /// Stream the interactive workflow.
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
        continuation.yield(State(step: .preparing))

        // Check if Lambda is built
        let isBuilt = await service.isLambdaBuilt()
        if !isBuilt {
            continuation.yield(State(step: .preparing, detail: .output("Lambda not built, building first...")))
            try await service.build(output: nil)
        }

        continuation.yield(State(step: .launching))
        continuation.yield(State(step: .launching, detail: .output("Starting interactive container...")))

        // This will block until the user exits the container
        try await service.runInteractive()

        continuation.yield(State(step: .complete))
        continuation.finish()
    }
}
