//
//  UpdateReminderRequest.swift
//  SwiftLambda
//
//  Created by Bill Gestrich on 12/6/25.
//

import Foundation

public struct UpdateReminderRequest: Codable, Sendable {
    public let name: String?
    public let details: String?
    public let dueDate: Date?
    public let isComplete: Bool?

    public init(name: String? = nil, details: String? = nil, dueDate: Date? = nil, isComplete: Bool? = nil) {
        self.name = name
        self.details = details
        self.dueDate = dueDate
        self.isComplete = isComplete
    }
}
