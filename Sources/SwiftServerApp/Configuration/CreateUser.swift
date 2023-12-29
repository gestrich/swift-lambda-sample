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
}

extension CreateUser {
    func toUser() -> User {
        return User(email: email, password: password, firstName: firstName, lastName: lastName, nickName: nickName, phone: phone, slackID: slackID)
    }
}
