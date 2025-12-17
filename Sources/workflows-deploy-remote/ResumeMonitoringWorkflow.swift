//
//  ResumeMonitoringWorkflow.swift
//  service-deploy
//
//  Workflow for resuming monitoring of an in-progress CloudFormation operation.
//

import Foundation
import sdk_aws
import sdk_cli
import service_deploy_remote

/// Workflow for resuming monitoring of an in-progress CloudFormation operation.
/// Used when the app starts and detects a deploy/destroy is already running.
public struct ResumeMonitoringWorkflow: Sendable {
    private let cfClient: CloudFormationClient
    private let stackName: String

    public init(
        cfClient: CloudFormationClient,
        stackName: String
    ) {
        self.cfClient = cfClient
        self.stackName = stackName
    }

    /// Run the monitoring workflow for an already in-progress operation.
    /// - Parameter initialState: The CloudFormationState detected (must be .deploying or .destroying)
    /// - Returns: AsyncThrowingStream that yields WorkflowState updates until completion
    public func run(
        initialState: CloudFormationState
    ) -> AsyncThrowingStream<WorkflowState, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    try await runWorkflow(
                        initialState: initialState,
                        continuation: continuation
                    )
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func runWorkflow(
        initialState: CloudFormationState,
        continuation: AsyncThrowingStream<WorkflowState, Error>.Continuation
    ) async throws {
        let startTime = initialState.operationStartTime ?? Date()

        // Yield initial state
        if let workflowState = makeWorkflowState(from: initialState, startTime: startTime) {
            continuation.yield(workflowState)
        }

        // Monitor until complete
        for try await cfState in cfClient.monitorStream(stackName: stackName) {
            switch cfState {
            case .deploying, .destroying:
                if let workflowState = makeWorkflowState(from: cfState, startTime: startTime) {
                    continuation.yield(workflowState)
                }

            case .deployed, .notDeployed, .failed, .credentialExpired:
                continuation.yield(.completed(DeploymentSnapshot.from(cfState)))
                continuation.finish()
                return

            case .unknown, .loading:
                continue
            }
        }

        // Stream ended without completion - query final state
        let finalState = try await cfClient.queryState(stackName: stackName)
        continuation.yield(.completed(DeploymentSnapshot.from(finalState)))
        continuation.finish()
    }

    private func makeWorkflowState(from cfState: CloudFormationState, startTime: Date) -> WorkflowState? {
        switch cfState {
        case .deploying(_, let progress, _):
            return .deploying(WorkflowState.DeployProgress(
                step: .monitoring,
                startTime: startTime,
                detail: progress
            ))

        case .destroying(let progress, _):
            return .destroying(WorkflowState.DestroyProgress(
                step: .destroying,
                startTime: startTime,
                detail: progress
            ))

        default:
            return nil
        }
    }
}
