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

/// Use case for stopping local services for Xcode development.
/// Contains all service stop logic directly, using SDK clients.
public struct XcodeStopServicesUseCase: StreamingUseCase {
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
        public let useCase: XcodeStopServicesUseCase
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

        let useCase = XcodeStopServicesUseCase(
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

    public typealias State = XcodeUseCaseState
    public typealias Result = XcodeUseCaseState

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
    /// - Returns: AsyncThrowingStream that yields XcodeUseCaseState updates
    public func stream(options: Options) -> AsyncThrowingStream<XcodeUseCaseState, Error> {
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
        continuation: AsyncThrowingStream<XcodeUseCaseState, Error>.Continuation
    ) async throws {
        let startTime = Date()

        // Stop PostgreSQL
        if options.services.contains(.database) {
            continuation.yield(.stoppingServices(XcodeUseCaseState.ServicesProgress(
                step: .stopping,
                startTime: startTime,
                currentService: .database
            )))
            try await postgresClient.stop()
        }

        // Stop MinIO S3
        if options.services.contains(.s3) {
            continuation.yield(.stoppingServices(XcodeUseCaseState.ServicesProgress(
                step: .stopping,
                startTime: startTime,
                currentService: .s3
            )))
            try await minioClient.stop()
        }

        // Stop DynamoDB Local
        if options.services.contains(.dynamodb) {
            continuation.yield(.stoppingServices(XcodeUseCaseState.ServicesProgress(
                step: .stopping,
                startTime: startTime,
                currentService: .dynamodb
            )))
            try await dynamodbClient.stop()
        }

        // Completed - yield snapshot with services stopped
        let snapshot = XcodeSnapshot(
            serviceStatus: .stopped,
            buildStatus: .notBuilt
        )
        continuation.yield(.completed(snapshot))
        continuation.finish()
    }
}
