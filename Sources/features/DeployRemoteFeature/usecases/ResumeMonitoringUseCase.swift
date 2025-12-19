//
//  ResumeMonitoringUseCase.swift
//  service-deploy
//
//  Use case for resuming monitoring of an in-progress CloudFormation operation.
//

import Foundation
import AWSSDK
import CLISDK

/// Use case for resuming monitoring of an in-progress CloudFormation operation.
/// Used when the app starts and detects a deploy/destroy is already running.
public struct ResumeMonitoringUseCase: Sendable {
    private let cfClient: CloudFormationClient
    private let stackName: String

    public init(
        cfClient: CloudFormationClient,
        stackName: String
    ) {
        self.cfClient = cfClient
        self.stackName = stackName
    }

    /// Run the monitoring use case for an already in-progress operation.
    /// - Parameter initialState: The CloudFormationState detected (must be .deploying or .destroying)
    /// - Returns: AsyncThrowingStream that yields UseCaseState updates until completion
    public func run(
        initialState: CloudFormationState
    ) -> AsyncThrowingStream<UseCaseState, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    try await runUseCase(
                        initialState: initialState,
                        continuation: continuation
                    )
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func runUseCase(
        initialState: CloudFormationState,
        continuation: AsyncThrowingStream<UseCaseState, Error>.Continuation
    ) async throws {
        let startTime = initialState.operationStartTime ?? Date()

        // Yield initial state
        if let useCaseState = makeUseCaseState(from: initialState, startTime: startTime) {
            continuation.yield(useCaseState)
        }

        // Monitor until complete
        for try await cfState in cfClient.monitorStream(stackName: stackName) {
            switch cfState {
            case .deploying, .destroying:
                if let useCaseState = makeUseCaseState(from: cfState, startTime: startTime) {
                    continuation.yield(useCaseState)
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

    private func makeUseCaseState(from cfState: CloudFormationState, startTime: Date) -> UseCaseState? {
        switch cfState {
        case .deploying(_, let progress, _):
            return .deploying(UseCaseState.DeployProgress(
                step: .monitoring,
                startTime: startTime,
                detail: progress
            ))

        case .destroying(let progress, _):
            return .destroying(UseCaseState.DestroyProgress(
                step: .destroying,
                startTime: startTime,
                detail: progress
            ))

        default:
            return nil
        }
    }
}
