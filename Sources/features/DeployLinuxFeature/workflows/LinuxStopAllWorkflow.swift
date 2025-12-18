import Foundation
import CLISDK
import Uniflow

/// Workflow for stopping Lambda and all services for Linux development.
/// Orchestrates LinuxStopLambdaWorkflow and LinuxStopServicesWorkflow.
public struct LinuxStopAllWorkflow: StreamingWorkflow {
    private let workingDirectory: String

    public init(workingDirectory: String) {
        self.workingDirectory = workingDirectory
    }

    /// Components needed for stop all operations.
    public struct Components: Sendable {
        public let workflow: LinuxStopAllWorkflow
    }

    /// Creates a workflow and associated components.
    /// - Parameter workingDirectory: The working directory for the workflow
    /// - Returns: Components containing the workflow
    public static func create(workingDirectory: String) -> Components {
        let workflow = LinuxStopAllWorkflow(workingDirectory: workingDirectory)
        return Components(workflow: workflow)
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
            case lambdaState(LinuxStopLambdaWorkflow.State)
            case servicesState(LinuxStopServicesWorkflow.State)
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
        // Stop Lambda container first
        continuation.yield(State(step: .stoppingLambda))
        let lambdaComponents = LinuxStopLambdaWorkflow.create(workingDirectory: workingDirectory)
        for try await lambdaState in lambdaComponents.workflow.stream() {
            continuation.yield(State(
                step: .stoppingLambda,
                detail: .lambdaState(lambdaState)
            ))
        }

        // Then stop services
        continuation.yield(State(step: .stoppingServices))
        let servicesComponents = LinuxStopServicesWorkflow.create(workingDirectory: workingDirectory)
        for try await servicesState in servicesComponents.workflow.stream(options: .all) {
            continuation.yield(State(
                step: .stoppingServices,
                detail: .servicesState(servicesState)
            ))
        }

        continuation.yield(State(step: .complete))
        continuation.finish()
    }
}
