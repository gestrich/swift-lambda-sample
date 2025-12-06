//
//  DynamoDBDataStoreInterface.swift
//  SwiftLambda
//
//  Created by Bill Gestrich on 12/6/25.
//

import Foundation
import Client

public protocol DynamoDBDataStoreInterface: Sendable {
    func createDynamoDBFileRecord(_ request: CreateDynamoDBFileRecordRequest) async throws -> DynamoDBFileRecord
    func getDynamoDBFileRecord(id: String) async throws -> DynamoDBFileRecord?
    func listDynamoDBFileRecords() async throws -> [DynamoDBFileRecord]
    func updateDynamoDBFileRecord(id: String, request: UpdateDynamoDBFileRecordRequest) async throws -> DynamoDBFileRecord
    func deleteDynamoDBFileRecord(id: String) async throws
}
