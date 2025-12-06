//
//  DynamoDBDataStoreProduction.swift
//  SwiftLambda
//
//  Created by Bill Gestrich on 12/6/25.
//

import Foundation
import Client

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

    public func createDynamoDBFileRecord(_ request: CreateDynamoDBFileRecordRequest) async throws -> DynamoDBFileRecord {
        let store = try await getOrCreateStore()
        return try await store.createDynamoDBFileRecord(request)
    }

    public func getDynamoDBFileRecord(id: String) async throws -> DynamoDBFileRecord? {
        let store = try await getOrCreateStore()
        return try await store.getDynamoDBFileRecord(id: id)
    }

    public func listDynamoDBFileRecords() async throws -> [DynamoDBFileRecord] {
        let store = try await getOrCreateStore()
        return try await store.listDynamoDBFileRecords()
    }

    public func updateDynamoDBFileRecord(id: String, request: UpdateDynamoDBFileRecordRequest) async throws -> DynamoDBFileRecord {
        let store = try await getOrCreateStore()
        return try await store.updateDynamoDBFileRecord(id: id, request: request)
    }

    public func deleteDynamoDBFileRecord(id: String) async throws {
        let store = try await getOrCreateStore()
        try await store.deleteDynamoDBFileRecord(id: id)
    }
}
