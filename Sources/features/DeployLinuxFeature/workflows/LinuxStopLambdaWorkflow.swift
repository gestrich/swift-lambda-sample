import Foundation
import CLISDK
import DeployCoreService
import DockerCLISDK
import Uniflow

/// Workflow for stopping the Lambda container.
/// Contains all stop logic directly, using SDK clients.
public struct LinuxStopLambdaWorkflow: StreamingUseCase {
    private let dockerClient: DockerClient
    private let config: LinuxContainerConfig

    public init(
        dockerClient: DockerClient,
        config: LinuxContainerConfig
    ) {
        self.dockerClient = dockerClient
        self.config = config
    }

    /// Components needed for Lambda stop operations.
    public struct Components: Sendable {
        public let workflow: LinuxStopLambdaWorkflow
    }

    /// Creates a workflow and associated components by instantiating required clients.
    /// - Parameter workingDirectory: The working directory
    /// - Returns: Components containing the workflow
    public static func create(workingDirectory: String) -> Components {
        let cliClient = CLIClient(defaultWorkingDirectory: workingDirectory)
        let dockerClient = DockerClient(cliClient: cliClient)
        let config = LinuxContainerConfig.default(workingDirectory: workingDirectory)

        let workflow = LinuxStopLambdaWorkflow(
            dockerClient: dockerClient,
            config: config
        )

        return Components(workflow: workflow)
    }

    public typealias State = LinuxWorkflowState
    public typealias Result = State
    public typealias Options = Void

    /// Stream the stop Lambda workflow.
    /// - Returns: AsyncThrowingStream that yields LinuxWorkflowState updates
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

        // Stop Lambda container
        continuation.yield(.stoppingLambda(LinuxWorkflowState.LambdaProgress(step: .stopping, startTime: startTime)))
        try await stopLambda()

        // Build final snapshot - Lambda is stopped, services status untracked (use stopped as default)
        let snapshot = LinuxSnapshot(
            serviceStatus: DeploymentStatus(
                lambdaState: .stopped,
                s3State: .stopped,
                postgresState: .stopped,
                dynamodbState: .stopped
            ),
            buildStatus: .notBuilt
        )
        continuation.yield(.completed(snapshot))
        continuation.finish()
    }

    // MARK: - Private Helpers

    /// Check if Lambda container is running
    private func isRunning() async throws -> Bool {
        return try await dockerClient.containerIsRunning(name: config.containerName)
    }

    /// Stop Lambda container
    private func stopLambda() async throws {
        do {
            try await dockerClient.stop(container: config.containerName)
        } catch {
            // Container may already be stopped, which is fine
        }
    }
}
