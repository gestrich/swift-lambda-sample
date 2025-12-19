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
            let mappedState = mapServicesState(servicesState, startTime: startTime)
            continuation.yield(mappedState)
        }

        // Start Lambda (includes build if needed and waitForReady)
        continuation.yield(.startingLambda(XcodeWorkflowState.LambdaProgress(
            step: .starting,
            startTime: startTime
        )))
        let lambdaComponents = XcodeStartLambdaWorkflow.create(workingDirectory: workingDirectory)
        for try await lambdaState in lambdaComponents.workflow.stream() {
            let mappedState = mapLambdaState(lambdaState, startTime: startTime)
            continuation.yield(mappedState)
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

    // MARK: - State Mapping Helpers

    private func mapServicesState(
        _ state: XcodeStartServicesWorkflow.State,
        startTime: Date
    ) -> XcodeWorkflowState {
        let currentService: LocalServiceType?
        switch state.step {
        case .startingDatabase:
            currentService = .database
        case .startingS3, .creatingBucket:
            currentService = .s3
        case .startingDynamoDB:
            currentService = .dynamodb
        case .complete:
            currentService = nil
        }

        let step: XcodeWorkflowState.ServicesProgress.Step
        if case .creatingBucket = state.step {
            step = .creatingBucket
        } else {
            step = .starting
        }

        return .startingServices(XcodeWorkflowState.ServicesProgress(
            step: step,
            startTime: startTime,
            currentService: currentService
        ))
    }

    private func mapLambdaState(
        _ state: XcodeStartLambdaWorkflow.State,
        startTime: Date
    ) -> XcodeWorkflowState {
        let step: XcodeWorkflowState.LambdaProgress.Step
        switch state.step {
        case .checkingBuild:
            step = .checkingBuild
        case .building:
            step = .building
        case .starting:
            step = .starting
        case .waitingForReady:
            step = .waitingForReady
        case .complete:
            step = .starting
        }

        return .startingLambda(XcodeWorkflowState.LambdaProgress(
            step: step,
            startTime: startTime
        ))
    }
}
