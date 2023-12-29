//
//  UserStoreProduction.swift
//
//
//  Created by Bill Gestrich on 12/16/23.
//

import Foundation

public actor UserStoreProduction: UserStore {
    var userStore: UserStore? = nil
    var userStoreFactory: (() async throws -> UserStore)

    public init(userStoreFactory: @escaping () async throws -> UserStore) {
        self.userStoreFactory = userStoreFactory
    }

    func getOrCreateUserStore () async throws -> UserStore {
        if let userStore {
            return userStore
        } else {
            let result  = try await userStoreFactory()
            userStore = result
            return result
        }
    }

    public func getUser(id: UUID) async throws -> User? {
        let postgresStore = try await getOrCreateUserStore()
        return try await postgresStore.getUser(id: id)
    }

    public func getUsers() async throws -> [User] {
        let postgresStore = try await getOrCreateUserStore()
        return try await postgresStore.getUsers()
    }
    
    public func createUser(_ user: User) async throws {
        let postgresStore = try await getOrCreateUserStore()
        return try await postgresStore.createUser(user)
    }
    
    public func updateUser(_ user: User) async throws -> User {
        let postgresStore = try await getOrCreateUserStore()
        return try await postgresStore.updateUser(user)
    }
    
    public func deleteUser(_ user: User) async throws {
        let postgresStore = try await getOrCreateUserStore()
        return try await postgresStore.deleteUser(user)
    }
    
    public func wipeAndInitialize() async throws {
        let postgresStore = try await getOrCreateUserStore()
        try await postgresStore.wipeAndInitialize()
    }
    
    public func shutdown() async throws {
        guard let postgresStore = userStore else {
            return
        }
        try await postgresStore.shutdown()
    }
}
