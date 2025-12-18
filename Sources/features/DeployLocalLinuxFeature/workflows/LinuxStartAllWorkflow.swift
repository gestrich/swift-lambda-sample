import Foundation
import CLISDK
import DockerCLISDK
import DynamoDBSDK
import MinioSDK
import PostgreSQLSDK
import StorageService
import DeployLocalService
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

    /// State updates from the start all workflow.
    public struct State: Sendable {
        public let step: Step
        public let detail: Detail?

        public enum Step: Sendable, Equatable {
            case startingServices
            case setupNetwork
            case startingLambda
            case complete
        }

        public enum Detail: Sendable {
            case output(String)
            case servicesState(LinuxStartServicesWorkflow.State)
            case networkState(LinuxSetupNetworkWorkflow.State)
            case lambdaState(LinuxStartLambdaWorkflow.State)
            case port(Int)
        }

        public init(step: Step, detail: Detail? = nil) {
            self.step = step
            self.detail = detail
        }
    }

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
        // Start services first
        continuation.yield(State(step: .startingServices))
        let servicesComponents = LinuxStartServicesWorkflow.create(workingDirectory: workingDirectory)
        for try await servicesState in servicesComponents.workflow.stream(options: .all) {
            continuation.yield(State(
                step: .startingServices,
                detail: .servicesState(servicesState)
            ))
        }

        // Setup Docker network
        continuation.yield(State(step: .setupNetwork))
        let networkComponents = LinuxSetupNetworkWorkflow.create(workingDirectory: workingDirectory)
        for try await networkState in networkComponents.workflow.stream() {
            continuation.yield(State(
                step: .setupNetwork,
                detail: .networkState(networkState)
            ))
        }

        // Start Lambda container (includes waitForReady)
        continuation.yield(State(step: .startingLambda))
        let lambdaComponents = LinuxStartLambdaWorkflow.create(workingDirectory: workingDirectory)
        for try await lambdaState in lambdaComponents.workflow.stream() {
            continuation.yield(State(
                step: .startingLambda,
                detail: .lambdaState(lambdaState)
            ))
        }

        // Complete with port info
        let config = LinuxContainerConfig.default(workingDirectory: workingDirectory)
        continuation.yield(State(step: .complete, detail: .port(config.hostPort)))
        continuation.finish()
    }
}
