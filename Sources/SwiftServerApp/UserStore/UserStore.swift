//
//  UserStore.swift
//
//
//  Created by Bill Gestrich on 12/16/23.
//

import Foundation

public protocol UserStore {
    func getUser(id: UUID) async throws -> User?
    func getUsers() async throws -> [User]
    func createUser(_ user: User) async throws
    func updateUser(_ user: User) async throws -> User
    func deleteUser(_ user : User) async throws
    func wipeAndInitialize() async throws
    func shutdown() async throws
}
