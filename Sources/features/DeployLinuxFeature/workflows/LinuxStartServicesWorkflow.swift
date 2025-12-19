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

/// Workflow for starting local services for Linux development.
/// Contains all service start logic directly, using SDK clients.
public struct LinuxStartServicesWorkflow: StreamingWorkflow {
    private let cliClient: CLIClient
    private let dockerClient: DockerClient
    private let postgresClient: PostgreSQLClient
    private let minioClient: MinIOClient
    private let dynamodbClient: DynamoDBClient

    public init(
        cliClient: CLIClient,
        dockerClient: DockerClient,
        postgresClient: PostgreSQLClient,
        minioClient: MinIOClient,
        dynamodbClient: DynamoDBClient
    ) {
        self.cliClient = cliClient
        self.dockerClient = dockerClient
        self.postgresClient = postgresClient
        self.minioClient = minioClient
        self.dynamodbClient = dynamodbClient
    }

    /// Components needed for starting services.
    public struct Components: Sendable {
        public let workflow: LinuxStartServicesWorkflow
        public let postgresClient: PostgreSQLClient
        public let minioClient: MinIOClient
        public let dynamodbClient: DynamoDBClient
    }

    /// Creates a workflow and associated components by instantiating required clients.
    /// - Parameter workingDirectory: The working directory for the workflow
    /// - Returns: Components containing the workflow and clients
    public static func create(workingDirectory: String) -> Components {
        let cliClient = CLIClient(defaultWorkingDirectory: workingDirectory)
        let dockerClient = DockerClient(cliClient: cliClient)
        let storageService = LocalStorageService()
        let config = LinuxContainerConfig.default(workingDirectory: workingDirectory)

        let postgresClient = PostgreSQLClient(
            dockerClient: dockerClient,
            config: .linux,
            dataDirectory: storageService.dataDirectory(for: PostgreSQLLinuxStorageKey.self)
        )
        let minioClient = MinIOClient(
            dockerClient: dockerClient,
            networkName: config.networkName,
            config: .linux,
            dataDirectory: storageService.dataDirectory(for: MinIOLinuxStorageKey.self)
        )
        let dynamodbClient = DynamoDBClient(
            dockerClient: dockerClient,
            config: .linux,
            dataDirectory: storageService.dataDirectory(for: DynamoDBLocalLinuxStorageKey.self)
        )

        let workflow = LinuxStartServicesWorkflow(
            cliClient: cliClient,
            dockerClient: dockerClient,
            postgresClient: postgresClient,
            minioClient: minioClient,
            dynamodbClient: dynamodbClient
        )

        return Components(
            workflow: workflow,
            postgresClient: postgresClient,
            minioClient: minioClient,
            dynamodbClient: dynamodbClient
        )
    }

    public typealias State = LinuxWorkflowState
    public typealias Result = State

    /// Options for the start services workflow.
    public struct Options: Sendable {
        public let services: Set<LocalServiceType>

        public init(services: Set<LocalServiceType>) {
            self.services = services
        }

        public static let all = Options(services: [.database, .s3, .dynamodb])

        public static func only(_ services: LocalServiceType...) -> Options {
            Options(services: Set(services))
        }
    }

    /// Stream the start services workflow.
    /// - Parameter options: Service options specifying which services to start
    /// - Returns: AsyncThrowingStream that yields LinuxWorkflowState updates
    public func stream(options: Options) -> AsyncThrowingStream<State, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    try await runWorkflow(options: options, continuation: continuation)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func runWorkflow(
        options: Options,
        continuation: AsyncThrowingStream<State, Error>.Continuation
    ) async throws {
        let startTime = Date()

        // Ensure Docker is running
        if !(await dockerClient.isDockerRunning()) {
            try await startDockerDesktop()
        }

        // Track which services were started
        var postgresState: ServiceState = .stopped
        var s3State: ServiceState = .stopped
        var dynamodbState: ServiceState = .stopped

        // Start PostgreSQL
        if options.services.contains(.database) {
            continuation.yield(.startingServices(LinuxWorkflowState.ServicesProgress(step: .starting, startTime: startTime, currentService: .database)))
            try await postgresClient.start()
            postgresState = .running
        }

        // Start MinIO S3
        if options.services.contains(.s3) {
            continuation.yield(.startingServices(LinuxWorkflowState.ServicesProgress(step: .starting, startTime: startTime, currentService: .s3)))
            try await minioClient.start()
            s3State = .running

            // Create bucket after S3 is running
            try await minioClient.createBucket(bucketName: nil)
        }

        // Start DynamoDB Local
        if options.services.contains(.dynamodb) {
            continuation.yield(.startingServices(LinuxWorkflowState.ServicesProgress(step: .starting, startTime: startTime, currentService: .dynamodb)))
            try await dynamodbClient.start()
            dynamodbState = .running
        }

        // Build final snapshot
        let snapshot = LinuxSnapshot(
            serviceStatus: DeploymentStatus(
                lambdaState: .stopped,
                s3State: s3State,
                postgresState: postgresState,
                dynamodbState: dynamodbState
            ),
            buildStatus: .notBuilt
        )
        continuation.yield(.completed(snapshot))
        continuation.finish()
    }

    /// Start Docker Desktop application and wait for daemon to be ready
    private func startDockerDesktop() async throws {
        let result = try await cliClient.executeForResult(
            Open(application: "Docker"),
            printCommand: false
        )

        guard result.isSuccess else {
            throw DeployError.commandFailed(
                command: "open -a Docker",
                exitCode: result.exitCode,
                output: "Failed to start Docker Desktop. Is it installed?"
            )
        }

        let maxAttempts = 60
        for _ in 1...maxAttempts {
            if await dockerClient.isDockerRunning() {
                return
            }
            try await Task.sleep(for: .seconds(1))
        }

        throw DeployError.commandFailed(
            command: "docker",
            exitCode: 1,
            output: "Docker Desktop started but daemon did not become ready within 60 seconds."
        )
    }
}
