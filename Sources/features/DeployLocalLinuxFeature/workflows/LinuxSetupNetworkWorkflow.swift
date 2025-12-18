import Foundation
import CLISDK
import DeployLocalService
import DockerCLISDK
import DynamoDBSDK
import MinioSDK
import PostgreSQLSDK
import StorageService
import Uniflow

/// Workflow for setting up Docker network for container communication.
/// Contains all network setup logic directly, using SDK clients.
public struct LinuxSetupNetworkWorkflow: StreamingWorkflow {
    private let dockerClient: DockerClient
    private let config: LinuxContainerConfig
    private let postgresContainerName: String
    private let minioContainerName: String
    private let dynamodbContainerName: String

    public init(
        dockerClient: DockerClient,
        config: LinuxContainerConfig,
        postgresContainerName: String,
        minioContainerName: String,
        dynamodbContainerName: String
    ) {
        self.dockerClient = dockerClient
        self.config = config
        self.postgresContainerName = postgresContainerName
        self.minioContainerName = minioContainerName
        self.dynamodbContainerName = dynamodbContainerName
    }

    /// Components needed for network setup.
    public struct Components: Sendable {
        public let workflow: LinuxSetupNetworkWorkflow
    }

    /// Creates a workflow and associated components by instantiating required clients.
    /// - Parameter workingDirectory: The working directory for the workflow
    /// - Returns: Components containing the workflow
    public static func create(workingDirectory: String) -> Components {
        let cliClient = CLIClient(defaultWorkingDirectory: workingDirectory)
        let dockerClient = DockerClient(cliClient: cliClient)
        let config = LinuxContainerConfig.default(workingDirectory: workingDirectory)

        let workflow = LinuxSetupNetworkWorkflow(
            dockerClient: dockerClient,
            config: config,
            postgresContainerName: PostgreSQLConfig.linux.containerName,
            minioContainerName: MinIOConfig.linux.containerName,
            dynamodbContainerName: DynamoDBLocalConfig.linux.containerName
        )

        return Components(workflow: workflow)
    }

    /// State updates from the setup network workflow.
    public struct State: Sendable {
        public let step: Step
        public let detail: Detail?

        public enum Step: Sendable, Equatable {
            case creatingNetwork
            case connectingContainers
            case complete
        }

        public enum Detail: Sendable {
            case output(String)
            case networkCreated(String)
            case containerConnected(String)
            case containerSkipped(String, reason: String)
        }

        public init(step: Step, detail: Detail? = nil) {
            self.step = step
            self.detail = detail
        }
    }

    public typealias Result = State
    public typealias Options = Void

    /// Stream the setup network workflow.
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
        continuation.yield(State(step: .creatingNetwork))

        // Create network if it doesn't exist
        if !(try await dockerClient.networkExists(name: config.networkName)) {
            try await dockerClient.createNetwork(name: config.networkName)
            continuation.yield(State(step: .creatingNetwork, detail: .networkCreated(config.networkName)))
        } else {
            continuation.yield(State(step: .creatingNetwork, detail: .output("Network \(config.networkName) already exists")))
        }

        continuation.yield(State(step: .connectingContainers))

        // Connect PostgreSQL container
        try await connectContainerToNetwork(
            container: postgresContainerName,
            continuation: continuation
        )

        // Connect MinIO container
        try await connectContainerToNetwork(
            container: minioContainerName,
            continuation: continuation
        )

        // Connect DynamoDB container
        try await connectContainerToNetwork(
            container: dynamodbContainerName,
            continuation: continuation
        )

        continuation.yield(State(step: .complete))
        continuation.finish()
    }

    private func connectContainerToNetwork(
        container: String,
        continuation: AsyncThrowingStream<State, Error>.Continuation
    ) async throws {
        try await Task.sleep(for: .seconds(1))

        let isConnected = try await dockerClient.isConnectedToNetwork(
            container: container,
            network: config.networkName
        )

        if !isConnected {
            let isRunning = try await dockerClient.containerIsRunning(name: container)

            if isRunning {
                try await dockerClient.connectToNetwork(container: container, network: config.networkName)
                continuation.yield(State(step: .connectingContainers, detail: .containerConnected(container)))
            } else {
                continuation.yield(State(step: .connectingContainers, detail: .containerSkipped(container, reason: "not running")))
            }
        } else {
            continuation.yield(State(step: .connectingContainers, detail: .output("\(container) already connected")))
        }
    }
}
