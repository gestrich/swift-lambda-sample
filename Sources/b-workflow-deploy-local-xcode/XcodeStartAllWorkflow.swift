import Foundation
import c_service_deploy_local
import CLISDK

/// Workflow for starting Lambda with all services for Xcode development.
public struct XcodeStartAllWorkflow: Sendable {
    private let service: XcodeLocalDevelopmentService

    public init(service: XcodeLocalDevelopmentService) {
        self.service = service
    }

    /// Progress updates from the start all workflow.
    public struct Progress: Sendable {
        public let step: Step
        public let detail: Detail?

        public enum Step: Sendable, Equatable {
            case startingServices
            case startingLambda
            case waitingForReady
            case complete
        }

        public enum Detail: Sendable {
            case output(String)
            case servicesProgress(XcodeStartServicesWorkflow.Progress)
            case lambdaProgress(XcodeStartLambdaWorkflow.Progress)
            case port(Int)
        }

        public init(step: Step, detail: Detail? = nil) {
            self.step = step
            self.detail = detail
        }
    }

    /// Run the start all workflow.
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
        // Start services first
        continuation.yield(Progress(step: .startingServices))
        let servicesWorkflow = XcodeStartServicesWorkflow(service: service)
        for try await servicesProgress in servicesWorkflow.run() {
            continuation.yield(Progress(
                step: .startingServices,
                detail: .servicesProgress(servicesProgress)
            ))
        }

        // Then start Lambda
        continuation.yield(Progress(step: .startingLambda))
        let lambdaWorkflow = XcodeStartLambdaWorkflow(service: service)
        for try await lambdaProgress in lambdaWorkflow.run() {
            continuation.yield(Progress(
                step: .startingLambda,
                detail: .lambdaProgress(lambdaProgress)
            ))
        }

        // Wait for Lambda to be ready
        continuation.yield(Progress(step: .waitingForReady))
        try await service.waitForReady()

        continuation.yield(Progress(step: .complete, detail: .port(8080)))
        continuation.finish()
    }
}
