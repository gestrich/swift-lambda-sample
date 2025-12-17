import Foundation
import DeployLocalService
import CLISDK

/// Workflow for copying configuration files to `~/.swiftSampleDemo/`.
public struct XcodeCopyConfigWorkflow: Sendable {
    private let service: XcodeLocalDevelopmentService

    public init(service: XcodeLocalDevelopmentService) {
        self.service = service
    }

    /// Progress updates from the copy config workflow.
    public struct Progress: Sendable {
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

    /// Run the copy config workflow.
    /// - Parameter sourcePath: Optional source path for the config file
    /// - Returns: AsyncThrowingStream that yields Progress updates
    public func run(sourcePath: String? = nil) -> AsyncThrowingStream<Progress, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    try await runWorkflow(sourcePath: sourcePath, continuation: continuation)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func runWorkflow(
        sourcePath: String?,
        continuation: AsyncThrowingStream<Progress, Error>.Continuation
    ) async throws {
        continuation.yield(Progress(step: .copying))

        try await service.copyConfig(sourcePath: sourcePath)

        // Get destination path for detail
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser.path
        let destPath = "\(homeDirectory)/.swiftSampleDemo/"

        continuation.yield(Progress(step: .copying, detail: .copiedFile("swiftLambdaDemo.json")))
        continuation.yield(Progress(step: .complete, detail: .destinationPath(destPath)))
        continuation.finish()
    }
}
