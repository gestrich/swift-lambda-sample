//
//  RefreshWorkflow.swift
//  service-deploy
//
//  Workflow for refreshing deployment state from AWS.
//  Queries CloudFormation and monitors any in-progress operations to completion.
//

import Foundation
import AWSSDK
import Uniflow

/// Workflow for refreshing deployment state from AWS.
/// Queries CloudFormation and delegates to ResumeMonitoringWorkflow if an operation is in progress.
public struct RefreshWorkflow: StreamingWorkflow {
    public typealias Options = Void
    public typealias State = WorkflowState
    public typealias Result = State

    private let cfClient: CloudFormationClient
    private let stackName: String

    public init(
        cfClient: CloudFormationClient,
        stackName: String
    ) {
        self.cfClient = cfClient
        self.stackName = stackName
    }

    /// Stream the refresh workflow, yielding state updates during execution.
    /// For stable states (deployed, notDeployed, failed), yields completed immediately.
    /// For in-progress operations (deploying, destroying), delegates to ResumeMonitoringWorkflow.
    public func stream(options: Options) -> AsyncThrowingStream<State, Error> {
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
        let cfState = try await cfClient.queryState(stackName: stackName)

        switch cfState {
        case .deploying, .destroying:
            let monitorWorkflow = ResumeMonitoringWorkflow(
                cfClient: cfClient,
                stackName: stackName
            )
            for try await state in monitorWorkflow.run(initialState: cfState) {
                continuation.yield(state)
            }
            continuation.finish()

        default:
            let snapshot = DeploymentSnapshot.from(cfState)
            continuation.yield(.completed(snapshot))
            continuation.finish()
        }
    }
}
