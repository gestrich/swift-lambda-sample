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

/// Unified use case for starting local Docker services.
/// Configuration-driven to support both Xcode and Linux workflows.
public struct StartServicesUseCase: StreamingUseCase {
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
        public let useCase: StartServicesUseCase
        public let cliClient: CLIClient
        public let dockerClient: DockerClient
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

        let useCase = StartServicesUseCase(
            cliClient: cliClient,
            dockerClient: dockerClient,
            postgresClient: postgresClient,
            minioClient: minioClient,
            dynamodbClient: dynamodbClient
        )

        return Components(
            useCase: useCase,
            cliClient: cliClient,
            dockerClient: dockerClient,
            postgresClient: postgresClient,
            minioClient: minioClient,
            dynamodbClient: dynamodbClient
        )
    }

    public typealias State = LocalServicesUseCaseState
    public typealias Result = LocalServicesUseCaseState

    /// Options for the start services use case.
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

    /// Stream the start services use case.
    /// - Parameter options: Service options specifying which services to start
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
            continuation.yield(.starting(LocalServicesUseCaseState.ServicesProgress(
                step: .starting,
                startTime: startTime,
                currentService: .database
            )))
            try await postgresClient.start()
            postgresState = .running
        }

        // Start MinIO S3
        if options.services.contains(.s3) {
            continuation.yield(.starting(LocalServicesUseCaseState.ServicesProgress(
                step: .starting,
                startTime: startTime,
                currentService: .s3
            )))
            try await minioClient.start()
            s3State = .running

            // Create bucket after S3 is running
            continuation.yield(.starting(LocalServicesUseCaseState.ServicesProgress(
                step: .creatingBucket,
                startTime: startTime,
                currentService: .s3
            )))
            try await minioClient.createBucket(bucketName: nil)
        }

        // Start DynamoDB Local
        if options.services.contains(.dynamodb) {
            continuation.yield(.starting(LocalServicesUseCaseState.ServicesProgress(
                step: .starting,
                startTime: startTime,
                currentService: .dynamodb
            )))
            try await dynamodbClient.start()
            dynamodbState = .running
        }

        // Build final snapshot
        let snapshot = LocalServicesSnapshot(
            s3State: s3State,
            postgresState: postgresState,
            dynamodbState: dynamodbState
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
