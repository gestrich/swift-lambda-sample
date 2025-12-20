import Foundation
import DeployCoreService
import DeployLocalService
import LocalServicesFeature
import Uniflow

/// Backwards-compatible wrapper for LinuxStartServicesUseCase.
/// This use case has been unified into StartServicesUseCase in LocalServicesFeature.
/// Use StartServicesUseCase.create(workingDirectory:configuration:) with .linux configuration instead.
/// This wrapper will be removed in Phase 5 when CLI commands are updated.
public struct LinuxStartServicesUseCase: StreamingUseCase {
    private let underlyingUseCase: StartServicesUseCase

    public init(underlyingUseCase: StartServicesUseCase) {
        self.underlyingUseCase = underlyingUseCase
    }

    /// Backwards-compatible Components type.
    public struct Components: Sendable {
        public let useCase: LinuxStartServicesUseCase
    }

    /// Backwards-compatible Options type.
    public typealias Options = StartServicesUseCase.Options
    public typealias State = LinuxUseCaseState
    public typealias Result = LinuxUseCaseState

    /// Creates a use case with Linux configuration.
    /// - Parameter workingDirectory: The working directory for the use case
    /// - Returns: Components containing the use case
    public static func create(workingDirectory: String) -> Components {
        let underlyingComponents = StartServicesUseCase.create(
            workingDirectory: workingDirectory,
            configuration: .linux
        )
        return Components(useCase: LinuxStartServicesUseCase(underlyingUseCase: underlyingComponents.useCase))
    }

    /// Stream the start services use case, adapting LocalServicesUseCaseState to LinuxUseCaseState.
    public func stream(options: Options) -> AsyncThrowingStream<LinuxUseCaseState, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await state in underlyingUseCase.stream(options: options) {
                        let mappedState = mapToLinuxState(state)
                        continuation.yield(mappedState)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func mapToLinuxState(_ state: LocalServicesUseCaseState) -> LinuxUseCaseState {
        switch state {
        case .starting(let progress):
            return .startingServices(LinuxUseCaseState.ServicesProgress(
                step: mapStep(progress.step),
                startTime: progress.startTime,
                currentService: progress.currentService
            ))
        case .stopping(let progress):
            return .stoppingServices(LinuxUseCaseState.ServicesProgress(
                step: mapStep(progress.step),
                startTime: progress.startTime,
                currentService: progress.currentService
            ))
        case .checkingStatus(let progress):
            return .checkingStatus(LinuxUseCaseState.StatusProgress(
                step: .checkingS3,
                startTime: progress.startTime,
                serviceStatus: nil,
                lambdaStatus: nil
            ))
        case .completed(let snapshot):
            return .completed(LinuxSnapshot(
                serviceStatus: DeploymentStatus(
                    lambdaState: .stopped,
                    s3State: snapshot.s3State,
                    postgresState: snapshot.postgresState,
                    dynamodbState: snapshot.dynamodbState
                ),
                buildStatus: .notBuilt
            ))
        }
    }

    private func mapStep(_ step: LocalServicesUseCaseState.ServicesProgress.Step) -> LinuxUseCaseState.ServicesProgress.Step {
        switch step {
        case .starting: return .starting
        case .stopping: return .stopping
        case .creatingBucket: return .creatingBucket
        }
    }
}
