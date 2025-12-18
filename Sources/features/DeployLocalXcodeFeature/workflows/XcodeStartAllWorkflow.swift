import Foundation
import Uniflow

/// Workflow for starting Lambda with all services for Xcode development.
/// Orchestrates XcodeStartServicesWorkflow and XcodeStartLambdaWorkflow.
public struct XcodeStartAllWorkflow: StreamingWorkflow {
    private let workingDirectory: String
    private let lambdaHostPort = 8080

    public init(workingDirectory: String) {
        self.workingDirectory = workingDirectory
    }

    /// Components needed for start all operations.
    public struct Components: Sendable {
        public let workflow: XcodeStartAllWorkflow
        public let port: Int
    }

    /// Creates a workflow and associated components.
    /// - Parameter workingDirectory: The working directory for the workflow
    /// - Returns: Components containing the workflow and configuration
    public static func create(workingDirectory: String) -> Components {
        let workflow = XcodeStartAllWorkflow(workingDirectory: workingDirectory)
        return Components(workflow: workflow, port: 8080)
    }

    /// State updates from the start all workflow.
    public struct State: Sendable {
        public let step: Step
        public let detail: Detail?

        public enum Step: Sendable, Equatable {
            case startingServices
            case startingLambda
            case complete
        }

        public enum Detail: Sendable {
            case output(String)
            case servicesState(XcodeStartServicesWorkflow.State)
            case lambdaState(XcodeStartLambdaWorkflow.State)
            case port(Int)
        }

        public init(step: Step, detail: Detail? = nil) {
            self.step = step
            self.detail = detail
        }
    }

    public typealias Result = State
    public typealias Options = Void

    /// Stream the start all workflow.
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
        // Start services first
        continuation.yield(State(step: .startingServices))
        let servicesComponents = XcodeStartServicesWorkflow.create(workingDirectory: workingDirectory)
        for try await servicesState in servicesComponents.workflow.stream(options: .all) {
            continuation.yield(State(
                step: .startingServices,
                detail: .servicesState(servicesState)
            ))
        }

        // Start Lambda (includes build if needed and waitForReady)
        continuation.yield(State(step: .startingLambda))
        let lambdaComponents = XcodeStartLambdaWorkflow.create(workingDirectory: workingDirectory)
        for try await lambdaState in lambdaComponents.workflow.stream() {
            continuation.yield(State(
                step: .startingLambda,
                detail: .lambdaState(lambdaState)
            ))
        }

        // Complete with port info
        continuation.yield(State(step: .complete, detail: .port(lambdaHostPort)))
        continuation.finish()
    }
}
