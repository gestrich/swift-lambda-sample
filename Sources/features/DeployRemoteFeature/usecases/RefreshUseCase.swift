//
//  RefreshUseCase.swift
//  service-deploy
//
//  Use case for refreshing deployment state from AWS.
//  Queries CloudFormation and monitors any in-progress operations to completion.
//

import Foundation
import AWSSDK
import Uniflow

/// Use case for refreshing deployment state from AWS.
/// Queries CloudFormation and delegates to ResumeMonitoringUseCase if an operation is in progress.
public struct RefreshUseCase: StreamingUseCase {
    public typealias Options = Void
    public typealias State = UseCaseState
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

    /// Stream the refresh use case, yielding state updates during execution.
    /// For stable states (deployed, notDeployed, failed), yields completed immediately.
    /// For in-progress operations (deploying, destroying), delegates to ResumeMonitoringUseCase.
    public func stream(options: Options) -> AsyncThrowingStream<State, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    try await runUseCase(continuation: continuation)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func runUseCase(
        continuation: AsyncThrowingStream<State, Error>.Continuation
    ) async throws {
        let cfState = try await cfClient.queryState(stackName: stackName)

        switch cfState {
        case .deploying, .destroying:
            let monitorUseCase = ResumeMonitoringUseCase(
                cfClient: cfClient,
                stackName: stackName
            )
            for try await state in monitorUseCase.run(initialState: cfState) {
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
