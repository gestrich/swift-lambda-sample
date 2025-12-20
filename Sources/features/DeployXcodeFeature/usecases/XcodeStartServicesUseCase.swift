import Foundation
import DeployCoreService
import DeployLocalService
import LocalServicesFeature
import Uniflow

/// Backwards-compatible wrapper for XcodeStartServicesUseCase.
/// This use case has been unified into StartServicesUseCase in LocalServicesFeature.
/// Use StartServicesUseCase.create(workingDirectory:configuration:) with .xcode configuration instead.
/// This wrapper will be removed in Phase 5 when CLI commands are updated.
public struct XcodeStartServicesUseCase: StreamingUseCase {
    private let underlyingUseCase: StartServicesUseCase

    public init(underlyingUseCase: StartServicesUseCase) {
        self.underlyingUseCase = underlyingUseCase
    }

    /// Backwards-compatible Components type.
    public struct Components: Sendable {
        public let useCase: XcodeStartServicesUseCase
    }

    /// Backwards-compatible Options type.
    public typealias Options = StartServicesUseCase.Options
    public typealias State = XcodeUseCaseState
    public typealias Result = XcodeUseCaseState

    /// Creates a use case with Xcode configuration.
    /// - Parameter workingDirectory: The working directory for the use case
    /// - Returns: Components containing the use case
    public static func create(workingDirectory: String) -> Components {
        let underlyingComponents = StartServicesUseCase.create(
            workingDirectory: workingDirectory,
            configuration: .xcode
        )
        return Components(useCase: XcodeStartServicesUseCase(underlyingUseCase: underlyingComponents.useCase))
    }

    /// Stream the start services use case, adapting LocalServicesUseCaseState to XcodeUseCaseState.
    public func stream(options: Options) -> AsyncThrowingStream<XcodeUseCaseState, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await state in underlyingUseCase.stream(options: options) {
                        let mappedState = mapToXcodeState(state)
                        continuation.yield(mappedState)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func mapToXcodeState(_ state: LocalServicesUseCaseState) -> XcodeUseCaseState {
        switch state {
        case .starting(let progress):
            return .startingServices(XcodeUseCaseState.ServicesProgress(
                step: mapStep(progress.step),
                startTime: progress.startTime,
                currentService: progress.currentService
            ))
        case .stopping(let progress):
            return .stoppingServices(XcodeUseCaseState.ServicesProgress(
                step: mapStep(progress.step),
                startTime: progress.startTime,
                currentService: progress.currentService
            ))
        case .checkingStatus(let progress):
            return .checkingStatus(XcodeUseCaseState.StatusProgress(
                step: .checkingS3,
                startTime: progress.startTime,
                serviceStatus: nil,
                lambdaStatus: nil
            ))
        case .completed(let snapshot):
            return .completed(XcodeSnapshot(
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

    private func mapStep(_ step: LocalServicesUseCaseState.ServicesProgress.Step) -> XcodeUseCaseState.ServicesProgress.Step {
        switch step {
        case .starting: return .starting
        case .stopping: return .stopping
        case .creatingBucket: return .creatingBucket
        }
    }
}
