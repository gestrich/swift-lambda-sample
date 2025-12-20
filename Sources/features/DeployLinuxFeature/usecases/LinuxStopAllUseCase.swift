import Foundation
import CLISDK
import DeployCoreService
import DeployLocalService
import LocalServicesFeature
import Uniflow

/// Use case for stopping Lambda and all services for Linux development.
/// Orchestrates LinuxStopLambdaUseCase and StopServicesUseCase (from LocalServicesFeature).
public struct LinuxStopAllUseCase: StreamingUseCase {
    private let workingDirectory: String

    public init(workingDirectory: String) {
        self.workingDirectory = workingDirectory
    }

    /// Components needed for stop all operations.
    public struct Components: Sendable {
        public let useCase: LinuxStopAllUseCase
    }

    /// Creates a use case and associated components.
    /// - Parameter workingDirectory: The working directory for the use case
    /// - Returns: Components containing the use case
    public static func create(workingDirectory: String) -> Components {
        let useCase = LinuxStopAllUseCase(workingDirectory: workingDirectory)
        return Components(useCase: useCase)
    }

    public typealias State = LinuxUseCaseState
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

        // Stop Lambda container first
        continuation.yield(.stoppingLambda(LinuxUseCaseState.LambdaProgress(
            step: .stopping,
            startTime: startTime
        )))
        let lambdaComponents = LinuxStopLambdaUseCase.create(workingDirectory: workingDirectory)
        for try await lambdaState in lambdaComponents.useCase.stream() {
            // Sub-use case now yields LinuxUseCaseState, forward relevant states
            switch lambdaState {
            case .stoppingLambda(let progress):
                continuation.yield(.stoppingLambda(LinuxUseCaseState.LambdaProgress(
                    step: progress.step,
                    startTime: startTime
                )))
            case .completed:
                break
            default:
                break
            }
        }

        // Then stop services using unified StopServicesUseCase
        continuation.yield(.stoppingServices(LinuxUseCaseState.ServicesProgress(
            step: .stopping,
            startTime: startTime
        )))
        let servicesComponents = StopServicesUseCase.create(
            workingDirectory: workingDirectory,
            configuration: .linux
        )
        for try await servicesState in servicesComponents.useCase.stream(options: .all) {
            // Map LocalServicesUseCaseState to LinuxUseCaseState
            switch servicesState {
            case .stopping(let progress):
                continuation.yield(.stoppingServices(LinuxUseCaseState.ServicesProgress(
                    step: mapServicesStep(progress.step),
                    startTime: startTime,
                    currentService: progress.currentService
                )))
            case .starting, .checkingStatus:
                break
            case .completed:
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

    private func mapServicesStep(_ step: LocalServicesUseCaseState.ServicesProgress.Step) -> LinuxUseCaseState.ServicesProgress.Step {
        switch step {
        case .starting: return .starting
        case .stopping: return .stopping
        case .creatingBucket: return .creatingBucket
        }
    }
}
