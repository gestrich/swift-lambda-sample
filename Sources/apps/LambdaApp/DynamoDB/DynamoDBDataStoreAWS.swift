//
//  DynamoDBDataStoreAWS.swift
//  SwiftLambda
//
//  Created by Bill Gestrich on 12/6/25.
//

import ClientService
import Foundation
import SotoDynamoDB

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

        // Build DynamoDB item with required attributes
        // AttributeValue types: .s (String), .bool (Boolean)
        var item: [String: DynamoDB.AttributeValue] = [
            "id": .s(id),
            "name": .s(request.name),
            "isComplete": .bool(false),
            "createdAt": .s(dateFormatter.string(from: now)),
            "updatedAt": .s(dateFormatter.string(from: now))
        ]

        // Add optional attributes only if provided
        // DynamoDB best practice: omit null values to reduce storage costs
        if let details = request.details {
            item["details"] = .s(details)
        }

        if let dueDate = request.dueDate {
            item["dueDate"] = .s(dateFormatter.string(from: dueDate))
        }

        // Write item to DynamoDB table
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
        // Use Scan operation to retrieve all items from the table
        // Note: Scan is expensive for large tables - consider using Query with indexes for production
        let scanRequest = DynamoDB.ScanInput(tableName: tableName)
        let response = try await dynamoDB.scan(scanRequest)

        guard let items = response.items else {
            return []
        }

        // Parse each DynamoDB item into a Reminder, filtering out any invalid items
        return try items.compactMap { try parseReminder(from: $0) }
    }

    public func updateReminder(id: String, request: UpdateReminderRequest) async throws -> Reminder {
        // Fetch existing reminder to preserve unmodified fields
        guard let existing = try await getReminder(id: id) else {
            throw DynamoDBError.recordNotFound
        }

        let now = Date()

        // Merge request fields with existing values (request takes precedence)
        let newName = request.name ?? existing.name
        let newDetails = request.details ?? existing.details
        let newDueDate = request.dueDate ?? existing.dueDate
        let newIsComplete = request.isComplete ?? existing.isComplete

        // Build DynamoDB item with required attributes
        // Note: Using PutItem instead of UpdateItem to replace entire record
        var item: [String: DynamoDB.AttributeValue] = [
            "id": .s(id),
            "name": .s(newName),
            "isComplete": .bool(newIsComplete),
            "createdAt": .s(dateFormatter.string(from: existing.createdAt)),  // Preserve original creation time
            "updatedAt": .s(dateFormatter.string(from: now))
        ]

        // Add optional attributes only if they have values
        // DynamoDB best practice: omit attributes rather than storing nulls
        if let details = newDetails {
            item["details"] = .s(details)
        }

        if let dueDate = newDueDate {
            item["dueDate"] = .s(dateFormatter.string(from: dueDate))
        }

        // Execute the put operation
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
        // Extract and validate required attributes using pattern matching
        // DynamoDB AttributeValue is an enum (.s for String, .bool for Boolean, etc.)
        // All required fields must exist and have the correct type, or parsing fails
        guard case .s(let id) = item["id"],
              case .s(let name) = item["name"],
              case .bool(let isComplete) = item["isComplete"],
              case .s(let createdAtStr) = item["createdAt"],
              case .s(let updatedAtStr) = item["updatedAt"],
              let createdAt = dateFormatter.date(from: createdAtStr),
              let updatedAt = dateFormatter.date(from: updatedAtStr) else {
            throw DynamoDBError.invalidItemFormat
        }

        // Parse optional attributes - these may not exist in the DynamoDB item
        var details: String? = nil
        if case .s(let detailsValue) = item["details"] {
            details = detailsValue
        }

        // Parse optional dueDate with ISO8601 format validation
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
