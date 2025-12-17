import Foundation
import c_service_deploy_local
import d_sdk_cli

/// Workflow for starting the Lambda as a native macOS process.
public struct XcodeStartLambdaWorkflow: Sendable {
    private let service: XcodeLocalDevelopmentService

    public init(service: XcodeLocalDevelopmentService) {
        self.service = service
    }

    /// Progress updates from the start Lambda workflow.
    public struct Progress: Sendable {
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

    /// Run the start Lambda workflow.
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
                        continuation.yield(Progress(step: .starting, detail: .output(trimmed)))
                    }
                case .exit, .command, .error:
                    break
                }
            }
        }

        defer { outputTask.cancel() }

        // Check if build exists
        continuation.yield(Progress(step: .checkingBuild))
        let isBuilt = await service.isLambdaBuilt()
        if !isBuilt {
            continuation.yield(Progress(step: .checkingBuild, detail: .output("Lambda not built, will build first")))
        }

        // Start Lambda (will build if needed)
        continuation.yield(Progress(step: .starting))
        try await service.startLambda(output: outputStream)

        // Wait for ready
        continuation.yield(Progress(step: .waitingForReady))
        try await service.waitForReady()

        continuation.yield(Progress(step: .complete, detail: .port(8080)))
        continuation.finish()
    }
}
