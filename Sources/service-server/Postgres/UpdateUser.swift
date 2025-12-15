//
//  UpdateUser.swift
//  SwiftServerApp
//
//  DTO for partial user updates following REST API best practices
//  All fields are optional - only provided fields will be updated
//

import Foundation

public struct UpdateUser: Codable {
    public var email: String?
    public var password: String?
    public var firstName: String?
    public var lastName: String?
    public var nickName: String?
    public var phone: String?
    public var slackID: String?

    public init(
        email: String? = nil,
        password: String? = nil,
        firstName: String? = nil,
        lastName: String? = nil,
        nickName: String? = nil,
        phone: String? = nil,
        slackID: String? = nil
    ) {
        self.email = email
        self.password = password
        self.firstName = firstName
        self.lastName = lastName
        self.nickName = nickName
        self.phone = phone
        self.slackID = slackID
    }
}
