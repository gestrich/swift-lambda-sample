//
//  PostgresUserStoreProduction.swift
//
//
//  Created by Bill Gestrich on 12/16/23.
//

import Foundation

public actor PostgresUserStoreProduction: PostgresUserStoreInterface {
    var userStore: PostgresUserStoreInterface? = nil
    var userStoreFactory: (() async throws -> PostgresUserStoreInterface?)

    public init(userStoreFactory: @escaping () async throws -> PostgresUserStoreInterface?) {
        self.userStoreFactory = userStoreFactory
    }

    func getOrCreateUserStore () async throws -> PostgresUserStoreInterface? {
        if let userStore {
            return userStore
        } else {
            let result  = try await userStoreFactory()
            userStore = result
            return result
        }
    }

    public func getUser(id: UUID) async throws -> User? {
        guard let postgresStore = try await getOrCreateUserStore() else {
            throw UserStoreProductionError.databaseNotConfigured
        }
        return try await postgresStore.getUser(id: id)
    }

    public func getUsers() async throws -> [User] {
        guard let postgresStore = try await getOrCreateUserStore() else {
            throw UserStoreProductionError.databaseNotConfigured
        }
        return try await postgresStore.getUsers()
    }

    public func createUser(_ user: User) async throws {
        guard let postgresStore = try await getOrCreateUserStore() else {
            throw UserStoreProductionError.databaseNotConfigured
        }
        return try await postgresStore.createUser(user)
    }

    public func updateUser(_ user: User) async throws -> User {
        guard let postgresStore = try await getOrCreateUserStore() else {
            throw UserStoreProductionError.databaseNotConfigured
        }
        return try await postgresStore.updateUser(user)
    }

    public func deleteUser(_ user: User) async throws {
        guard let postgresStore = try await getOrCreateUserStore() else {
            throw UserStoreProductionError.databaseNotConfigured
        }
        return try await postgresStore.deleteUser(user)
    }

    public func wipeAndInitialize() async throws {
        guard let postgresStore = try await getOrCreateUserStore() else {
            throw UserStoreProductionError.databaseNotConfigured
        }
        try await postgresStore.wipeAndInitialize()
    }
    
    public func shutdown() async throws {
        guard let postgresStore = userStore else {
            return
        }
        try await postgresStore.shutdown()
    }
}

enum UserStoreProductionError: LocalizedError {
    case databaseNotConfigured

    var errorDescription: String? {
        switch self {
        case .databaseNotConfigured:
            return "Database not configured - required environment variables (POSTGRES_HOST, POSTGRES_PORT, etc.) are missing"
        }
    }
}
