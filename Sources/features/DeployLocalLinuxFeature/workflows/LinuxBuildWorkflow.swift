import Foundation
import DeployLocalService
import CLISDK
import Uniflow

/// Workflow for building Lambda for Linux/Docker container development.
public struct LinuxBuildWorkflow: StreamingWorkflow {
    private let service: LinuxLocalDevelopmentService

    public init(service: LinuxLocalDevelopmentService) {
        self.service = service
    }

    /// State updates from the build workflow.
    public struct State: Sendable {
        public let step: Step
        public let detail: Detail?

        public enum Step: Sendable, Equatable {
            case cleaning
            case building
            case complete
        }

        public enum Detail: Sendable {
            case output(String)
            case buildPath(String)
        }

        public init(step: Step, detail: Detail? = nil) {
            self.step = step
            self.detail = detail
        }
    }

    public typealias Result = State

    /// Options for the build workflow.
    public struct Options: Sendable {
        public let clean: Bool

        public init(clean: Bool = false) {
            self.clean = clean
        }
    }

    /// Stream the build workflow.
    /// - Parameter options: Build options
    /// - Returns: AsyncThrowingStream that yields State updates
    public func stream(options: Options) -> AsyncThrowingStream<State, Error> {
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
                        continuation.yield(State(step: .building, detail: .output(trimmed)))
                    }
                case .exit, .command, .error:
                    break
                }
            }
        }

        defer { outputTask.cancel() }

        if options.clean {
            continuation.yield(State(step: .cleaning))
        }

        continuation.yield(State(step: .building))

        try await service.build(clean: options.clean, output: outputStream)

        continuation.yield(State(step: .complete, detail: .buildPath("lambda/")))
        continuation.finish()
    }
}
