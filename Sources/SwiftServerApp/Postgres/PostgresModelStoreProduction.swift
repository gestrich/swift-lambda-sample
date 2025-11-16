//
//  PostgresModelStoreProduction.swift
//
//
//  Created by Bill Gestrich on 12/16/23.
//

import Foundation

public actor PostgresModelStoreProduction: PostgresModelStoreInterface {
    var modelStore: PostgresModelStoreInterface? = nil
    var modelStoreFactory: (() async throws -> PostgresModelStoreInterface?)

    public init(modelStoreFactory: @escaping () async throws -> PostgresModelStoreInterface?) {
        self.modelStoreFactory = modelStoreFactory
    }

    func getOrCreateModelStore () async throws -> PostgresModelStoreInterface? {
        if let modelStore {
            return modelStore
        } else {
            let result  = try await modelStoreFactory()
            modelStore = result
            return result
        }
    }

    public func getUser(id: UUID) async throws -> User? {
        guard let postgresStore = try await getOrCreateModelStore() else {
            throw PostgresModelStoreProductionError.databaseNotConfigured
        }
        return try await postgresStore.getUser(id: id)
    }

    public func getUsers() async throws -> [User] {
        guard let postgresStore = try await getOrCreateModelStore() else {
            throw PostgresModelStoreProductionError.databaseNotConfigured
        }
        return try await postgresStore.getUsers()
    }

    public func createUser(_ user: User) async throws {
        guard let postgresStore = try await getOrCreateModelStore() else {
            throw PostgresModelStoreProductionError.databaseNotConfigured
        }
        return try await postgresStore.createUser(user)
    }

    public func updateUser(_ user: User) async throws -> User {
        guard let postgresStore = try await getOrCreateModelStore() else {
            throw PostgresModelStoreProductionError.databaseNotConfigured
        }
        return try await postgresStore.updateUser(user)
    }

    public func deleteUser(_ user: User) async throws {
        guard let postgresStore = try await getOrCreateModelStore() else {
            throw PostgresModelStoreProductionError.databaseNotConfigured
        }
        return try await postgresStore.deleteUser(user)
    }

    public func wipeAndInitialize() async throws {
        guard let postgresStore = try await getOrCreateModelStore() else {
            throw PostgresModelStoreProductionError.databaseNotConfigured
        }
        try await postgresStore.wipeAndInitialize()
    }

    public func shutdown() async throws {
        guard let postgresStore = modelStore else {
            return
        }
        try await postgresStore.shutdown()
    }
}

enum PostgresModelStoreProductionError: LocalizedError {
    case databaseNotConfigured

    var errorDescription: String? {
        switch self {
        case .databaseNotConfigured:
            return "Database not configured - required environment variables (POSTGRES_HOST, POSTGRES_PORT, etc.) are missing"
        }
    }
}
