//
//  DynamoDBDataStoreAWS.swift
//  SwiftLambda
//
//  Created by Bill Gestrich on 12/6/25.
//

import Foundation
import SotoDynamoDB
import ClientService

public final class DynamoDBDataStoreAWS: DynamoDBDataStoreInterface, @unchecked Sendable {

    private let dynamoDB: SotoDynamoDB.DynamoDB
    private let tableName: String
    private let dateFormatter = ISO8601DateFormatter()

    public init(awsClient: AWSClient, tableName: String, endpoint: String? = nil) {
        if let endpoint {
            self.dynamoDB = SotoDynamoDB.DynamoDB(client: awsClient, region: .useast1, endpoint: endpoint)
        } else {
            self.dynamoDB = SotoDynamoDB.DynamoDB(client: awsClient)
        }
        self.tableName = tableName
    }

    public func createReminder(_ request: CreateReminderRequest) async throws -> Reminder {
        let id = UUID().uuidString
        let now = Date()

        var item: [String: DynamoDB.AttributeValue] = [
            "id": .s(id),
            "name": .s(request.name),
            "isComplete": .bool(false),
            "createdAt": .s(dateFormatter.string(from: now)),
            "updatedAt": .s(dateFormatter.string(from: now))
        ]

        if let details = request.details {
            item["details"] = .s(details)
        }

        if let dueDate = request.dueDate {
            item["dueDate"] = .s(dateFormatter.string(from: dueDate))
        }

        let putRequest = DynamoDB.PutItemInput(item: item, tableName: tableName)
        _ = try await dynamoDB.putItem(putRequest)

        return Reminder(
            id: id,
            name: request.name,
            details: request.details,
            dueDate: request.dueDate,
            isComplete: false,
            createdAt: now,
            updatedAt: now
        )
    }

    public func getReminder(id: String) async throws -> Reminder? {
        let key: [String: DynamoDB.AttributeValue] = ["id": .s(id)]
        let getRequest = DynamoDB.GetItemInput(key: key, tableName: tableName)
        let response = try await dynamoDB.getItem(getRequest)

        guard let item = response.item else {
            return nil
        }

        return try parseReminder(from: item)
    }

    public func listReminders() async throws -> [Reminder] {
        let scanRequest = DynamoDB.ScanInput(tableName: tableName)
        let response = try await dynamoDB.scan(scanRequest)

        guard let items = response.items else {
            return []
        }

        return try items.compactMap { try parseReminder(from: $0) }
    }

    public func updateReminder(id: String, request: UpdateReminderRequest) async throws -> Reminder {
        guard let existing = try await getReminder(id: id) else {
            throw DynamoDBError.recordNotFound
        }

        let now = Date()
        let newName = request.name ?? existing.name
        let newDetails = request.details ?? existing.details
        let newDueDate = request.dueDate ?? existing.dueDate
        let newIsComplete = request.isComplete ?? existing.isComplete

        var item: [String: DynamoDB.AttributeValue] = [
            "id": .s(id),
            "name": .s(newName),
            "isComplete": .bool(newIsComplete),
            "createdAt": .s(dateFormatter.string(from: existing.createdAt)),
            "updatedAt": .s(dateFormatter.string(from: now))
        ]

        if let details = newDetails {
            item["details"] = .s(details)
        }

        if let dueDate = newDueDate {
            item["dueDate"] = .s(dateFormatter.string(from: dueDate))
        }

        let putRequest = DynamoDB.PutItemInput(item: item, tableName: tableName)
        _ = try await dynamoDB.putItem(putRequest)

        return Reminder(
            id: id,
            name: newName,
            details: newDetails,
            dueDate: newDueDate,
            isComplete: newIsComplete,
            createdAt: existing.createdAt,
            updatedAt: now
        )
    }

    public func deleteReminder(id: String) async throws {
        let key: [String: DynamoDB.AttributeValue] = ["id": .s(id)]
        let deleteRequest = DynamoDB.DeleteItemInput(key: key, tableName: tableName)
        _ = try await dynamoDB.deleteItem(deleteRequest)
    }

    private func parseReminder(from item: [String: DynamoDB.AttributeValue]) throws -> Reminder {
        guard case .s(let id) = item["id"],
              case .s(let name) = item["name"],
              case .bool(let isComplete) = item["isComplete"],
              case .s(let createdAtStr) = item["createdAt"],
              case .s(let updatedAtStr) = item["updatedAt"],
              let createdAt = dateFormatter.date(from: createdAtStr),
              let updatedAt = dateFormatter.date(from: updatedAtStr) else {
            throw DynamoDBError.invalidItemFormat
        }

        var details: String? = nil
        if case .s(let detailsValue) = item["details"] {
            details = detailsValue
        }

        var dueDate: Date? = nil
        if case .s(let dueDateStr) = item["dueDate"],
           let parsedDueDate = dateFormatter.date(from: dueDateStr) {
            dueDate = parsedDueDate
        }

        return Reminder(
            id: id,
            name: name,
            details: details,
            dueDate: dueDate,
            isComplete: isComplete,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

public enum DynamoDBError: LocalizedError {
    case recordNotFound
    case invalidItemFormat

    public var errorDescription: String? {
        switch self {
        case .recordNotFound:
            return "Reminder not found"
        case .invalidItemFormat:
            return "Invalid DynamoDB item format"
        }
    }
}
