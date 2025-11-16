//
//  SwiftServerAppTests.swift
//  
//
//  Created by Bill Gestrich on 12/9/23.
//

import FluentKit
import NIO
@testable import SwiftServerApp
import XCTest

final class SwiftServerAppTests: XCTestCase {

    override func setUpWithError() throws {
    }

    override func tearDownWithError() throws {
    }

    func testS3UploadAndDownload() async throws {
        let s3Service = MockS3DataStore()
        let app = SwiftServerApp(s3DataStore: s3Service, postgresUserStore: nil)
        let result = try await app.uploadAndDownloadS3File()
        XCTAssertEqual(result, "Hello World! This data was written/read from S3.")
    }

    func testCreateUser() async throws {
        let databaseService = PostgresUserStoreProduction.createInMemoryDatabaseService()
        try await databaseService.wipeAndInitialize()
        let app = SwiftServerApp(s3DataStore: nil, postgresUserStore: databaseService)
        let user = CreateUser(email: "test@gmail.com", password: "pw", firstName: "John", lastName: "Smith", nickName: "JS", phone: "555-555-5555", slackID: "12345")
        let result = try await app.createUser(user)
        try await databaseService.shutdown()
        XCTAssertEqual(result, "Inserted and Read User: John Smith")
    }
}

final class MockS3DataStore: S3DataStoreInterface, @unchecked Sendable {
    var keysToData = [String: Data]()

    func getData(key: String) async throws -> Data? {
        return keysToData[key]
    }

    func uploadData(_ data: Data, key: String) async throws {
        keysToData[key] = data
    }
}

extension PostgresUserStoreProduction {
    public static func createInMemoryDatabaseService() -> UserStorePostgres {
        let threadPool: NIOThreadPool = NIOThreadPool(numberOfThreads: System.coreCount)
        threadPool.start()
        let eventLoop = MultiThreadedEventLoopGroup(numberOfThreads: 2).next()
        let databases: Databases = Databases(threadPool: threadPool, on: eventLoop)
        databases.use(.sqlite(.memory), as: .sqlite)
        let database = databases.database(logger: Logger(label: "test.fluent.b"), on: eventLoop.next())!
        return UserStorePostgres(databases: databases, database: database, threadPool: threadPool)
    }
}
