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

/// Workflow for stopping local services for Xcode development.
/// Contains all service stop logic directly, using SDK clients.
public struct XcodeStopServicesWorkflow: StreamingUseCase {
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
        public let workflow: XcodeStopServicesWorkflow
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

        let workflow = XcodeStopServicesWorkflow(
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

    public typealias State = XcodeWorkflowState
    public typealias Result = XcodeWorkflowState

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
    /// - Returns: AsyncThrowingStream that yields XcodeWorkflowState updates
    public func stream(options: Options) -> AsyncThrowingStream<XcodeWorkflowState, Error> {
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
        continuation: AsyncThrowingStream<XcodeWorkflowState, Error>.Continuation
    ) async throws {
        let startTime = Date()

        // Stop PostgreSQL
        if options.services.contains(.database) {
            continuation.yield(.stoppingServices(XcodeWorkflowState.ServicesProgress(
                step: .stopping,
                startTime: startTime,
                currentService: .database
            )))
            try await postgresClient.stop()
        }

        // Stop MinIO S3
        if options.services.contains(.s3) {
            continuation.yield(.stoppingServices(XcodeWorkflowState.ServicesProgress(
                step: .stopping,
                startTime: startTime,
                currentService: .s3
            )))
            try await minioClient.stop()
        }

        // Stop DynamoDB Local
        if options.services.contains(.dynamodb) {
            continuation.yield(.stoppingServices(XcodeWorkflowState.ServicesProgress(
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
