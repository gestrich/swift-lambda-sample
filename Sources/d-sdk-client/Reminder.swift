//
//  Reminder.swift
//  SwiftLambda
//
//  Created by Bill Gestrich on 12/6/25.
//

import Foundation

public struct Reminder: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let details: String?
    public let dueDate: Date?
    public let isComplete: Bool
    public let createdAt: Date
    public let updatedAt: Date

    public init(id: String, name: String, details: String?, dueDate: Date?, isComplete: Bool, createdAt: Date, updatedAt: Date) {
        self.id = id
        self.name = name
        self.details = details
        self.dueDate = dueDate
        self.isComplete = isComplete
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
