//
//  DynamoDBDataStoreAWS.swift
//  SwiftLambda
//
//  Created by Bill Gestrich on 12/6/25.
//

import Foundation
import SotoDynamoDB
import Client

public final class DynamoDBDataStoreAWS: DynamoDBDataStoreInterface, @unchecked Sendable {

    private let dynamoDB: SotoDynamoDB.DynamoDB
    private let tableName: String

    public init(awsClient: AWSClient, tableName: String, endpoint: String? = nil) {
        if let endpoint {
            self.dynamoDB = SotoDynamoDB.DynamoDB(client: awsClient, region: .useast1, endpoint: endpoint)
        } else {
            self.dynamoDB = SotoDynamoDB.DynamoDB(client: awsClient)
        }
        self.tableName = tableName
    }

    public func createDynamoDBFileRecord(_ request: CreateDynamoDBFileRecordRequest) async throws -> DynamoDBFileRecord {
        let id = UUID().uuidString
        let now = Date()

        guard let fileData = Data(base64Encoded: request.data) else {
            throw DynamoDBError.invalidBase64Data
        }

        let item: [String: DynamoDB.AttributeValue] = [
            "id": .s(id),
            "fileName": .s(request.fileName),
            "fileSize": .n(String(fileData.count)),
            "contentType": .s(request.contentType),
            "data": .s(request.data),
            "createdAt": .s(ISO8601DateFormatter().string(from: now)),
            "updatedAt": .s(ISO8601DateFormatter().string(from: now))
        ]

        let putRequest = DynamoDB.PutItemInput(item: item, tableName: tableName)
        _ = try await dynamoDB.putItem(putRequest)

        return DynamoDBFileRecord(
            id: id,
            fileName: request.fileName,
            fileSize: fileData.count,
            contentType: request.contentType,
            data: request.data,
            createdAt: now,
            updatedAt: now
        )
    }

    public func getDynamoDBFileRecord(id: String) async throws -> DynamoDBFileRecord? {
        let key: [String: DynamoDB.AttributeValue] = ["id": .s(id)]
        let getRequest = DynamoDB.GetItemInput(key: key, tableName: tableName)
        let response = try await dynamoDB.getItem(getRequest)

        guard let item = response.item else {
            return nil
        }

        return try parseDynamoDBFileRecord(from: item)
    }

    public func listDynamoDBFileRecords() async throws -> [DynamoDBFileRecord] {
        let scanRequest = DynamoDB.ScanInput(tableName: tableName)
        let response = try await dynamoDB.scan(scanRequest)

        guard let items = response.items else {
            return []
        }

        return try items.compactMap { try parseDynamoDBFileRecord(from: $0) }
    }

    public func updateDynamoDBFileRecord(id: String, request: UpdateDynamoDBFileRecordRequest) async throws -> DynamoDBFileRecord {
        guard let existing = try await getDynamoDBFileRecord(id: id) else {
            throw DynamoDBError.recordNotFound
        }

        let now = Date()
        let newFileName = request.fileName ?? existing.fileName
        let newContentType = request.contentType ?? existing.contentType
        let newData = request.data ?? existing.data

        var newFileSize = existing.fileSize
        if let newDataString = request.data, let fileData = Data(base64Encoded: newDataString) {
            newFileSize = fileData.count
        }

        let item: [String: DynamoDB.AttributeValue] = [
            "id": .s(id),
            "fileName": .s(newFileName),
            "fileSize": .n(String(newFileSize)),
            "contentType": .s(newContentType),
            "data": .s(newData),
            "createdAt": .s(ISO8601DateFormatter().string(from: existing.createdAt)),
            "updatedAt": .s(ISO8601DateFormatter().string(from: now))
        ]

        let putRequest = DynamoDB.PutItemInput(item: item, tableName: tableName)
        _ = try await dynamoDB.putItem(putRequest)

        return DynamoDBFileRecord(
            id: id,
            fileName: newFileName,
            fileSize: newFileSize,
            contentType: newContentType,
            data: newData,
            createdAt: existing.createdAt,
            updatedAt: now
        )
    }

    public func deleteDynamoDBFileRecord(id: String) async throws {
        let key: [String: DynamoDB.AttributeValue] = ["id": .s(id)]
        let deleteRequest = DynamoDB.DeleteItemInput(key: key, tableName: tableName)
        _ = try await dynamoDB.deleteItem(deleteRequest)
    }

    private func parseDynamoDBFileRecord(from item: [String: DynamoDB.AttributeValue]) throws -> DynamoDBFileRecord {
        guard case .s(let id) = item["id"],
              case .s(let fileName) = item["fileName"],
              case .n(let fileSizeStr) = item["fileSize"],
              case .s(let contentType) = item["contentType"],
              case .s(let data) = item["data"],
              case .s(let createdAtStr) = item["createdAt"],
              case .s(let updatedAtStr) = item["updatedAt"],
              let fileSize = Int(fileSizeStr),
              let createdAt = ISO8601DateFormatter().date(from: createdAtStr),
              let updatedAt = ISO8601DateFormatter().date(from: updatedAtStr) else {
            throw DynamoDBError.invalidItemFormat
        }

        return DynamoDBFileRecord(
            id: id,
            fileName: fileName,
            fileSize: fileSize,
            contentType: contentType,
            data: data,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

public enum DynamoDBError: LocalizedError {
    case invalidBase64Data
    case recordNotFound
    case invalidItemFormat

    public var errorDescription: String? {
        switch self {
        case .invalidBase64Data:
            return "Invalid base64 encoded data"
        case .recordNotFound:
            return "File record not found"
        case .invalidItemFormat:
            return "Invalid DynamoDB item format"
        }
    }
}
