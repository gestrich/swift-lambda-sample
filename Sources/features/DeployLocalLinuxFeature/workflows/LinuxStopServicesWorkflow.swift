import Foundation
import CLISDK
import DeployLocalService
import DockerCLISDK
import DynamoDBSDK
import MinioSDK
import PostgreSQLSDK
import StorageService
import Uniflow

/// Workflow for stopping local services for Linux development.
/// Contains all service stop logic directly, using SDK clients.
public struct LinuxStopServicesWorkflow: StreamingWorkflow {
    private let postgresClient: PostgreSQLClient
    private let minioClient: MinIOClient
    private let dynamodbClient: DynamoDBClient

    public init(
        postgresClient: PostgreSQLClient,
        minioClient: MinIOClient,
        dynamodbClient: DynamoDBClient
    ) {
        self.postgresClient = postgresClient
        self.minioClient = minioClient
        self.dynamodbClient = dynamodbClient
    }

    /// Legacy initializer for backward compatibility with LinuxStopAllWorkflow.
    /// Will be removed in Phase 9 when LinuxStopAllWorkflow is migrated.
    @available(*, deprecated, message: "Use LinuxStopServicesWorkflow.create(workingDirectory:) instead")
    public init(service: LinuxLocalDevelopmentService) {
        // This initializer creates its own clients, ignoring the service parameter.
        // The service is only used to maintain API compatibility.
        let workingDirectory = FileManager.default.currentDirectoryPath
        let cliClient = CLIClient(defaultWorkingDirectory: workingDirectory)
        let dockerClient = DockerClient(cliClient: cliClient)
        let storageService = LocalStorageService()
        let config = LinuxContainerConfig.default(workingDirectory: workingDirectory)

        self.postgresClient = PostgreSQLClient(
            dockerClient: dockerClient,
            config: .linux,
            dataDirectory: storageService.dataDirectory(for: PostgreSQLLinuxStorageKey.self)
        )
        self.minioClient = MinIOClient(
            dockerClient: dockerClient,
            networkName: config.networkName,
            config: .linux,
            dataDirectory: storageService.dataDirectory(for: MinIOLinuxStorageKey.self)
        )
        self.dynamodbClient = DynamoDBClient(
            dockerClient: dockerClient,
            config: .linux,
            dataDirectory: storageService.dataDirectory(for: DynamoDBLocalLinuxStorageKey.self)
        )
        _ = service // Silence unused parameter warning
    }

    /// Components needed for stopping services.
    public struct Components: Sendable {
        public let workflow: LinuxStopServicesWorkflow
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

        let workflow = LinuxStopServicesWorkflow(
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

    /// State updates from the stop services workflow.
    public struct State: Sendable {
        public let step: Step
        public let detail: Detail?

        public enum Step: Sendable, Equatable {
            case stoppingDatabase
            case stoppingS3
            case stoppingDynamoDB
            case complete
        }

        public enum Detail: Sendable {
            case output(String)
            case serviceStopped(LocalServiceType)
        }

        public init(step: Step, detail: Detail? = nil) {
            self.step = step
            self.detail = detail
        }
    }

    public typealias Result = State

    /// Options for the stop services workflow.
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

    /// Stream the stop services workflow.
    /// - Parameter options: Service options specifying which services to stop
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
        // Stop PostgreSQL
        if options.services.contains(.database) {
            continuation.yield(State(step: .stoppingDatabase))
            try await postgresClient.stop()
            continuation.yield(State(step: .stoppingDatabase, detail: .serviceStopped(.database)))
        }

        // Stop MinIO S3
        if options.services.contains(.s3) {
            continuation.yield(State(step: .stoppingS3))
            try await minioClient.stop()
            continuation.yield(State(step: .stoppingS3, detail: .serviceStopped(.s3)))
        }

        // Stop DynamoDB Local
        if options.services.contains(.dynamodb) {
            continuation.yield(State(step: .stoppingDynamoDB))
            try await dynamodbClient.stop()
            continuation.yield(State(step: .stoppingDynamoDB, detail: .serviceStopped(.dynamodb)))
        }

        continuation.yield(State(step: .complete))
        continuation.finish()
    }
}
