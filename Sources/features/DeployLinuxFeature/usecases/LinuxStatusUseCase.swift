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

/// Use case for checking the status of local development services (Linux mode).
/// Contains all status logic directly, using SDK clients.
public struct LinuxStatusUseCase: StreamingUseCase {
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
        public let useCase: LinuxStatusUseCase
    }

    /// Creates a use case and associated components by instantiating required clients.
    /// - Parameter workingDirectory: The working directory for the use case
    /// - Returns: Components containing the use case
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

        let useCase = LinuxStatusUseCase(
            dockerClient: dockerClient,
            postgresClient: postgresClient,
            minioClient: minioClient,
            dynamodbClient: dynamodbClient,
            config: config
        )

        return Components(useCase: useCase)
    }

    public typealias State = LinuxUseCaseState
    public typealias Result = LinuxUseCaseState
    public typealias Options = Void

    /// Stream the status use case.
    /// - Returns: AsyncThrowingStream that yields LinuxUseCaseState updates
    public func stream(options: Void) -> AsyncThrowingStream<LinuxUseCaseState, Error> {
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
        continuation: AsyncThrowingStream<LinuxUseCaseState, Error>.Continuation
    ) async throws {
        let startTime = Date()

        // Check Lambda container status
        continuation.yield(.checkingStatus(LinuxUseCaseState.StatusProgress(
            step: .checkingLambda,
            startTime: startTime
        )))
        let lambdaRunning = try await isLambdaRunning()

        // Check S3 (MinIO) status
        continuation.yield(.checkingStatus(LinuxUseCaseState.StatusProgress(
            step: .checkingS3,
            startTime: startTime
        )))
        let s3Running = try await minioClient.isRunning()

        // Check PostgreSQL status
        continuation.yield(.checkingStatus(LinuxUseCaseState.StatusProgress(
            step: .checkingDatabase,
            startTime: startTime
        )))
        let postgresRunning = try await postgresClient.isRunning()

        // Check DynamoDB status
        continuation.yield(.checkingStatus(LinuxUseCaseState.StatusProgress(
            step: .checkingDynamoDB,
            startTime: startTime
        )))
        let dynamodbRunning = try await dynamodbClient.isRunning()

        // Create final snapshot
        let status = DeploymentStatus(
            lambdaState: lambdaRunning ? .running : .stopped,
            s3State: s3Running ? .running : .stopped,
            postgresState: postgresRunning ? .running : .stopped,
            dynamodbState: dynamodbRunning ? .running : .stopped
        )

        let snapshot = LinuxSnapshot(
            serviceStatus: status,
            buildStatus: .notBuilt
        )

        continuation.yield(.completed(snapshot))
        continuation.finish()
    }

    // MARK: - Private Helpers

    /// Check if Lambda container is running
    private func isLambdaRunning() async throws -> Bool {
        return try await dockerClient.containerIsRunning(name: config.containerName)
    }
}
