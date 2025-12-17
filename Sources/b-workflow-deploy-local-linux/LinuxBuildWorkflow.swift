import Foundation
import DeployLocalService
import CLISDK

/// Workflow for building Lambda for Linux/Docker container development.
public struct LinuxBuildWorkflow: Sendable {
    private let service: LinuxLocalDevelopmentService

    public init(service: LinuxLocalDevelopmentService) {
        self.service = service
    }

    /// Progress updates from the build workflow.
    public struct Progress: Sendable {
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

    /// Options for the build workflow.
    public struct Options: Sendable {
        public let clean: Bool

        public init(clean: Bool = false) {
            self.clean = clean
        }
    }

    /// Run the build workflow.
    /// - Parameter options: Build options
    /// - Returns: AsyncThrowingStream that yields Progress updates
    public func run(options: Options = Options()) -> AsyncThrowingStream<Progress, Error> {
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
                        continuation.yield(Progress(step: .building, detail: .output(trimmed)))
                    }
                case .exit, .command, .error:
                    break
                }
            }
        }

        defer { outputTask.cancel() }

        if options.clean {
            continuation.yield(Progress(step: .cleaning))
        }

        continuation.yield(Progress(step: .building))

        try await service.build(clean: options.clean, output: outputStream)

        continuation.yield(Progress(step: .complete, detail: .buildPath("lambda/")))
        continuation.finish()
    }
}
