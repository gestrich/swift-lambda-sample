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

/// Workflow for starting local services for Xcode development.
/// Contains all service start logic directly, using SDK clients.
public struct XcodeStartServicesWorkflow: StreamingWorkflow {
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

    /// Backward-compatible initializer for XcodeStartAllWorkflow.
    /// - Parameter service: The Xcode local development service (ignored, clients created internally)
    @available(*, deprecated, message: "Use XcodeStartServicesWorkflow.create() instead")
    public init(service: XcodeLocalDevelopmentService) {
        let workingDirectory = FileManager.default.currentDirectoryPath
        let components = Self.create(workingDirectory: workingDirectory)
        self.cliClient = components.cliClient
        self.dockerClient = components.dockerClient
        self.postgresClient = components.postgresClient
        self.minioClient = components.minioClient
        self.dynamodbClient = components.dynamodbClient
    }

    /// Components needed for starting services.
    public struct Components: Sendable {
        public let workflow: XcodeStartServicesWorkflow
        public let cliClient: CLIClient
        public let dockerClient: DockerClient
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

        let postgresClient = PostgreSQLClient(
            dockerClient: dockerClient,
            config: .xcode,
            dataDirectory: storageService.dataDirectory(for: PostgreSQLXcodeStorageKey.self)
        )
        let minioClient = MinIOClient(
            dockerClient: dockerClient,
            networkName: "lambda-xcode",
            config: .xcode,
            dataDirectory: storageService.dataDirectory(for: MinIOXcodeStorageKey.self)
        )
        let dynamodbClient = DynamoDBClient(
            dockerClient: dockerClient,
            config: .xcode,
            dataDirectory: storageService.dataDirectory(for: DynamoDBLocalXcodeStorageKey.self)
        )

        let workflow = XcodeStartServicesWorkflow(
            cliClient: cliClient,
            dockerClient: dockerClient,
            postgresClient: postgresClient,
            minioClient: minioClient,
            dynamodbClient: dynamodbClient
        )

        return Components(
            workflow: workflow,
            cliClient: cliClient,
            dockerClient: dockerClient,
            postgresClient: postgresClient,
            minioClient: minioClient,
            dynamodbClient: dynamodbClient
        )
    }

    /// State updates from the start services workflow.
    public struct State: Sendable {
        public let step: Step
        public let detail: Detail?

        public enum Step: Sendable, Equatable {
            case startingDatabase
            case startingS3
            case creatingBucket
            case startingDynamoDB
            case complete
        }

        public enum Detail: Sendable {
            case output(String)
            case serviceStarted(LocalServiceType)
        }

        public init(step: Step, detail: Detail? = nil) {
            self.step = step
            self.detail = detail
        }
    }

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
    /// - Returns: AsyncThrowingStream that yields State updates
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
        // Ensure Docker is running
        if !(await dockerClient.isDockerRunning()) {
            try await startDockerDesktop()
        }

        // Start PostgreSQL
        if options.services.contains(.database) {
            continuation.yield(State(step: .startingDatabase))
            try await postgresClient.start()
            continuation.yield(State(step: .startingDatabase, detail: .serviceStarted(.database)))
        }

        // Start MinIO S3
        if options.services.contains(.s3) {
            continuation.yield(State(step: .startingS3))
            try await minioClient.start()
            continuation.yield(State(step: .startingS3, detail: .serviceStarted(.s3)))

            // Create bucket after S3 is running
            continuation.yield(State(step: .creatingBucket))
            try await minioClient.createBucket(bucketName: nil)
        }

        // Start DynamoDB Local
        if options.services.contains(.dynamodb) {
            continuation.yield(State(step: .startingDynamoDB))
            try await dynamodbClient.start()
            continuation.yield(State(step: .startingDynamoDB, detail: .serviceStarted(.dynamodb)))
        }

        continuation.yield(State(step: .complete))
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
