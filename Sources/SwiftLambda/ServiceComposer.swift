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
import SwiftServerApp

/*
 Manages the lifecycle and configuration of your services.
 */

class ServiceComposer {

    let app: SwiftServerApp
    let awsClient: AWSClient
    let configurationService: ConfigurationService
    let cloudDataService: CloudDataStore
    let secretsService: SecretsService
    let userStoreService: UserStoreProduction
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
            awsClient = AWSClient(credentialProvider: .static(accessKeyId: "admin", secretAccessKey: "password"), httpClientProvider: .createNew)
        } else {
            awsClient = AWSClient(httpClientProvider: .createNew)
        }

        self.awsClient = awsClient

        let secretsServiceAWS = SecretsServiceAWS(awsClient: awsClient)
        self.secretsService = SecretsServiceProduction(awsSecretsService: secretsServiceAWS)

        self.configurationService = ConfigurationService(secretsService: secretsService)

        let cloudStoreFactory = CloudStoreFactory(configurationService: configurationService, awsClient: awsClient)
        self.cloudDataService = CloudDataStoreProduction(cloudStoreFactory: cloudStoreFactory.createCloudStore)

        // Create EventLoopGroup only if database is configured (Fluent requires it)
        let eventLoopGroup: MultiThreadedEventLoopGroup?
        let hasDatabase = (try? await configurationService.postgresConfiguration()) != nil
        if hasDatabase {
            eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        } else {
            eventLoopGroup = nil
        }
        self.eventLoopGroup = eventLoopGroup

        let userStoreFactory = UserStoreFactory(configurationService: self.configurationService, eventLoopGroup: eventLoopGroup)
        self.userStoreService = UserStoreProduction(userStoreFactory: userStoreFactory.createUserStore)

        let app = SwiftServerApp(cloudDataStore: cloudDataService, userStore: userStoreService)
        self.app = app
    }

    func shutdown() async throws {
        try await awsClient.shutdown()
        try await userStoreService.shutdown()
        try await eventLoopGroup?.shutdownGracefully()
    }
}

struct CloudStoreFactory: Sendable {

    let configurationService: ConfigurationService
    let awsClient: AWSClient

    func createCloudStore() async throws -> CloudDataStore {
        let configuration = try await configurationService.s3Configuration()
        return CloudDataStoreS3(awsClient: awsClient, bucketName: configuration.bucketName, endpoint: configuration.endpoint)
    }
}

struct UserStoreFactory {

    let configurationService: ConfigurationService
    let eventLoopGroup: MultiThreadedEventLoopGroup?

    func createUserStore() async throws -> UserStore? {
        guard let configuration = try await configurationService.postgresConfiguration() else {
            // Database not configured - return nil (database is optional)
            return nil
        }
        guard let eventLoopGroup = eventLoopGroup else {
            throw ServiceComposerError.missingEventLoopGroup
        }
        return try await UserStorePostgres(eventLoop: eventLoopGroup.next(), configuration: configuration)
    }
}

enum ServiceComposerError: Error {
    case missingEventLoopGroup
}
