//
//  CreateReminderRequest.swift
//  SwiftLambda
//
//  Created by Bill Gestrich on 12/6/25.
//

import Foundation

public struct CreateReminderRequest: Codable, Sendable {
    public let name: String
    public let details: String?
    public let dueDate: Date?

    public init(name: String, details: String? = nil, dueDate: Date? = nil) {
        self.name = name
        self.details = details
        self.dueDate = dueDate
    }
}
