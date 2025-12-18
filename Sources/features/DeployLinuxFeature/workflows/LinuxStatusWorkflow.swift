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

/// Workflow for checking the status of local development services (Linux mode).
/// Contains all status logic directly, using SDK clients.
public struct LinuxStatusWorkflow: StreamingWorkflow {
    private let dockerClient: DockerClient
    private let postgresClient: PostgreSQLClient
    private let minioClient: MinIOClient
    private let dynamodbClient: DynamoDBClient
    private let config: LinuxContainerConfig

    public init(
        dockerClient: DockerClient,
        postgresClient: PostgreSQLClient,
        minioClient: MinIOClient,
        dynamodbClient: DynamoDBClient,
        config: LinuxContainerConfig
    ) {
        self.dockerClient = dockerClient
        self.postgresClient = postgresClient
        self.minioClient = minioClient
        self.dynamodbClient = dynamodbClient
        self.config = config
    }

    /// Components needed for status checking operations.
    public struct Components: Sendable {
        public let workflow: LinuxStatusWorkflow
    }

    /// Creates a workflow and associated components by instantiating required clients.
    /// - Parameter workingDirectory: The working directory for the workflow
    /// - Returns: Components containing the workflow
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

        let workflow = LinuxStatusWorkflow(
            dockerClient: dockerClient,
            postgresClient: postgresClient,
            minioClient: minioClient,
            dynamodbClient: dynamodbClient,
            config: config
        )

        return Components(workflow: workflow)
    }

    /// State updates from the status workflow.
    public struct State: Sendable {
        public let step: Step
        public let detail: Detail?

        public enum Step: Sendable, Equatable {
            case checkingLambda
            case checkingS3
            case checkingDatabase
            case checkingDynamoDB
            case complete
        }

        public enum Detail: Sendable {
            case serviceStatus(LocalServiceType, ServiceState)
            case lambdaStatus(ServiceState)
            case status(DeploymentStatus)
        }

        public init(step: Step, detail: Detail? = nil) {
            self.step = step
            self.detail = detail
        }
    }

    public typealias Result = State
    public typealias Options = Void

    /// Stream the status workflow.
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
        // Check Lambda container status
        continuation.yield(State(step: .checkingLambda))
        let lambdaRunning = try await isLambdaRunning()
        continuation.yield(State(step: .checkingLambda, detail: .lambdaStatus(lambdaRunning ? .running : .stopped)))

        // Check S3 (MinIO) status
        continuation.yield(State(step: .checkingS3))
        let s3Running = try await minioClient.isRunning()
        continuation.yield(State(step: .checkingS3, detail: .serviceStatus(.s3, s3Running ? .running : .stopped)))

        // Check PostgreSQL status
        continuation.yield(State(step: .checkingDatabase))
        let postgresRunning = try await postgresClient.isRunning()
        continuation.yield(State(step: .checkingDatabase, detail: .serviceStatus(.database, postgresRunning ? .running : .stopped)))

        // Check DynamoDB status
        continuation.yield(State(step: .checkingDynamoDB))
        let dynamodbRunning = try await dynamodbClient.isRunning()
        continuation.yield(State(step: .checkingDynamoDB, detail: .serviceStatus(.dynamodb, dynamodbRunning ? .running : .stopped)))

        // Create final status
        let status = DeploymentStatus(
            lambdaState: lambdaRunning ? .running : .stopped,
            s3State: s3Running ? .running : .stopped,
            postgresState: postgresRunning ? .running : .stopped,
            dynamodbState: dynamodbRunning ? .running : .stopped
        )

        continuation.yield(State(step: .complete, detail: .status(status)))
        continuation.finish()
    }

    // MARK: - Private Helpers

    /// Check if Lambda container is running
    private func isLambdaRunning() async throws -> Bool {
        return try await dockerClient.containerIsRunning(name: config.containerName)
    }
}
