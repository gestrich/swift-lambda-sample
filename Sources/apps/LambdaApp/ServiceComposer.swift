//
//  ServiceComposer.swift
//
//
//  Created by Bill Gestrich on 12/9/23.
//

import Foundation
import NIOCore
import NIOPosix
import SotoS3
import SotoSecretsManager
import SotoDynamoDB

/// Manages the lifecycle and configuration of all Lambda services.
///
/// **Initialization Lifecycle:**
/// This class is instantiated on every Lambda invocation and handles:
/// 1. AWS client creation (with mock credential support for local development)
/// 2. Secrets Manager integration
/// 3. Configuration loading (from files or environment variables)
/// 4. Service factory setup (S3, DynamoDB, PostgreSQL)
/// 5. Conditional resource allocation (EventLoopGroup only created if database is configured)
/// 6. Application composition
///
/// **Performance Note:**
/// Currently, services are initialized per-request. For better performance, consider using
/// `Lambda.InitializationContext` to create persistent connections across invocations.
///
/// **Resource Cleanup:**
/// Always call `shutdown()` after request processing to properly release:
/// - AWS client connections
/// - PostgreSQL connections
/// - EventLoopGroup threads
class ServiceComposer {

    let app: SwiftServerApp
    let awsClient: AWSClient
    let configurationService: ConfigurationService
    let s3DataService: S3DataStoreInterface
    let dynamoDBDataService: DynamoDBDataStoreInterface
    let secretsService: SecretsServiceInterface
    let postgresModelStoreService: PostgresModelStoreProduction
    let eventLoopGroup: MultiThreadedEventLoopGroup?

    private static func getEnvironmentVariable(key: String) -> String? {
        guard let rawVal = getenv(key) else {
            return nil
        }

        guard let result = String(utf8String: rawVal) else {
            return nil
        }

        return result
    }

    /// Initializes all services required for Lambda request handling.
    ///
    /// **Initialization Steps:**
    /// 1. **AWS Client**: Creates client with real credentials (production) or mock credentials (local development)
    /// 2. **Secrets Manager**: Sets up access to AWS Secrets Manager for secure credential storage
    /// 3. **Configuration**: Loads config from files (local) or environment variables (AWS)
    /// 4. **Service Factories**: Creates factory closures for lazy initialization of expensive resources
    /// 5. **EventLoopGroup**: Conditionally creates thread pool only if database is configured (optimization)
    /// 6. **Application**: Composes all services into the main application instance
    ///
    /// **Local Development Mode:**
    /// Set `MOCK_AWS_CREDENTIALS=true` to use static credentials for local S3/DynamoDB/Secrets testing.
    /// This allows the Lambda to connect to local services (MinIO, DynamoDB Local) without AWS authentication.
    ///
    /// **Database Optimization:**
    /// The EventLoopGroup (NIO thread pool) is only created if PostgreSQL is configured, saving resources
    /// when running without a database. This check is async because configuration may load from Secrets Manager.
    ///
    /// - Throws: Configuration errors if required environment variables are missing or invalid
    init() async throws {

        // Create AWS client - use mock credentials for local development
        let awsClient: AWSClient
        let value = Self.getEnvironmentVariable(key: "MOCK_AWS_CREDENTIALS")
        if value == "true" {
            // Local development: static credentials for MinIO, DynamoDB Local, etc.
            awsClient = AWSClient(credentialProvider: .static(accessKeyId: "admin", secretAccessKey: "password"))
        } else {
            // Production: IAM role credentials from Lambda execution environment
            awsClient = AWSClient()
        }

        self.awsClient = awsClient

        // Set up Secrets Manager integration for secure credential storage
        let secretsServiceAWS = SecretsServiceAWS(awsClient: awsClient)
        self.secretsService = SecretsServiceProduction(awsSecretsService: secretsServiceAWS)

        // Load configuration from files (local) or environment variables (AWS)
        self.configurationService = ConfigurationService(secretsService: secretsService)

        // Create service factories with lazy initialization via closures
        let s3StoreFactory = S3StoreFactory(configurationService: configurationService, awsClient: awsClient)
        self.s3DataService = S3DataStoreProduction(s3StoreFactory: s3StoreFactory.createS3Store)

        let dynamoDBStoreFactory = DynamoDBStoreFactory(configurationService: configurationService, awsClient: awsClient)
        self.dynamoDBDataService = DynamoDBDataStoreProduction(dynamoDBStoreFactory: dynamoDBStoreFactory.createDynamoDBStore)

        // Conditionally create EventLoopGroup only if database is configured
        // This saves resources when running without PostgreSQL
        let eventLoopGroup: MultiThreadedEventLoopGroup?
        let hasDatabase = (try? await configurationService.postgresConfiguration()) != nil
        if hasDatabase {
            // Create single-threaded EventLoopGroup for Fluent database operations
            eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        } else {
            eventLoopGroup = nil
        }
        self.eventLoopGroup = eventLoopGroup

        // Create PostgreSQL factory with optional database support
        let postgresModelStoreFactory = PostgresModelStoreFactory(configurationService: self.configurationService, eventLoopGroup: eventLoopGroup)
        self.postgresModelStoreService = PostgresModelStoreProduction(modelStoreFactory: postgresModelStoreFactory.createPostgresModelStore)

        // Compose all services into the main application
        let app = SwiftServerApp(s3DataStore: s3DataService, postgresModelStore: postgresModelStoreService, dynamoDBDataStore: dynamoDBDataService)
        self.app = app
    }

    /// Shuts down all services and releases resources.
    ///
    /// **Critical for Lambda Cost Optimization:**
    /// Must be called after every request to properly release:
    /// - AWS client HTTP connections
    /// - PostgreSQL database connections
    /// - EventLoopGroup thread pool
    ///
    /// Failure to call shutdown will leak connections and threads, increasing Lambda memory usage
    /// and potentially causing throttling or timeouts on subsequent invocations.
    ///
    /// - Throws: Any errors from shutting down individual services
    func shutdown() async throws {
        try await awsClient.shutdown()
        try await postgresModelStoreService.shutdown()
        try await eventLoopGroup?.shutdownGracefully()
    }
}

/// Factory for creating S3 data store instances.
///
/// Uses a factory pattern with async closures to defer expensive S3 client initialization
/// until the S3 service is actually needed. Configuration is loaded lazily from environment
/// variables or config files.
struct S3StoreFactory: Sendable {

    let configurationService: ConfigurationService
    let awsClient: AWSClient

    /// Creates an S3 data store instance with lazy configuration loading.
    ///
    /// - Returns: Configured S3 data store connected to AWS S3 or MinIO (local development)
    /// - Throws: Configuration errors if S3 bucket name or endpoint is missing/invalid
    func createS3Store() async throws -> S3DataStoreInterface {
        let configuration = try await configurationService.s3Configuration()
        return S3DataStoreS3(awsClient: awsClient, bucketName: configuration.bucketName, endpoint: configuration.endpoint)
    }
}

/// Factory for creating DynamoDB data store instances.
///
/// Uses a factory pattern with async closures to defer expensive DynamoDB client initialization
/// until the DynamoDB service is actually needed. Configuration is loaded lazily from environment
/// variables or config files.
struct DynamoDBStoreFactory: Sendable {

    let configurationService: ConfigurationService
    let awsClient: AWSClient

    /// Creates a DynamoDB data store instance with lazy configuration loading.
    ///
    /// - Returns: Configured DynamoDB data store connected to AWS DynamoDB or DynamoDB Local
    /// - Throws: Configuration errors if table name or endpoint is missing/invalid
    func createDynamoDBStore() async throws -> DynamoDBDataStoreInterface {
        let configuration = try await configurationService.dynamoDBConfiguration()
        return DynamoDBDataStoreAWS(awsClient: awsClient, tableName: configuration.tableName, endpoint: configuration.endpoint)
    }
}

/// Factory for creating PostgreSQL model store instances.
///
/// **Optional Database Support:**
/// PostgreSQL is optional - if not configured, `createPostgresModelStore()` returns nil.
/// This allows the Lambda to run without a database for S3-only or DynamoDB-only use cases.
///
/// **EventLoopGroup Requirement:**
/// Fluent (the PostgreSQL ORM) requires a NIO EventLoopGroup for async operations.
/// The EventLoopGroup must be created before calling this factory method, or an error is thrown.
struct PostgresModelStoreFactory {

    let configurationService: ConfigurationService
    let eventLoopGroup: MultiThreadedEventLoopGroup?

    /// Creates a PostgreSQL model store instance with lazy configuration loading.
    ///
    /// **Optional Database:**
    /// Returns nil if PostgreSQL is not configured (database is optional). This allows the Lambda
    /// to handle requests that don't require database access.
    ///
    /// - Returns: Configured PostgreSQL model store, or nil if database is not configured
    /// - Throws: `ServiceComposerError.missingEventLoopGroup` if EventLoopGroup is nil but database is configured
    /// - Throws: Configuration errors if database credentials are missing/invalid
    func createPostgresModelStore() async throws -> PostgresModelStoreInterface? {
        guard let configuration = try await configurationService.postgresConfiguration() else {
            // Database not configured - return nil (database is optional)
            return nil
        }
        guard let eventLoopGroup = eventLoopGroup else {
            throw ServiceComposerError.missingEventLoopGroup
        }
        return try await PostgresModelStore(eventLoop: eventLoopGroup.next(), configuration: configuration)
    }
}

/// Errors that can occur during service composition.
enum ServiceComposerError: Error {
    /// EventLoopGroup is required for PostgreSQL but was not created during initialization.
    /// This should never happen if ServiceComposer.init() is implemented correctly.
    case missingEventLoopGroup
}
