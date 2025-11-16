//
//  CreateUser.swift
//
//
//  Created by Bill Gestrich on 12/25/23.
//

import Foundation

public struct CreateUser: Codable {
    public var email: String
    public var password: String
    public var firstName: String
    public var lastName: String
    public var nickName: String
    public var phone: String
    public var slackID: String

    /// Failable initializer for event routing
    /// Returns nil if the JSON doesn't match the CreateUser structure
    public init?(from decoder: Decoder) {
        do {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.email = try container.decode(String.self, forKey: .email)
            self.password = try container.decode(String.self, forKey: .password)
            self.firstName = try container.decode(String.self, forKey: .firstName)
            self.lastName = try container.decode(String.self, forKey: .lastName)
            self.nickName = try container.decode(String.self, forKey: .nickName)
            self.phone = try container.decode(String.self, forKey: .phone)
            self.slackID = try container.decode(String.self, forKey: .slackID)
        } catch {
            return nil
        }
    }
}

extension CreateUser {
    func toUser() -> User {
        return User(email: email, password: password, firstName: firstName, lastName: lastName, nickName: nickName, phone: phone, slackID: slackID)
    }
}
