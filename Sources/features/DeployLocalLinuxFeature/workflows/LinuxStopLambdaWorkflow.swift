import Foundation
import CLISDK
import DockerCLISDK
import Uniflow

/// Workflow for stopping the Lambda container.
/// Contains all stop logic directly, using SDK clients.
public struct LinuxStopLambdaWorkflow: StreamingWorkflow {
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

    /// Backward compatibility initializer for LinuxStopAllWorkflow.
    /// - Parameter service: The service (ignored - creates own clients)
    @available(*, deprecated, message: "Use LinuxStopLambdaWorkflow.create() instead")
    public init(service: LinuxLocalDevelopmentService) {
        let workingDirectory = FileManager.default.currentDirectoryPath
        let components = Self.create(workingDirectory: workingDirectory)
        self = components.workflow
    }

    /// State updates from the stop Lambda workflow.
    public struct State: Sendable {
        public let step: Step
        public let detail: Detail?

        public enum Step: Sendable, Equatable {
            case checking
            case stopping
            case complete
        }

        public enum Detail: Sendable {
            case output(String)
            case wasRunning(Bool)
        }

        public init(step: Step, detail: Detail? = nil) {
            self.step = step
            self.detail = detail
        }
    }

    public typealias Result = State
    public typealias Options = Void

    /// Stream the stop Lambda workflow.
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
        // Check if Lambda container is running
        continuation.yield(State(step: .checking))
        let wasRunning = try await isRunning()

        // Stop Lambda container
        continuation.yield(State(step: .stopping))
        try await stopLambda(continuation: continuation)

        continuation.yield(State(step: .complete, detail: .wasRunning(wasRunning)))
        continuation.finish()
    }

    // MARK: - Private Helpers

    /// Check if Lambda container is running
    private func isRunning() async throws -> Bool {
        return try await dockerClient.containerIsRunning(name: config.containerName)
    }

    /// Stop Lambda container
    private func stopLambda(
        continuation: AsyncThrowingStream<State, Error>.Continuation
    ) async throws {
        do {
            try await dockerClient.stop(container: config.containerName)
            continuation.yield(State(step: .stopping, detail: .output("Lambda stopped")))
        } catch {
            continuation.yield(State(step: .stopping, detail: .output("Container may already be stopped")))
        }
    }
}
