//
//  SwiftServerApp.swift
//
//
//  Created by Bill Gestrich on 12/9/23.
//

import Foundation
import d_sdk_client

public struct SwiftServerApp {

    let s3DataStore: S3DataStoreInterface?
    let postgresModelStore: PostgresModelStoreInterface?
    let dynamoDBDataStore: DynamoDBDataStoreInterface?
    let s3FileKey = "hello-world.text"

    public init(s3DataStore: S3DataStoreInterface? = nil, postgresModelStore: PostgresModelStoreInterface?, dynamoDBDataStore: DynamoDBDataStoreInterface? = nil) {
        self.s3DataStore = s3DataStore
        self.postgresModelStore = postgresModelStore
        self.dynamoDBDataStore = dynamoDBDataStore
    }
    
    
    //MARK: Database Service

    public func initializeDatabase() async throws {
        guard let postgresModelStore else {
            throw LambdaDemoError.missingService(name: "postgresModelStore")
        }
        //TODO: This should not delete the database contents.
        try await postgresModelStore.wipeAndInitialize()
    }

    public func resetDatabase() async throws {
        guard let postgresModelStore else {
            throw LambdaDemoError.missingService(name: "postgresModelStore")
        }

        try await postgresModelStore.wipeAndInitialize()
    }

    
    //MARK: User Service

    public func createUser(_ createUserRequest: CreateUser) async throws -> User {
        guard let postgresModelStore else {
            throw LambdaDemoError.missingService(name: "postgresModelStore")
        }

        try await postgresModelStore.createUser(createUserRequest.toUser())

        guard let user = try await postgresModelStore.getUsers().first else {
            throw LambdaDemoError.unexpectedError(description: "Unexpected for Postgres not to return user.")
        }

        return user
    }

    public func getUser(id: String) async throws -> User? {
        guard let postgresModelStore else {
            throw LambdaDemoError.missingService(name: "postgresModelStore")
        }

        guard let uuid = UUID(uuidString: id) else {
            throw LambdaDemoError.unexpectedError(description: "Invalid uuid: \(id).")
        }
        return try await postgresModelStore.getUser(id: uuid)
    }

    public func getUsers() async throws -> [User] {
        guard let postgresModelStore else {
            throw LambdaDemoError.missingService(name: "postgresModelStore")
        }
        return try await postgresModelStore.getUsers()
    }

    public func updateUser(_ user: User) async throws -> User {
        guard let postgresModelStore else {
            throw LambdaDemoError.missingService(name: "postgresModelStore")
        }

        return try await postgresModelStore.updateUser(user)
    }

    public func deleteUser(_ user: User) async throws {
        guard let postgresModelStore else {
            throw LambdaDemoError.missingService(name: "postgresModelStore")
        }
        try await postgresModelStore.deleteUser(user)
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

    public func uploadS3File(key: String, data: Data) async throws {
        guard let s3DataStore else {
            throw LambdaDemoError.missingService(name: "s3DataStore")
        }
        try await s3DataStore.uploadData(data, key: key)
    }

    public func downloadS3File(key: String) async throws -> Data? {
        guard let s3DataStore else {
            throw LambdaDemoError.missingService(name: "s3DataStore")
        }
        return try await s3DataStore.getData(key: key)
    }

    public func listS3Files() async throws -> [String] {
        guard let s3DataStore else {
            throw LambdaDemoError.missingService(name: "s3DataStore")
        }
        return try await s3DataStore.listFiles()
    }

    public func deleteS3File(key: String) async throws {
        guard let s3DataStore else {
            throw LambdaDemoError.missingService(name: "s3DataStore")
        }
        try await s3DataStore.deleteFile(key: key)
    }


    //MARK: DynamoDB Reminders Service

    public func createReminder(_ request: CreateReminderRequest) async throws -> Reminder {
        guard let dynamoDBDataStore else {
            throw LambdaDemoError.missingService(name: "dynamoDBDataStore")
        }
        return try await dynamoDBDataStore.createReminder(request)
    }

    public func getReminder(id: String) async throws -> Reminder? {
        guard let dynamoDBDataStore else {
            throw LambdaDemoError.missingService(name: "dynamoDBDataStore")
        }
        return try await dynamoDBDataStore.getReminder(id: id)
    }

    public func listReminders() async throws -> [Reminder] {
        guard let dynamoDBDataStore else {
            throw LambdaDemoError.missingService(name: "dynamoDBDataStore")
        }
        return try await dynamoDBDataStore.listReminders()
    }

    public func updateReminder(id: String, request: UpdateReminderRequest) async throws -> Reminder {
        guard let dynamoDBDataStore else {
            throw LambdaDemoError.missingService(name: "dynamoDBDataStore")
        }
        return try await dynamoDBDataStore.updateReminder(id: id, request: request)
    }

    public func deleteReminder(id: String) async throws {
        guard let dynamoDBDataStore else {
            throw LambdaDemoError.missingService(name: "dynamoDBDataStore")
        }
        try await dynamoDBDataStore.deleteReminder(id: id)
    }


    enum LambdaDemoError: LocalizedError {
        case missingService(name: String)
        case unexpectedError(description: String)
    }

}
