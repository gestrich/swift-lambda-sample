import Foundation
import DeployLocalService
import CLISDK
import Uniflow

/// Workflow for copying configuration files to `~/.swiftSampleDemo/`.
public struct LinuxCopyConfigWorkflow: StreamingWorkflow {
    private let service: LinuxLocalDevelopmentService

    public init(service: LinuxLocalDevelopmentService) {
        self.service = service
    }

    /// State updates from the copy config workflow.
    public struct State: Sendable {
        public let step: Step
        public let detail: Detail?

        public enum Step: Sendable, Equatable {
            case copying
            case complete
        }

        public enum Detail: Sendable {
            case copiedFile(String)
            case destinationPath(String)
        }

        public init(step: Step, detail: Detail? = nil) {
            self.step = step
            self.detail = detail
        }
    }

    public typealias Result = State

    /// Options for the copy config workflow.
    public struct Options: Sendable {
        public let sourcePath: String?

        public init(sourcePath: String? = nil) {
            self.sourcePath = sourcePath
        }
    }

    /// Stream the copy config workflow.
    /// - Parameter options: Copy config options
    /// - Returns: AsyncThrowingStream that yields State updates
    public func stream(options: Options) -> AsyncThrowingStream<State, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    try await runWorkflow(sourcePath: options.sourcePath, continuation: continuation)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func runWorkflow(
        sourcePath: String?,
        continuation: AsyncThrowingStream<State, Error>.Continuation
    ) async throws {
        continuation.yield(State(step: .copying))

        try await service.copyConfig(sourcePath: sourcePath)

        // Get destination path for detail
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser.path
        let destPath = "\(homeDirectory)/.swiftSampleDemo/"

        continuation.yield(State(step: .copying, detail: .copiedFile("swiftLambdaDemo.json")))
        continuation.yield(State(step: .complete, detail: .destinationPath(destPath)))
        continuation.finish()
    }
}
