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

/// Use case for stopping local services for Linux development.
/// Contains all service stop logic directly, using SDK clients.
public struct LinuxStopServicesUseCase: StreamingUseCase {
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
        public let useCase: LinuxStopServicesUseCase
        public let postgresClient: PostgreSQLClient
        public let minioClient: MinIOClient
        public let dynamodbClient: DynamoDBClient
    }

    /// Creates a use case and associated components by instantiating required clients.
    /// - Parameter workingDirectory: The working directory for the use case
    /// - Returns: Components containing the use case and clients
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

        let useCase = LinuxStopServicesUseCase(
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

    public typealias State = LinuxUseCaseState
    public typealias Result = State

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
    /// - Returns: AsyncThrowingStream that yields LinuxUseCaseState updates
    public func stream(options: Options) -> AsyncThrowingStream<State, Error> {
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
        continuation: AsyncThrowingStream<State, Error>.Continuation
    ) async throws {
        let startTime = Date()

        // Stop PostgreSQL
        if options.services.contains(.database) {
            continuation.yield(.stoppingServices(LinuxUseCaseState.ServicesProgress(step: .stopping, startTime: startTime, currentService: .database)))
            try await postgresClient.stop()
        }

        // Stop MinIO S3
        if options.services.contains(.s3) {
            continuation.yield(.stoppingServices(LinuxUseCaseState.ServicesProgress(step: .stopping, startTime: startTime, currentService: .s3)))
            try await minioClient.stop()
        }

        // Stop DynamoDB Local
        if options.services.contains(.dynamodb) {
            continuation.yield(.stoppingServices(LinuxUseCaseState.ServicesProgress(step: .stopping, startTime: startTime, currentService: .dynamodb)))
            try await dynamodbClient.stop()
        }

        // Build final snapshot - all stopped
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
}
