//
//  UserStorePostgres.swift
//
//
//  Created by Bill Gestrich on 12/9/23.
//

import FluentKit
import FluentPostgresDriver
import FluentSQLiteDriver
import Foundation

public actor UserStorePostgres: UserStore {

    public let databases: Databases
    public let database: Database
    public let threadPool: NIOThreadPool

    init(databases: Databases, database: Database, threadPool: NIOThreadPool) {
        self.databases = databases
        self.database = database
        self.threadPool = threadPool
    }

    public init(eventLoop: EventLoop, configuration: PostgresConfiguration) async throws {

        //Database Setup
        let threadPool: NIOThreadPool = NIOThreadPool(numberOfThreads: System.coreCount)
        let databases: Databases = Databases(threadPool: threadPool, on: eventLoop)

        //let sslContext = try NIOSSLContext(configuration: .clientDefault)
        let tls = PostgresConnection.Configuration.TLS.disable //FAILS Locally: .prefer(sslContext)

        let postGresConfiguration = SQLPostgresConfiguration(
            hostname: configuration.host,
            port: configuration.port,
            username: configuration.username,
            password: configuration.userPassword,
            database: configuration.name,
            tls: tls
        )

        databases.use(.postgres(configuration: postGresConfiguration), as: DatabaseID.init(string: configuration.identifier))
        let database = databases.database(DatabaseID.init(string: configuration.identifier), logger: Logger(label: "test.fluent.a"), on: eventLoop.next())!

        self.databases = databases
        self.database = database
        self.threadPool = threadPool
    }

    public func wipeAndInitialize() async throws {
        await deleteTables()
        try await createTables()
    }

    public func createTables() async throws {
        for migration in allMigrations() {
            let _ = try await migration.prepare(on: database)
        }
    }

    public func deleteTables() async {
        for migration in allMigrations().reversed() {
            //Ignore errors as this occurs when tables do not exist
            do {
                try await migration.revert(on: database)
            } catch {
                print(error)
            }
        }
    }

    public func allMigrations() -> [AsyncMigration] {
        return [
            CreatePostgresUser(),
        ]
    }

    public func shutdown() async throws {
        databases.shutdown()
        let _ = try? await threadPool.shutdownGracefully()
    }
    
    //MARK: User CRUD
    
    public func getUser(id: UUID) async throws -> User? {
        let matches = try await User.query(on: database)
            .filter(\.$id == id)
            .all()
        return matches.first
    }
    
    public func getUsers() async throws -> [User] {
        return try await User.query(on: database).all()
    }
    
    public func createUser(_ user: User) async throws{
        try await user.create(on: database)
    }
    
    public func updateUser(_ user: User) async throws -> User {
        guard let id = user.id else {
            throw UserStorePostgresError.updateUserError("Missing user id")
        }
        try await user.update(on: database)
        guard let result = try await getUser(id: id) else {
            throw UserStorePostgresError.updateUserError("Could not fetch updated user")
        }

        return result
    }
    
    public func deleteUser(_ user : User) async throws {
        try await user.delete(on: database)
    }
}

enum UserStorePostgresError: LocalizedError {
    case updateUserError(String)

    var errorDescription: String? {
        switch self {
        case .updateUserError(let description):
            return description
        }
    }
}
