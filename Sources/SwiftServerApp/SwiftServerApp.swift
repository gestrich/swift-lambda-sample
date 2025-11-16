//
//  SwiftServerApp.swift
//
//
//  Created by Bill Gestrich on 12/9/23.
//

import Foundation

public struct SwiftServerApp {

    let s3DataStore: S3DataStoreInterface?
    let postgresUserStore: PostgresUserStoreInterface?
    let s3FileKey = "hello-world.text"

    public init(s3DataStore: S3DataStoreInterface? = nil, postgresUserStore: PostgresUserStoreInterface?) {
        self.s3DataStore = s3DataStore
        self.postgresUserStore = postgresUserStore
    }
    
    
    //MARK: Database Service

    public func initializeDatabase() async throws {
        guard let postgresUserStore else {
            throw LambdaDemoError.missingService(name: "postgresUserStore")
        }
        //TODO: This should not delete the database contents.
        try await postgresUserStore.wipeAndInitialize()
    }

    public func resetDatabase() async throws {
        guard let postgresUserStore else {
            throw LambdaDemoError.missingService(name: "postgresUserStore")
        }

        try await postgresUserStore.wipeAndInitialize()
    }

    
    //MARK: User Service

    public func createUser(_ createUserRequest: CreateUser) async throws -> String {
        guard let postgresUserStore else {
            throw LambdaDemoError.missingService(name: "postgresUserStore")
        }

        try await postgresUserStore.createUser(createUserRequest.toUser())

        guard let user = try await postgresUserStore.getUsers().first else {
            throw LambdaDemoError.unexpectedError(description: "Unexpected for Postgres not to return user.")
        }

        return "Inserted and Read User: \(user.firstName) \(user.lastName)"
    }

    public func getUser(id: String) async throws -> User? {
        guard let postgresUserStore else {
            throw LambdaDemoError.missingService(name: "postgresUserStore")
        }

        guard let uuid = UUID(uuidString: id) else {
            throw LambdaDemoError.unexpectedError(description: "Invalid uuid: \(id).")
        }
        return try await postgresUserStore.getUser(id: uuid)
    }

    public func getUsers() async throws -> [User] {
        guard let postgresUserStore else {
            throw LambdaDemoError.missingService(name: "postgresUserStore")
        }
        return try await postgresUserStore.getUsers()
    }

    public func updateUser(_ user: User) async throws -> User {
        guard let postgresUserStore else {
            throw LambdaDemoError.missingService(name: "postgresUserStore")
        }

        return try await postgresUserStore.updateUser(user)
    }

    public func deleteUser(_ user: User) async throws {
        guard let postgresUserStore else {
            throw LambdaDemoError.missingService(name: "postgresUserStore")
        }
        try await postgresUserStore.deleteUser(user)
    }

    
    //MARK: S3 Service

    public func uploadAndDownloadS3File() async throws -> String {
        guard let s3DataStore else {
            throw LambdaDemoError.missingService(name: "s3DataStore")
        }
        let string = "Hello World! This data was written/read from S3."
        guard let data = string.data(using: .utf8) else {
            fatalError("Unexpected not to convert to data.")
        }
        try await s3DataStore.uploadData(data, key: s3FileKey)
        guard let responseData = try await s3DataStore.getData(key: s3FileKey) else {
            throw LambdaDemoError.unexpectedError(description: "Couldn't find S3 file")
        }

        guard let result = String(data: responseData, encoding: .utf8) else {
            throw LambdaDemoError.unexpectedError(description: "Can't convert Data to string")
        }
        return result
    }

    public func uploadToS3(key: String, content: String) async throws {
        guard let s3DataStore else {
            throw LambdaDemoError.missingService(name: "s3DataStore")
        }
        guard let data = content.data(using: .utf8) else {
            throw LambdaDemoError.unexpectedError(description: "Failed to convert string to data")
        }
        try await s3DataStore.uploadData(data, key: key)
    }
    
    
    enum LambdaDemoError: LocalizedError {
        case missingService(name: String)
        case unexpectedError(description: String)
    }
    
}
