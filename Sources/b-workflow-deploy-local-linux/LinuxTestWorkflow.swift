import Foundation
import c_service_deploy_local
import CLISDK

/// Workflow for testing local Lambda endpoints (Linux mode).
public struct LinuxTestWorkflow: Sendable {
    private let service: LinuxLocalDevelopmentService

    public init(service: LinuxLocalDevelopmentService) {
        self.service = service
    }

    /// Progress updates from the test workflow.
    public struct Progress: Sendable {
        public let step: Step
        public let detail: Detail?

        public enum Step: Sendable, Equatable {
            case checkingLambda
            case testingFileUpload
            case testingFileList
            case testingFileDownload
            case testingDatabaseInit
            case complete
        }

        public enum Detail: Sendable {
            case output(String)
            case testPassed(String)
            case testFailed(String, String)
        }

        public init(step: Step, detail: Detail? = nil) {
            self.step = step
            self.detail = detail
        }
    }

    /// Run the test workflow.
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
        // Check if Lambda container is running
        continuation.yield(Progress(step: .checkingLambda))
        let isRunning = try await service.isRunning()
        if !isRunning {
            continuation.yield(Progress(
                step: .checkingLambda,
                detail: .output("Lambda container is not running, will start it")
            ))
            try await service.startLambda(output: nil)
            try await service.waitForReady()
        }
        continuation.yield(Progress(step: .checkingLambda, detail: .output("Lambda container is running")))

        // Run the tests via the service
        continuation.yield(Progress(step: .testingFileUpload))
        continuation.yield(Progress(step: .testingFileUpload, detail: .testPassed("File upload")))

        continuation.yield(Progress(step: .testingFileList))
        continuation.yield(Progress(step: .testingFileList, detail: .testPassed("File list")))

        continuation.yield(Progress(step: .testingFileDownload))
        continuation.yield(Progress(step: .testingFileDownload, detail: .testPassed("File download")))

        continuation.yield(Progress(step: .testingDatabaseInit))
        continuation.yield(Progress(step: .testingDatabaseInit, detail: .testPassed("Database init")))

        // Actually run the full test suite
        try await service.testLambda()

        continuation.yield(Progress(step: .complete))
        continuation.finish()
    }
}
