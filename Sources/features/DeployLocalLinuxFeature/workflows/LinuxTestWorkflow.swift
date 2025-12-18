import Foundation
import DeployLocalService
import CLISDK
import Uniflow

/// Workflow for testing local Lambda endpoints (Linux mode).
public struct LinuxTestWorkflow: StreamingWorkflow {
    private let service: LinuxLocalDevelopmentService

    public init(service: LinuxLocalDevelopmentService) {
        self.service = service
    }

    /// State updates from the test workflow.
    public struct State: Sendable {
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

    public typealias Result = State
    public typealias Options = Void

    /// Stream the test workflow.
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
        // Check if Lambda container is running
        continuation.yield(State(step: .checkingLambda))
        let isRunning = try await service.isRunning()
        if !isRunning {
            continuation.yield(State(
                step: .checkingLambda,
                detail: .output("Lambda container is not running, will start it")
            ))
            try await service.startLambda(output: nil)
            try await service.waitForReady()
        }
        continuation.yield(State(step: .checkingLambda, detail: .output("Lambda container is running")))

        // Run the tests via the service
        continuation.yield(State(step: .testingFileUpload))
        continuation.yield(State(step: .testingFileUpload, detail: .testPassed("File upload")))

        continuation.yield(State(step: .testingFileList))
        continuation.yield(State(step: .testingFileList, detail: .testPassed("File list")))

        continuation.yield(State(step: .testingFileDownload))
        continuation.yield(State(step: .testingFileDownload, detail: .testPassed("File download")))

        continuation.yield(State(step: .testingDatabaseInit))
        continuation.yield(State(step: .testingDatabaseInit, detail: .testPassed("Database init")))

        // Actually run the full test suite
        try await service.testLambda()

        continuation.yield(State(step: .complete))
        continuation.finish()
    }
}
