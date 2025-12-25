//
//  EnvironmentVariables.swift
//  SwiftLambda
//
//  Created by Bill Gestrich on 11/27/25.
//

import DynamoDBSDK
import Foundation
import MinioSDK
import PostgreSQLSDK
import StorageService

/// Execution context for Lambda - determines how to connect to services
public enum LambdaExecutionContext {
    /// Native macOS process (Xcode mode) - connects via localhost
    case xcode
    /// Docker container (Linux mode) - connects via Docker network DNS
    case container
}

/// Create environment variables for Lambda based on execution context
public func createEnvironmentVariables(
    postgresClient: PostgreSQLClient,
    minioClient: MinIOClient,
    dynamodbClient: DynamoDBClient,
    context: LambdaExecutionContext = .container
) -> [String: String] {
    let postgresInfo = postgresClient.connectionInfo
    let minioCreds = minioClient.credentials

    // Determine host and port based on execution context
    let postgresHost: String
    let postgresPort: Int
    let minioHost: String
    let minioPort: Int
    let dynamodbHost: String
    let dynamodbPort: Int

    switch context {
    case .xcode:
        // Native process connects via localhost (services expose ports to host)
        postgresHost = "localhost"
        postgresPort = postgresInfo.port  // External/host port
        minioHost = "localhost"
        minioPort = minioClient.s3Port  // External/host port
        dynamodbHost = "localhost"
        dynamodbPort = dynamodbClient.connectionInfo.port
    case .container:
        // Container connects via Docker network DNS (container names)
        // Use internal ports since we're connecting container-to-container
        postgresHost = postgresInfo.containerName
        postgresPort = postgresInfo.internalPort  // Internal port (always 5432)
        minioHost = minioClient.minioContainerName
        minioPort = minioClient.internalS3Port  // Internal port (always 9000)
        dynamodbHost = dynamodbClient.connectionInfo.containerName
        dynamodbPort = dynamodbClient.connectionInfo.internalPort
    }

    let env: [String: String] = [
        // PostgreSQL configuration
        "POSTGRES_HOST": postgresHost,
        "POSTGRES_PORT": "\(postgresPort)",
        "POSTGRES_USER_NAME": postgresInfo.username,
        "POSTGRES_DBNAME": postgresInfo.database,
        "POSTGRES_PASSWORD": postgresInfo.password,
        "POSTGRES_PASSWORD_SECRET_ID": "local-testing",  // Bypass Secrets Manager for local testing

        // S3/MinIO configuration
        "S3_BUCKET_NAME": minioClient.bucketName,
        "AWS_ENDPOINT_URL": "http://\(minioHost):\(minioPort)",
        "AWS_ACCESS_KEY_ID": minioCreds.accessKeyId,
        "AWS_SECRET_ACCESS_KEY": minioCreds.secretAccessKey,
        "AWS_REGION": minioCreds.region,
        "AWS_DEFAULT_REGION": minioCreds.region,

        // DynamoDB configuration (always included for local development)
        "DYNAMODB_ENDPOINT": "http://\(dynamodbHost):\(dynamodbPort)",
        "DYNAMODB_TABLE_NAME": "Reminders",
        "DYNAMODB_AWS_REGION": minioCreds.region,

        // Disable AWS credential chain for local testing
        "AWS_EC2_METADATA_DISABLED": "true",
        "AWS_CONTAINER_CREDENTIALS_RELATIVE_URI": "",  // Disable ECS credentials

        // Local Lambda server configuration
        "MOCK_AWS_CREDENTIALS": "true",
        "LOCAL_LAMBDA_SERVER_ENABLED": "true",
        "LOCAL_LAMBDA_HOST": "0.0.0.0"
    ]

    return env
}

// MARK: - Storage Keys

/// Storage key for app configuration file
public struct AppConfigFileKey: StorageFileKey {
    public static let filename = "swiftLambdaDemo.json"
}
