import Foundation
import c_service_deploy_local
import d_sdk_cli

/// Workflow for stopping the Lambda container.
public struct LinuxStopLambdaWorkflow: Sendable {
    private let service: LinuxLocalDevelopmentService

    public init(service: LinuxLocalDevelopmentService) {
        self.service = service
    }

    /// Progress updates from the stop Lambda workflow.
    public struct Progress: Sendable {
        public let step: Step
        public let detail: Detail?

        public enum Step: Sendable, Equatable {
            case checking
            case stopping
            case complete
        }

        public enum Detail: Sendable {
            case output(String)
            case wasRunning(Bool)
        }

        public init(step: Step, detail: Detail? = nil) {
            self.step = step
            self.detail = detail
        }
    }

    /// Run the stop Lambda workflow.
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
        let outputStream = CLIOutputStream()

        // Subscribe to output stream in background
        let stream = await outputStream.makeStream()
        let outputTask = Task {
            for await output in stream {
                switch output {
                case .stdout(_, let text), .stderr(_, let text):
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        continuation.yield(Progress(step: .stopping, detail: .output(trimmed)))
                    }
                case .exit, .command, .error:
                    break
                }
            }
        }

        defer { outputTask.cancel() }

        // Check if Lambda container is running
        continuation.yield(Progress(step: .checking))
        let wasRunning = try await service.isRunning()

        // Stop Lambda container
        continuation.yield(Progress(step: .stopping))
        try await service.stopLambda(output: outputStream)

        continuation.yield(Progress(step: .complete, detail: .wasRunning(wasRunning)))
        continuation.finish()
    }
}
