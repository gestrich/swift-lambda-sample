import Foundation
import CLISDK
import DeployCoreService
import DeployLocalService
import DockerCLISDK
import DynamoDBSDK
import MinioSDK
import PostgreSQLSDK
import StorageService
import Uniflow

/// Workflow for starting Lambda with all services for Linux development.
/// Orchestrates LinuxStartServicesWorkflow, LinuxSetupNetworkWorkflow, and LinuxStartLambdaWorkflow.
public struct LinuxStartAllWorkflow: StreamingWorkflow {
    private let workingDirectory: String

    public init(workingDirectory: String) {
        self.workingDirectory = workingDirectory
    }

    /// Components needed for start all operations.
    public struct Components: Sendable {
        public let workflow: LinuxStartAllWorkflow
        public let port: Int
    }

    /// Creates a workflow and associated components.
    /// - Parameter workingDirectory: The working directory for the workflow
    /// - Returns: Components containing the workflow and configuration
    public static func create(workingDirectory: String) -> Components {
        let config = LinuxContainerConfig.default(workingDirectory: workingDirectory)
        let workflow = LinuxStartAllWorkflow(workingDirectory: workingDirectory)
        return Components(workflow: workflow, port: config.hostPort)
    }

    public typealias State = LinuxWorkflowState
    public typealias Result = State
    public typealias Options = Void

    /// Stream the start all workflow.
    /// - Returns: AsyncThrowingStream that yields State updates
    public func stream(options: Void) -> AsyncThrowingStream<State, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    try await runWorkflow(continuation: continuation)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func runWorkflow(
        continuation: AsyncThrowingStream<State, Error>.Continuation
    ) async throws {
        let startTime = Date()

        // Start services first
        continuation.yield(.startingServices(LinuxWorkflowState.ServicesProgress(
            step: .starting,
            startTime: startTime
        )))
        let servicesComponents = LinuxStartServicesWorkflow.create(workingDirectory: workingDirectory)
        for try await servicesState in servicesComponents.workflow.stream(options: .all) {
            // Sub-workflow now yields LinuxWorkflowState, forward relevant states
            switch servicesState {
            case .startingServices(let progress):
                continuation.yield(.startingServices(LinuxWorkflowState.ServicesProgress(
                    step: .starting,
                    startTime: startTime,
                    currentService: progress.currentService
                )))
            case .completed:
                break
            default:
                break
            }
        }

        // Setup Docker network
        continuation.yield(.settingUpNetwork(LinuxWorkflowState.NetworkProgress(
            step: .creatingNetwork,
            startTime: startTime
        )))
        let networkComponents = LinuxSetupNetworkWorkflow.create(workingDirectory: workingDirectory)
        for try await networkState in networkComponents.workflow.stream() {
            let networkStep = mapNetworkStep(networkState.step)
            let message = mapNetworkDetail(networkState.detail)
            continuation.yield(.settingUpNetwork(LinuxWorkflowState.NetworkProgress(
                step: networkStep,
                startTime: startTime,
                message: message
            )))
        }

        // Start Lambda container (includes waitForReady)
        continuation.yield(.startingLambda(LinuxWorkflowState.LambdaProgress(
            step: .starting,
            startTime: startTime
        )))
        let lambdaComponents = LinuxStartLambdaWorkflow.create(workingDirectory: workingDirectory)
        for try await lambdaState in lambdaComponents.workflow.stream() {
            // Sub-workflow now yields LinuxWorkflowState, forward relevant states
            switch lambdaState {
            case .startingLambda(let progress):
                continuation.yield(.startingLambda(LinuxWorkflowState.LambdaProgress(
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

    private func mapNetworkStep(_ step: LinuxSetupNetworkWorkflow.State.Step) -> LinuxWorkflowState.NetworkProgress.Step {
        switch step {
        case .creatingNetwork: return .creatingNetwork
        case .connectingContainers: return .connectingContainers
        case .complete: return .connectingContainers
        }
    }

    private func mapNetworkDetail(_ detail: LinuxSetupNetworkWorkflow.State.Detail?) -> String? {
        switch detail {
        case .output(let msg): return msg
        case .networkCreated(let name): return "Network '\(name)' created"
        case .containerConnected(let name): return "Connected \(name)"
        case .containerSkipped(let name, let reason): return "Skipped \(name) (\(reason))"
        case nil: return nil
        }
    }
}
