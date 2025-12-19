import Foundation
import DeployCoreService
import DeployLocalService
import Uniflow

/// Workflow for stopping Lambda and all services for Xcode development.
/// Orchestrates XcodeStopLambdaWorkflow and XcodeStopServicesWorkflow.
public struct XcodeStopAllWorkflow: StreamingWorkflow {
    private let workingDirectory: String

    public init(workingDirectory: String) {
        self.workingDirectory = workingDirectory
    }

    /// Components needed for stop all operations.
    public struct Components: Sendable {
        public let workflow: XcodeStopAllWorkflow
    }

    /// Creates a workflow and associated components.
    /// - Parameter workingDirectory: The working directory for the workflow
    /// - Returns: Components containing the workflow
    public static func create(workingDirectory: String) -> Components {
        let workflow = XcodeStopAllWorkflow(workingDirectory: workingDirectory)
        return Components(workflow: workflow)
    }

    public typealias State = XcodeWorkflowState
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

        // Stop Lambda first
        continuation.yield(.stoppingLambda(XcodeWorkflowState.LambdaProgress(
            step: .stopping,
            startTime: startTime
        )))
        let lambdaComponents = XcodeStopLambdaWorkflow.create()
        for try await lambdaState in lambdaComponents.workflow.stream() {
            let mappedState = mapLambdaState(lambdaState, startTime: startTime)
            continuation.yield(mappedState)
        }

        // Then stop services
        continuation.yield(.stoppingServices(XcodeWorkflowState.ServicesProgress(
            step: .stopping,
            startTime: startTime
        )))
        let servicesComponents = XcodeStopServicesWorkflow.create(workingDirectory: workingDirectory)
        for try await servicesState in servicesComponents.workflow.stream(options: .all) {
            let mappedState = mapServicesState(servicesState, startTime: startTime)
            continuation.yield(mappedState)
        }

        // Complete with snapshot
        let status = DeploymentStatus(
            lambdaState: .stopped,
            s3State: .stopped,
            postgresState: .stopped,
            dynamodbState: .stopped
        )
        let snapshot = XcodeSnapshot(
            serviceStatus: status,
            buildStatus: .notBuilt
        )
        continuation.yield(.completed(snapshot))
        continuation.finish()
    }

    // MARK: - State Mapping Helpers

    private func mapLambdaState(
        _ state: XcodeStopLambdaWorkflow.State,
        startTime: Date
    ) -> XcodeWorkflowState {
        .stoppingLambda(XcodeWorkflowState.LambdaProgress(
            step: .stopping,
            startTime: startTime
        ))
    }

    private func mapServicesState(
        _ state: XcodeStopServicesWorkflow.State,
        startTime: Date
    ) -> XcodeWorkflowState {
        let currentService: LocalServiceType?
        switch state.step {
        case .stoppingDatabase:
            currentService = .database
        case .stoppingS3:
            currentService = .s3
        case .stoppingDynamoDB:
            currentService = .dynamodb
        case .complete:
            currentService = nil
        }

        return .stoppingServices(XcodeWorkflowState.ServicesProgress(
            step: .stopping,
            startTime: startTime,
            currentService: currentService
        ))
    }
}
