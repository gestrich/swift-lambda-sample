//
//  DynamoDBDataStoreProduction.swift
//  SwiftLambda
//
//  Created by Bill Gestrich on 12/6/25.
//

import ClientService
import Foundation

public actor DynamoDBDataStoreProduction: DynamoDBDataStoreInterface, Sendable {

    private var dynamoDBStore: DynamoDBDataStoreInterface? = nil
    private let dynamoDBStoreFactory: () async throws -> DynamoDBDataStoreInterface

    public init(dynamoDBStoreFactory: @escaping () async throws -> DynamoDBDataStoreInterface) {
        self.dynamoDBStoreFactory = dynamoDBStoreFactory
    }

    private func getOrCreateStore() async throws -> DynamoDBDataStoreInterface {
        if let dynamoDBStore {
            return dynamoDBStore
        } else {
            let result = try await dynamoDBStoreFactory()
            dynamoDBStore = result
            return result
        }
    }

    public func createReminder(_ request: CreateReminderRequest) async throws -> Reminder {
        let store = try await getOrCreateStore()
        return try await store.createReminder(request)
    }

    public func getReminder(id: String) async throws -> Reminder? {
        let store = try await getOrCreateStore()
        return try await store.getReminder(id: id)
    }

    public func listReminders() async throws -> [Reminder] {
        let store = try await getOrCreateStore()
        return try await store.listReminders()
    }

    public func updateReminder(id: String, request: UpdateReminderRequest) async throws -> Reminder {
        let store = try await getOrCreateStore()
        return try await store.updateReminder(id: id, request: request)
    }

    public func deleteReminder(id: String) async throws {
        let store = try await getOrCreateStore()
        try await store.deleteReminder(id: id)
    }
}
