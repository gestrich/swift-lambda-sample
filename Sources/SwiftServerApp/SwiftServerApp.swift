//
//  SwiftServerApp.swift
//
//
//  Created by Bill Gestrich on 12/9/23.
//

import Foundation

public struct SwiftServerApp {
    
    let cloudDataStore: CloudDataStore?
    let userStore: UserStore?
    let s3FileKey = "hello-world.text"
    
    public init(cloudDataStore: CloudDataStore? = nil, userStore: UserStore?) {
        self.cloudDataStore = cloudDataStore
        self.userStore = userStore
    }
    
    
    //MARK: Database Service

    public func initializeDatabase() async throws {
        guard let userStore else {
            throw LambdaDemoError.missingService(name: "userDatabaseService")
        }
        //TODO: This should not delete the database contents.
        try await userStore.wipeAndInitialize()
    }

    public func resetDatabase() async throws {
        guard let userStore else {
            throw LambdaDemoError.missingService(name: "userDatabaseService")
        }

        try await userStore.wipeAndInitialize()
    }

    
    //MARK: User Service

    public func createUser(_ createUserRequest: CreateUser) async throws -> String {
        guard let userStore else {
            throw LambdaDemoError.missingService(name: "userDatabaseService")
        }

        try await userStore.createUser(createUserRequest.toUser())

        guard let user = try await userStore.getUsers().first else {
            throw LambdaDemoError.unexpectedError(description: "Unexpected for Postgres not to return user.")
        }
        
        return "Inserted and Read User: \(user.firstName) \(user.lastName)"
    }

    public func getUser(id: String) async throws -> User? {
        guard let userStore else {
            throw LambdaDemoError.missingService(name: "userDatabaseService")
        }

        guard let uuid = UUID(uuidString: id) else {
            throw LambdaDemoError.unexpectedError(description: "Invalid uuid: \(id).")
        }
        return try await userStore.getUser(id: uuid)
    }

    public func getUsers() async throws -> [User] {
        guard let userStore else {
            throw LambdaDemoError.missingService(name: "userDatabaseService")
        }
        return try await userStore.getUsers()
    }

    public func updateUser(_ user: User) async throws -> User {
        guard let userStore else {
            throw LambdaDemoError.missingService(name: "userDatabaseService")
        }

        return try await userStore.updateUser(user)
    }

    public func deleteUser(_ user: User) async throws {
        guard let userStore else {
            throw LambdaDemoError.missingService(name: "userDatabaseService")
        }
        try await userStore.deleteUser(user)
    }

    
    //MARK: S3 Service
    
    public func uploadAndDownloadS3File() async throws -> String {
        guard let cloudDataStore else {
            throw LambdaDemoError.missingService(name: "s3Service")
        }
        let string = "Hello World! This data was written/read from S3."
        guard let data = string.data(using: .utf8) else {
            fatalError("Unexpected not to convert to data.")
        }
        try await cloudDataStore.uploadData(data, key: s3FileKey)
        guard let responseData = try await cloudDataStore.getData(key: s3FileKey) else {
            throw LambdaDemoError.unexpectedError(description: "Couldn't find S3 file")
        }
        
        guard let result = String(data: responseData, encoding: .utf8) else {
            throw LambdaDemoError.unexpectedError(description: "Can't convert Data to string")
        }
        return result
    }
    
    
    enum LambdaDemoError: LocalizedError {
        case missingService(name: String)
        case unexpectedError(description: String)
    }
    
}
