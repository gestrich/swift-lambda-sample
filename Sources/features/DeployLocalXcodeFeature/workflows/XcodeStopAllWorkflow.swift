import Foundation
import DeployLocalService
import CLISDK

/// Workflow for stopping Lambda and all services for Xcode development.
public struct XcodeStopAllWorkflow: Sendable {
    private let service: XcodeLocalDevelopmentService

    public init(service: XcodeLocalDevelopmentService) {
        self.service = service
    }

    /// Progress updates from the stop all workflow.
    public struct Progress: Sendable {
        public let step: Step
        public let detail: Detail?

        public enum Step: Sendable, Equatable {
            case stoppingLambda
            case stoppingServices
            case complete
        }

        public enum Detail: Sendable {
            case output(String)
            case lambdaProgress(XcodeStopLambdaWorkflow.Progress)
            case servicesProgress(XcodeStopServicesWorkflow.Progress)
        }

        public init(step: Step, detail: Detail? = nil) {
            self.step = step
            self.detail = detail
        }
    }

    /// Run the stop all workflow.
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
        // Stop Lambda first
        continuation.yield(Progress(step: .stoppingLambda))
        let lambdaWorkflow = XcodeStopLambdaWorkflow(service: service)
        for try await lambdaProgress in lambdaWorkflow.run() {
            continuation.yield(Progress(
                step: .stoppingLambda,
                detail: .lambdaProgress(lambdaProgress)
            ))
        }

        // Then stop services
        continuation.yield(Progress(step: .stoppingServices))
        let servicesWorkflow = XcodeStopServicesWorkflow(service: service)
        for try await servicesProgress in servicesWorkflow.run() {
            continuation.yield(Progress(
                step: .stoppingServices,
                detail: .servicesProgress(servicesProgress)
            ))
        }

        continuation.yield(Progress(step: .complete))
        continuation.finish()
    }
}
