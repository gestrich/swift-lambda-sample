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

/// Unified use case for stopping local Docker services.
/// Configuration-driven to support both Xcode and Linux workflows.
public struct StopServicesUseCase: StreamingUseCase {
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

    /// Components needed for stopping services.
    public struct Components: Sendable {
        public let useCase: StopServicesUseCase
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

        let useCase = StopServicesUseCase(
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

    /// Options for the stop services use case.
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

    /// Stream the stop services use case.
    /// - Parameter options: Service options specifying which services to stop
    /// - Returns: AsyncThrowingStream that yields LocalServicesUseCaseState updates
    public func stream(options: Options) -> AsyncThrowingStream<LocalServicesUseCaseState, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    try await runUseCase(options: options, continuation: continuation)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func runUseCase(
        options: Options,
        continuation: AsyncThrowingStream<LocalServicesUseCaseState, Error>.Continuation
    ) async throws {
        let startTime = Date()

        // Stop PostgreSQL
        if options.services.contains(.database) {
            continuation.yield(.stopping(LocalServicesUseCaseState.ServicesProgress(
                step: .stopping,
                startTime: startTime,
                currentService: .database
            )))
            try await postgresClient.stop()
        }

        // Stop MinIO S3
        if options.services.contains(.s3) {
            continuation.yield(.stopping(LocalServicesUseCaseState.ServicesProgress(
                step: .stopping,
                startTime: startTime,
                currentService: .s3
            )))
            try await minioClient.stop()
        }

        // Stop DynamoDB Local
        if options.services.contains(.dynamodb) {
            continuation.yield(.stopping(LocalServicesUseCaseState.ServicesProgress(
                step: .stopping,
                startTime: startTime,
                currentService: .dynamodb
            )))
            try await dynamodbClient.stop()
        }

        // Build final snapshot - all stopped
        let snapshot = LocalServicesSnapshot.stopped
        continuation.yield(.completed(snapshot))
        continuation.finish()
    }
}
