import Foundation
import DeployCoreService
import DeployLocalService
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

    public typealias State = XcodeWorkflowState
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
        let startTime = Date()

        // Start services first
        continuation.yield(.startingServices(XcodeWorkflowState.ServicesProgress(
            step: .starting,
            startTime: startTime
        )))
        let servicesComponents = XcodeStartServicesWorkflow.create(workingDirectory: workingDirectory)
        for try await servicesState in servicesComponents.workflow.stream(options: .all) {
            // Pass through non-completed states (sub-workflow now yields XcodeWorkflowState)
            if case .completed = servicesState {
                // Skip sub-workflow's completed state; we'll emit our own
            } else {
                continuation.yield(servicesState)
            }
        }

        // Start Lambda (includes build if needed and waitForReady)
        continuation.yield(.startingLambda(XcodeWorkflowState.LambdaProgress(
            step: .starting,
            startTime: startTime
        )))
        let lambdaComponents = XcodeStartLambdaWorkflow.create(workingDirectory: workingDirectory)
        for try await lambdaState in lambdaComponents.workflow.stream() {
            // Pass through non-completed states
            if case .completed = lambdaState {
                // Skip sub-workflow's completed state; we'll emit our own
            } else {
                continuation.yield(lambdaState)
            }
        }

        // Complete with snapshot
        let status = DeploymentStatus(
            lambdaState: .running,
            s3State: .running,
            postgresState: .running,
            dynamodbState: .running
        )
        let snapshot = XcodeSnapshot(
            serviceStatus: status,
            buildStatus: .available
        )
        continuation.yield(.completed(snapshot))
        continuation.finish()
    }
}
