import Foundation
import CLISDK
import DeployCoreService
import DeployLocalService
import Uniflow

/// Workflow for stopping Lambda and all services for Linux development.
/// Orchestrates LinuxStopLambdaWorkflow and LinuxStopServicesWorkflow.
public struct LinuxStopAllWorkflow: StreamingUseCase {
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

    public typealias State = LinuxWorkflowState
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
        let startTime = Date()

        // Stop Lambda container first
        continuation.yield(.stoppingLambda(LinuxWorkflowState.LambdaProgress(
            step: .stopping,
            startTime: startTime
        )))
        let lambdaComponents = LinuxStopLambdaWorkflow.create(workingDirectory: workingDirectory)
        for try await lambdaState in lambdaComponents.workflow.stream() {
            // Sub-workflow now yields LinuxWorkflowState, forward relevant states
            switch lambdaState {
            case .stoppingLambda(let progress):
                continuation.yield(.stoppingLambda(LinuxWorkflowState.LambdaProgress(
                    step: progress.step,
                    startTime: startTime
                )))
            case .completed:
                break
            default:
                break
            }
        }

        // Then stop services
        continuation.yield(.stoppingServices(LinuxWorkflowState.ServicesProgress(
            step: .stopping,
            startTime: startTime
        )))
        let servicesComponents = LinuxStopServicesWorkflow.create(workingDirectory: workingDirectory)
        for try await servicesState in servicesComponents.workflow.stream(options: .all) {
            // Sub-workflow now yields LinuxWorkflowState, forward relevant states
            switch servicesState {
            case .stoppingServices(let progress):
                continuation.yield(.stoppingServices(LinuxWorkflowState.ServicesProgress(
                    step: .stopping,
                    startTime: startTime,
                    currentService: progress.currentService
                )))
            case .completed:
                break
            default:
                break
            }
        }

        // Complete with snapshot (all stopped)
        let status = DeploymentStatus(
            lambdaState: .stopped,
            s3State: .stopped,
            postgresState: .stopped,
            dynamodbState: .stopped
        )
        let snapshot = LinuxSnapshot(
            serviceStatus: status,
            buildStatus: .available
        )
        continuation.yield(.completed(snapshot))
        continuation.finish()
    }
}
