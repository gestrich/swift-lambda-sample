//
//  CreateUserRequest.swift
//  SwiftLambda
//
//  Created by Bill Gestrich on 11/23/25.
//

import Foundation

public struct CreateUserRequest: Codable {
    public let email: String
    public let password: String
    public let firstName: String
    public let lastName: String
    public let nickName: String
    public let phone: String
    public let slackID: String

    public init(email: String, password: String, firstName: String, lastName: String, nickName: String, phone: String, slackID: String) {
        self.email = email
        self.password = password
        self.firstName = firstName
        self.lastName = lastName
        self.nickName = nickName
        self.phone = phone
        self.slackID = slackID
    }
}
