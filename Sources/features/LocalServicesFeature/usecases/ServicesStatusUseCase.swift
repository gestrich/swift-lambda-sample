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

/// Unified use case for checking local Docker services status.
/// Configuration-driven to support both Xcode and Linux workflows.
public struct ServicesStatusUseCase: StreamingUseCase {
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

    /// Components needed for checking services status.
    public struct Components: Sendable {
        public let useCase: ServicesStatusUseCase
        public let postgresClient: PostgreSQLClient
        public let minioClient: MinIOClient
        public let dynamodbClient: DynamoDBClient
    }

    /// Creates a use case and associated components using the provided configuration.
    /// - Parameters:
    ///   - workingDirectory: The working directory for the use case
    ///   - configuration: The services configuration (`.xcode` or `.linux`)
    /// - Returns: Components containing the use case and clients
    public static func create(
        workingDirectory: String,
        configuration: LocalServicesConfiguration
    ) -> Components {
        let cliClient = CLIClient(defaultWorkingDirectory: workingDirectory)
        let dockerClient = DockerClient(cliClient: cliClient)
        let storageService = LocalStorageService()

        let postgresClient = PostgreSQLClient(
            dockerClient: dockerClient,
            config: configuration.postgresConfig,
            dataDirectory: storageService.dataDirectory(for: configuration.postgresStorageKey)
        )
        let minioClient = MinIOClient(
            dockerClient: dockerClient,
            networkName: configuration.networkName,
            config: configuration.minioConfig,
            dataDirectory: storageService.dataDirectory(for: configuration.minioStorageKey)
        )
        let dynamodbClient = DynamoDBClient(
            dockerClient: dockerClient,
            config: configuration.dynamodbConfig,
            dataDirectory: storageService.dataDirectory(for: configuration.dynamodbStorageKey)
        )

        let useCase = ServicesStatusUseCase(
            postgresClient: postgresClient,
            minioClient: minioClient,
            dynamodbClient: dynamodbClient
        )

        return Components(
            useCase: useCase,
            postgresClient: postgresClient,
            minioClient: minioClient,
            dynamodbClient: dynamodbClient
        )
    }

    public typealias State = LocalServicesUseCaseState
    public typealias Result = LocalServicesUseCaseState
    public typealias Options = Void

    /// Stream the status check use case.
    /// - Returns: AsyncThrowingStream that yields LocalServicesUseCaseState updates
    public func stream(options: Void) -> AsyncThrowingStream<LocalServicesUseCaseState, Error> {
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
        continuation: AsyncThrowingStream<LocalServicesUseCaseState, Error>.Continuation
    ) async throws {
        let startTime = Date()

        // Check S3 (MinIO)
        continuation.yield(.checkingStatus(LocalServicesUseCaseState.StatusProgress(
            step: .checkingS3,
            startTime: startTime
        )))
        let s3Running = try await minioClient.isRunning()

        // Check PostgreSQL
        continuation.yield(.checkingStatus(LocalServicesUseCaseState.StatusProgress(
            step: .checkingDatabase,
            startTime: startTime
        )))
        let postgresRunning = try await postgresClient.isRunning()

        // Check DynamoDB
        continuation.yield(.checkingStatus(LocalServicesUseCaseState.StatusProgress(
            step: .checkingDynamoDB,
            startTime: startTime
        )))
        let dynamodbRunning = try await dynamodbClient.isRunning()

        // Build final snapshot
        let snapshot = LocalServicesSnapshot.from(
            s3Running: s3Running,
            postgresRunning: postgresRunning,
            dynamodbRunning: dynamodbRunning
        )
        continuation.yield(.completed(snapshot))
        continuation.finish()
    }
}
