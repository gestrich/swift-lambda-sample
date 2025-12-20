import Foundation
import DeployCoreService
import DeployLocalService
import LocalServicesFeature
import Uniflow

/// Use case for starting Lambda with all services for Xcode development.
/// Orchestrates StartServicesUseCase (from LocalServicesFeature) and XcodeStartLambdaUseCase.
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

        // Start services first using unified StartServicesUseCase
        continuation.yield(.startingServices(XcodeUseCaseState.ServicesProgress(
            step: .starting,
            startTime: startTime
        )))
        let servicesComponents = StartServicesUseCase.create(
            workingDirectory: workingDirectory,
            configuration: .xcode
        )
        for try await servicesState in servicesComponents.useCase.stream(options: .all) {
            // Map LocalServicesUseCaseState to XcodeUseCaseState
            switch servicesState {
            case .starting(let progress):
                continuation.yield(.startingServices(XcodeUseCaseState.ServicesProgress(
                    step: mapServicesStep(progress.step),
                    startTime: startTime,
                    currentService: progress.currentService
                )))
            case .stopping, .checkingStatus:
                break
            case .completed:
                break
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

    private func mapServicesStep(_ step: LocalServicesUseCaseState.ServicesProgress.Step) -> XcodeUseCaseState.ServicesProgress.Step {
        switch step {
        case .starting: return .starting
        case .stopping: return .stopping
        case .creatingBucket: return .creatingBucket
        }
    }
}
