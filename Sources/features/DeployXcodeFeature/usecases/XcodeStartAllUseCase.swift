import Foundation
import DeployCoreService
import DeployLocalService
import Uniflow

/// Use case for starting Lambda with all services for Xcode development.
/// Orchestrates XcodeStartServicesUseCase and XcodeStartLambdaUseCase.
public struct XcodeStartAllUseCase: StreamingUseCase {
    private let workingDirectory: String
    private let lambdaHostPort = 8080

    public init(workingDirectory: String) {
        self.workingDirectory = workingDirectory
    }

    /// Components needed for start all operations.
    public struct Components: Sendable {
        public let useCase: XcodeStartAllUseCase
        public let port: Int
    }

    /// Creates a use case and associated components.
    /// - Parameter workingDirectory: The working directory for the use case
    /// - Returns: Components containing the use case and configuration
    public static func create(workingDirectory: String) -> Components {
        let useCase = XcodeStartAllUseCase(workingDirectory: workingDirectory)
        return Components(useCase: useCase, port: 8080)
    }

    public typealias State = XcodeUseCaseState
    public typealias Result = State
    public typealias Options = Void

    /// Stream the start all use case.
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

        // Start services first
        continuation.yield(.startingServices(XcodeUseCaseState.ServicesProgress(
            step: .starting,
            startTime: startTime
        )))
        let servicesComponents = XcodeStartServicesUseCase.create(workingDirectory: workingDirectory)
        for try await servicesState in servicesComponents.useCase.stream(options: .all) {
            // Pass through non-completed states (sub-use case now yields XcodeUseCaseState)
            if case .completed = servicesState {
                // Skip sub-use case's completed state; we'll emit our own
            } else {
                continuation.yield(servicesState)
            }
        }

        // Start Lambda (includes build if needed and waitForReady)
        continuation.yield(.startingLambda(XcodeUseCaseState.LambdaProgress(
            step: .starting,
            startTime: startTime
        )))
        let lambdaComponents = XcodeStartLambdaUseCase.create(workingDirectory: workingDirectory)
        for try await lambdaState in lambdaComponents.useCase.stream() {
            // Pass through non-completed states
            if case .completed = lambdaState {
                // Skip sub-use case's completed state; we'll emit our own
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
