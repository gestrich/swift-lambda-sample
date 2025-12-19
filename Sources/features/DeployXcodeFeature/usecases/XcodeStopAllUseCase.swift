import Foundation
import DeployCoreService
import DeployLocalService
import Uniflow

/// Use case for stopping Lambda and all services for Xcode development.
/// Orchestrates XcodeStopLambdaUseCase and XcodeStopServicesUseCase.
public struct XcodeStopAllUseCase: StreamingUseCase {
    private let workingDirectory: String

    public init(workingDirectory: String) {
        self.workingDirectory = workingDirectory
    }

    /// Components needed for stop all operations.
    public struct Components: Sendable {
        public let useCase: XcodeStopAllUseCase
    }

    /// Creates a use case and associated components.
    /// - Parameter workingDirectory: The working directory for the use case
    /// - Returns: Components containing the use case
    public static func create(workingDirectory: String) -> Components {
        let useCase = XcodeStopAllUseCase(workingDirectory: workingDirectory)
        return Components(useCase: useCase)
    }

    public typealias State = XcodeUseCaseState
    public typealias Result = State
    public typealias Options = Void

    /// Stream the stop all use case.
    /// - Returns: AsyncThrowingStream that yields State updates
    public func stream(options: Void) -> AsyncThrowingStream<State, Error> {
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
        let startTime = Date()

        // Stop Lambda first
        continuation.yield(.stoppingLambda(XcodeUseCaseState.LambdaProgress(
            step: .stopping,
            startTime: startTime
        )))
        let lambdaComponents = XcodeStopLambdaUseCase.create()
        for try await lambdaState in lambdaComponents.useCase.stream() {
            // Pass through non-completed states (sub-use case now yields XcodeUseCaseState)
            if case .completed = lambdaState {
                // Skip sub-use case's completed state; we'll emit our own
            } else {
                continuation.yield(lambdaState)
            }
        }

        // Then stop services
        continuation.yield(.stoppingServices(XcodeUseCaseState.ServicesProgress(
            step: .stopping,
            startTime: startTime
        )))
        let servicesComponents = XcodeStopServicesUseCase.create(workingDirectory: workingDirectory)
        for try await servicesState in servicesComponents.useCase.stream(options: .all) {
            // Pass through non-completed states
            if case .completed = servicesState {
                // Skip sub-use case's completed state; we'll emit our own
            } else {
                continuation.yield(servicesState)
            }
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
}
