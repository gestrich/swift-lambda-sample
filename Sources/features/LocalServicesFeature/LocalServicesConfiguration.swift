import Foundation
import DeployLocalService
import DynamoDBSDK
import MinioSDK
import PostgreSQLSDK
import StorageService

/// Configuration for local Docker services (PostgreSQL, MinIO, DynamoDB).
/// Captures all the differences between Xcode and Linux workflows.
public struct LocalServicesConfiguration: Sendable {
    public let postgresConfig: PostgreSQLConfig
    public let minioConfig: MinIOConfig
    public let dynamodbConfig: DynamoDBLocalConfig
    public let networkName: String
    public let postgresStorageKey: any StoragePathKey.Type
    public let minioStorageKey: any StoragePathKey.Type
    public let dynamodbStorageKey: any StoragePathKey.Type

    public init(
        postgresConfig: PostgreSQLConfig,
        minioConfig: MinIOConfig,
        dynamodbConfig: DynamoDBLocalConfig,
        networkName: String,
        postgresStorageKey: any StoragePathKey.Type,
        minioStorageKey: any StoragePathKey.Type,
        dynamodbStorageKey: any StoragePathKey.Type
    ) {
        self.postgresConfig = postgresConfig
        self.minioConfig = minioConfig
        self.dynamodbConfig = dynamodbConfig
        self.networkName = networkName
        self.postgresStorageKey = postgresStorageKey
        self.minioStorageKey = minioStorageKey
        self.dynamodbStorageKey = dynamodbStorageKey
    }

    /// Xcode development workflow configuration.
    /// Uses ports 5432, 9000/9001, 8000 and "lambda-xcode" network.
    public static let xcode = LocalServicesConfiguration(
        postgresConfig: .xcode,
        minioConfig: .xcode,
        dynamodbConfig: .xcode,
        networkName: "lambda-xcode",
        postgresStorageKey: PostgreSQLXcodeStorageKey.self,
        minioStorageKey: MinIOXcodeStorageKey.self,
        dynamodbStorageKey: DynamoDBLocalXcodeStorageKey.self
    )

    /// Linux container development workflow configuration.
    /// Uses ports 5433, 9002/9003, 8001 and "lambda-linux" network.
    public static let linux = LocalServicesConfiguration(
        postgresConfig: .linux,
        minioConfig: .linux,
        dynamodbConfig: .linux,
        networkName: "lambda-linux",
        postgresStorageKey: PostgreSQLLinuxStorageKey.self,
        minioStorageKey: MinIOLinuxStorageKey.self,
        dynamodbStorageKey: DynamoDBLocalLinuxStorageKey.self
    )

    /// Linux container development workflow configuration with custom network name.
    /// Use this when you need a custom network name (e.g., from LinuxContainerConfig).
    public static func linux(networkName: String) -> LocalServicesConfiguration {
        LocalServicesConfiguration(
            postgresConfig: .linux,
            minioConfig: .linux,
            dynamodbConfig: .linux,
            networkName: networkName,
            postgresStorageKey: PostgreSQLLinuxStorageKey.self,
            minioStorageKey: MinIOLinuxStorageKey.self,
            dynamodbStorageKey: DynamoDBLocalLinuxStorageKey.self
        )
    }
}
