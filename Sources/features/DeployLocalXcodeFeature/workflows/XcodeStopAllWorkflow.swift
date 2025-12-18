import Foundation
import DeployLocalService
import CLISDK
import Uniflow

/// Workflow for stopping Lambda and all services for Xcode development.
public struct XcodeStopAllWorkflow: StreamingWorkflow {
    private let service: XcodeLocalDevelopmentService

    public init(service: XcodeLocalDevelopmentService) {
        self.service = service
    }

    /// State updates from the stop all workflow.
    public struct State: Sendable {
        public let step: Step
        public let detail: Detail?

        public enum Step: Sendable, Equatable {
            case stoppingLambda
            case stoppingServices
            case complete
        }

        public enum Detail: Sendable {
            case output(String)
            case lambdaState(XcodeStopLambdaWorkflow.State)
            case servicesState(XcodeStopServicesWorkflow.State)
        }

        public init(step: Step, detail: Detail? = nil) {
            self.step = step
            self.detail = detail
        }
    }

    public typealias Result = State
    public typealias Options = Void

    /// Stream the stop all workflow.
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
        // Stop Lambda first
        continuation.yield(State(step: .stoppingLambda))
        let lambdaWorkflow = XcodeStopLambdaWorkflow(service: service)
        for try await lambdaState in lambdaWorkflow.stream() {
            continuation.yield(State(
                step: .stoppingLambda,
                detail: .lambdaState(lambdaState)
            ))
        }

        // Then stop services
        continuation.yield(State(step: .stoppingServices))
        let servicesWorkflow = XcodeStopServicesWorkflow(service: service)
        for try await servicesState in servicesWorkflow.stream(options: .all) {
            continuation.yield(State(
                step: .stoppingServices,
                detail: .servicesState(servicesState)
            ))
        }

        continuation.yield(State(step: .complete))
        continuation.finish()
    }
}
