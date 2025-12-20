import Foundation
import CLISDK
import DeployCoreService
import DeployLocalService
import LocalServicesFeature
import Uniflow

/// Use case for starting Lambda with all services for Linux development.
/// Orchestrates StartServicesUseCase (from LocalServicesFeature), LinuxSetupNetworkUseCase, and LinuxStartLambdaUseCase.
public struct LinuxStartAllUseCase: StreamingUseCase {
    private let workingDirectory: String

    public init(workingDirectory: String) {
        self.workingDirectory = workingDirectory
    }

    /// Components needed for start all operations.
    public struct Components: Sendable {
        public let useCase: LinuxStartAllUseCase
        public let port: Int
    }

    /// Creates a use case and associated components.
    /// - Parameter workingDirectory: The working directory for the use case
    /// - Returns: Components containing the use case and configuration
    public static func create(workingDirectory: String) -> Components {
        let config = LinuxContainerConfig.default(workingDirectory: workingDirectory)
        let useCase = LinuxStartAllUseCase(workingDirectory: workingDirectory)
        return Components(useCase: useCase, port: config.hostPort)
    }

    public typealias State = LinuxUseCaseState
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
        continuation.yield(.startingServices(LinuxUseCaseState.ServicesProgress(
            step: .starting,
            startTime: startTime
        )))
        let servicesComponents = StartServicesUseCase.create(
            workingDirectory: workingDirectory,
            configuration: .linux
        )
        for try await servicesState in servicesComponents.useCase.stream(options: .all) {
            // Map LocalServicesUseCaseState to LinuxUseCaseState
            switch servicesState {
            case .starting(let progress):
                continuation.yield(.startingServices(LinuxUseCaseState.ServicesProgress(
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

        // Setup Docker network
        continuation.yield(.settingUpNetwork(LinuxUseCaseState.NetworkProgress(
            step: .creatingNetwork,
            startTime: startTime
        )))
        let networkComponents = LinuxSetupNetworkUseCase.create(workingDirectory: workingDirectory)
        for try await networkState in networkComponents.useCase.stream() {
            let networkStep = mapNetworkStep(networkState.step)
            let message = mapNetworkDetail(networkState.detail)
            continuation.yield(.settingUpNetwork(LinuxUseCaseState.NetworkProgress(
                step: networkStep,
                startTime: startTime,
                message: message
            )))
        }

        // Start Lambda container (includes waitForReady)
        continuation.yield(.startingLambda(LinuxUseCaseState.LambdaProgress(
            step: .starting,
            startTime: startTime
        )))
        let lambdaComponents = LinuxStartLambdaUseCase.create(workingDirectory: workingDirectory)
        for try await lambdaState in lambdaComponents.useCase.stream() {
            // Sub-use case now yields LinuxUseCaseState, forward relevant states
            switch lambdaState {
            case .startingLambda(let progress):
                continuation.yield(.startingLambda(LinuxUseCaseState.LambdaProgress(
                    step: progress.step,
                    startTime: startTime
                )))
            case .building(let progress):
                continuation.yield(.building(progress))
            case .completed:
                break
            default:
                break
            }
        }

        // Complete with snapshot
        let status = DeploymentStatus(
            lambdaState: .running,
            s3State: .running,
            postgresState: .running,
            dynamodbState: .running
        )
        let snapshot = LinuxSnapshot(
            serviceStatus: status,
            buildStatus: .available
        )
        continuation.yield(.completed(snapshot))
        continuation.finish()
    }

    // MARK: - State Mapping Helpers

    private func mapServicesStep(_ step: LocalServicesUseCaseState.ServicesProgress.Step) -> LinuxUseCaseState.ServicesProgress.Step {
        switch step {
        case .starting: return .starting
        case .stopping: return .stopping
        case .creatingBucket: return .creatingBucket
        }
    }

    private func mapNetworkStep(_ step: LinuxSetupNetworkUseCase.State.Step) -> LinuxUseCaseState.NetworkProgress.Step {
        switch step {
        case .creatingNetwork: return .creatingNetwork
        case .connectingContainers: return .connectingContainers
        case .complete: return .connectingContainers
        }
    }

    private func mapNetworkDetail(_ detail: LinuxSetupNetworkUseCase.State.Detail?) -> String? {
        switch detail {
        case .output(let msg): return msg
        case .networkCreated(let name): return "Network '\(name)' created"
        case .containerConnected(let name): return "Connected \(name)"
        case .containerSkipped(let name, let reason): return "Skipped \(name) (\(reason))"
        case nil: return nil
        }
    }
}
