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

/// Use case for checking the status of local development services (Xcode mode).
/// Contains all status check logic directly, using SDK clients.
public struct XcodeStatusUseCase: StreamingUseCase {
    private let cliClient: CLIClient
    private let postgresClient: PostgreSQLClient
    private let minioClient: MinIOClient
    private let dynamodbClient: DynamoDBClient

    // Lambda configuration
    private let lambdaHostPort = 8080
    private let lambdaProcessPattern = "swiftlamb"  // lsof truncates process names

    public init(
        cliClient: CLIClient,
        postgresClient: PostgreSQLClient,
        minioClient: MinIOClient,
        dynamodbClient: DynamoDBClient
    ) {
        self.cliClient = cliClient
        self.postgresClient = postgresClient
        self.minioClient = minioClient
        self.dynamodbClient = dynamodbClient
    }

    /// Components needed for checking status.
    public struct Components: Sendable {
        public let useCase: XcodeStatusUseCase
        public let cliClient: CLIClient
        public let postgresClient: PostgreSQLClient
        public let minioClient: MinIOClient
        public let dynamodbClient: DynamoDBClient
    }

    /// Creates a use case and associated components by instantiating required clients.
    /// - Returns: Components containing the use case and clients
    public static func create() -> Components {
        let cliClient = CLIClient()
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

        let useCase = XcodeStatusUseCase(
            cliClient: cliClient,
            postgresClient: postgresClient,
            minioClient: minioClient,
            dynamodbClient: dynamodbClient
        )

        return Components(
            useCase: useCase,
            cliClient: cliClient,
            postgresClient: postgresClient,
            minioClient: minioClient,
            dynamodbClient: dynamodbClient
        )
    }

    public typealias State = XcodeUseCaseState
    public typealias Result = XcodeUseCaseState
    public typealias Options = Void

    /// Stream the status use case.
    /// - Returns: AsyncThrowingStream that yields XcodeUseCaseState updates
    public func stream(options: Void) -> AsyncThrowingStream<XcodeUseCaseState, Error> {
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
        continuation: AsyncThrowingStream<XcodeUseCaseState, Error>.Continuation
    ) async throws {
        let startTime = Date()

        // Check Lambda status
        continuation.yield(.checkingStatus(XcodeUseCaseState.StatusProgress(
            step: .checkingLambda,
            startTime: startTime
        )))
        let lambdaRunning = await isLambdaRunning()

        // Check S3 status
        continuation.yield(.checkingStatus(XcodeUseCaseState.StatusProgress(
            step: .checkingS3,
            startTime: startTime
        )))
        let s3Running = try await minioClient.isRunning()

        // Check PostgreSQL status
        continuation.yield(.checkingStatus(XcodeUseCaseState.StatusProgress(
            step: .checkingDatabase,
            startTime: startTime
        )))
        let postgresRunning = try await postgresClient.isRunning()

        // Check DynamoDB status
        continuation.yield(.checkingStatus(XcodeUseCaseState.StatusProgress(
            step: .checkingDynamoDB,
            startTime: startTime
        )))
        let dynamodbRunning = try await dynamodbClient.isRunning()

        // Build final status and snapshot
        let status = DeploymentStatus(
            lambdaState: lambdaRunning ? .running : .stopped,
            s3State: s3Running ? .running : .stopped,
            postgresState: postgresRunning ? .running : .stopped,
            dynamodbState: dynamodbRunning ? .running : .stopped
        )

        let snapshot = XcodeSnapshot(
            serviceStatus: status,
            buildStatus: .notBuilt
        )

        continuation.yield(.completed(snapshot))
        continuation.finish()
    }

    // MARK: - Lambda Status Helpers

    /// Check if Lambda is running (native process on port, not Docker)
    public func isLambdaRunning() async -> Bool {
        let output = await getPortInfo(lambdaHostPort)
        guard !output.isEmpty else { return false }

        let lines = output.components(separatedBy: "\n")
        for line in lines {
            let lowercased = line.lowercased()
            if lowercased.contains(lambdaProcessPattern) && !lowercased.contains("docker") {
                return true
            }
        }
        return false
    }

    // MARK: - Private Helpers

    /// Get information about what's using a port
    private func getPortInfo(_ port: Int) async -> String {
        do {
            let result = try await cliClient.executeForResult(
                Lsof(port: ":\(port)"),
                printCommand: false
            )
            guard result.isSuccess else { return "" }
            return result.stdout
        } catch {
            return ""
        }
    }
}
