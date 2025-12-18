import Foundation
import DeployLocalService
import CLISDK
import Uniflow

/// Workflow for starting the Lambda as a native macOS process.
public struct XcodeStartLambdaWorkflow: StreamingWorkflow {
    private let service: XcodeLocalDevelopmentService

    public init(service: XcodeLocalDevelopmentService) {
        self.service = service
    }

    /// State updates from the start Lambda workflow.
    public struct State: Sendable {
        public let step: Step
        public let detail: Detail?

        public enum Step: Sendable, Equatable {
            case checkingBuild
            case starting
            case waitingForReady
            case complete
        }

        public enum Detail: Sendable {
            case output(String)
            case port(Int)
        }

        public init(step: Step, detail: Detail? = nil) {
            self.step = step
            self.detail = detail
        }
    }

    public typealias Result = State
    public typealias Options = Void

    /// Stream the start Lambda workflow.
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
        let outputStream = CLIOutputStream()

        // Subscribe to output stream in background
        let stream = await outputStream.makeStream()
        let outputTask = Task {
            for await output in stream {
                switch output {
                case .stdout(_, let text), .stderr(_, let text):
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        continuation.yield(State(step: .starting, detail: .output(trimmed)))
                    }
                case .exit, .command, .error:
                    break
                }
            }
        }

        defer { outputTask.cancel() }

        // Check if build exists
        continuation.yield(State(step: .checkingBuild))
        let isBuilt = await service.isLambdaBuilt()
        if !isBuilt {
            continuation.yield(State(step: .checkingBuild, detail: .output("Lambda not built, will build first")))
        }

        // Start Lambda (will build if needed)
        continuation.yield(State(step: .starting))
        try await service.startLambda(output: outputStream)

        // Wait for ready
        continuation.yield(State(step: .waitingForReady))
        try await service.waitForReady()

        continuation.yield(State(step: .complete, detail: .port(8080)))
        continuation.finish()
    }
}
