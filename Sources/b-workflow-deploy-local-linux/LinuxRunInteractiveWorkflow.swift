import Foundation
import c_service_deploy_local
import CLISDK

/// Workflow for running interactive container shell.
public struct LinuxRunInteractiveWorkflow: Sendable {
    private let service: LinuxLocalDevelopmentService

    public init(service: LinuxLocalDevelopmentService) {
        self.service = service
    }

    /// Progress updates from the run interactive workflow.
    public struct Progress: Sendable {
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

    /// Run the interactive workflow.
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
        continuation.yield(Progress(step: .preparing))

        // Check if Lambda is built
        let isBuilt = await service.isLambdaBuilt()
        if !isBuilt {
            continuation.yield(Progress(step: .preparing, detail: .output("Lambda not built, building first...")))
            try await service.build(output: nil)
        }

        continuation.yield(Progress(step: .launching))
        continuation.yield(Progress(step: .launching, detail: .output("Starting interactive container...")))

        // This will block until the user exits the container
        try await service.runInteractive()

        continuation.yield(Progress(step: .complete))
        continuation.finish()
    }
}
