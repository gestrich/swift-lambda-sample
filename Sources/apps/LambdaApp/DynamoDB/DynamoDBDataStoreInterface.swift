//
//  DynamoDBDataStoreInterface.swift
//  SwiftLambda
//
//  Created by Bill Gestrich on 12/6/25.
//

import ClientService
import Foundation

public protocol DynamoDBDataStoreInterface: Sendable {
    func createReminder(_ request: CreateReminderRequest) async throws -> Reminder
    func getReminder(id: String) async throws -> Reminder?
    func listReminders() async throws -> [Reminder]
    func updateReminder(id: String, request: UpdateReminderRequest) async throws -> Reminder
    func deleteReminder(id: String) async throws
}
