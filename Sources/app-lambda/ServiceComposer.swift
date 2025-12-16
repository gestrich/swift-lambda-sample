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

/*
 Manages the lifecycle and configuration of your services.
 */

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

    init() async throws {

        let awsClient: AWSClient
        let value = Self.getEnvironmentVariable(key: "MOCK_AWS_CREDENTIALS")
        if value == "true" {
            awsClient = AWSClient(credentialProvider: .static(accessKeyId: "admin", secretAccessKey: "password"))
        } else {
            awsClient = AWSClient()
        }

        self.awsClient = awsClient

        let secretsServiceAWS = SecretsServiceAWS(awsClient: awsClient)
        self.secretsService = SecretsServiceProduction(awsSecretsService: secretsServiceAWS)

        self.configurationService = ConfigurationService(secretsService: secretsService)

        let s3StoreFactory = S3StoreFactory(configurationService: configurationService, awsClient: awsClient)
        self.s3DataService = S3DataStoreProduction(s3StoreFactory: s3StoreFactory.createS3Store)

        let dynamoDBStoreFactory = DynamoDBStoreFactory(configurationService: configurationService, awsClient: awsClient)
        self.dynamoDBDataService = DynamoDBDataStoreProduction(dynamoDBStoreFactory: dynamoDBStoreFactory.createDynamoDBStore)

        // Create EventLoopGroup only if database is configured (Fluent requires it)
        let eventLoopGroup: MultiThreadedEventLoopGroup?
        let hasDatabase = (try? await configurationService.postgresConfiguration()) != nil
        if hasDatabase {
            eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        } else {
            eventLoopGroup = nil
        }
        self.eventLoopGroup = eventLoopGroup

        let postgresModelStoreFactory = PostgresModelStoreFactory(configurationService: self.configurationService, eventLoopGroup: eventLoopGroup)
        self.postgresModelStoreService = PostgresModelStoreProduction(modelStoreFactory: postgresModelStoreFactory.createPostgresModelStore)

        let app = SwiftServerApp(s3DataStore: s3DataService, postgresModelStore: postgresModelStoreService, dynamoDBDataStore: dynamoDBDataService)
        self.app = app
    }

    func shutdown() async throws {
        try await awsClient.shutdown()
        try await postgresModelStoreService.shutdown()
        try await eventLoopGroup?.shutdownGracefully()
    }
}

struct S3StoreFactory: Sendable {

    let configurationService: ConfigurationService
    let awsClient: AWSClient

    func createS3Store() async throws -> S3DataStoreInterface {
        let configuration = try await configurationService.s3Configuration()
        return S3DataStoreS3(awsClient: awsClient, bucketName: configuration.bucketName, endpoint: configuration.endpoint)
    }
}

struct DynamoDBStoreFactory: Sendable {

    let configurationService: ConfigurationService
    let awsClient: AWSClient

    func createDynamoDBStore() async throws -> DynamoDBDataStoreInterface {
        let configuration = try await configurationService.dynamoDBConfiguration()
        return DynamoDBDataStoreAWS(awsClient: awsClient, tableName: configuration.tableName, endpoint: configuration.endpoint)
    }
}

struct PostgresModelStoreFactory {

    let configurationService: ConfigurationService
    let eventLoopGroup: MultiThreadedEventLoopGroup?

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

enum ServiceComposerError: Error {
    case missingEventLoopGroup
}
