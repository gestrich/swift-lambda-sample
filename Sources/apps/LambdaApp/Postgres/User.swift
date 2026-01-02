//
//  User.swift
//  
//
//  Created by Bill Gestrich on 12/9/23.
//

import FluentKit
import Foundation

final public class User: Model, Equatable, @unchecked Sendable {
    public static let schema = "user_schema" // "user" would conflict with reserved table name.

    @ID(key: .id)
    public var id: UUID?

    @Field(key: "email")
    public var email: String

    // Don't actually do this - shouldn't store user secrets in plain text.
    @Field(key: "password")
    public var password: String

    @Field(key: "firstName")
    public var firstName: String

    @Field(key: "lastName")
    public var lastName: String

    @Field(key: "nickName")
    public var nickName: String

    @Field(key: "phone")
    public var phone: String

    @Field(key: "slackID")
    public var slackID: String

    public init() {

    }

    public init(email: String, password: String, firstName: String, lastName: String, nickName: String, phone: String, slackID: String) {
        self.email = email
        self.password = password
        self.firstName = firstName
        self.lastName = lastName
        self.nickName = nickName
        self.phone = phone
        self.slackID = slackID
    }

    // MARK: Equatable

    public static func == (lhs: User, rhs: User) -> Bool {
        return lhs.id == rhs.id
    }
}

// MARK: - Request Application

extension User {
    /// Apply CreateUser request (for POST/create operations)
    /// Updates all fields from the request
    public func applyCreateUserRequest(_ createUser: CreateUser) {
        email = createUser.email
        password = createUser.password
        firstName = createUser.firstName
        lastName = createUser.lastName
        nickName = createUser.nickName
        phone = createUser.phone
        slackID = createUser.slackID
    }

    /// Apply UpdateUser request (for PUT/update operations)
    /// Only updates fields that are provided (non-nil)
    /// This implements PATCH semantics for partial updates
    public func applyUpdateUserRequest(_ updateUser: UpdateUser) {
        if let email = updateUser.email {
            self.email = email
        }

        // Only update password if provided and not empty
        // Empty passwords should not overwrite existing passwords
        if let password = updateUser.password, !password.isEmpty {
            self.password = password
        }

        if let firstName = updateUser.firstName {
            self.firstName = firstName
        }

        if let lastName = updateUser.lastName {
            self.lastName = lastName
        }

        if let nickName = updateUser.nickName {
            self.nickName = nickName
        }

        if let phone = updateUser.phone {
            self.phone = phone
        }

        if let slackID = updateUser.slackID {
            self.slackID = slackID
        }
    }
}

struct CreatePostgresUser: AsyncMigration {
    func prepare(on database: Database) async throws {
        return try await database.schema(User.schema)
            .id()
            .field("email", .string, .required)
            .unique(on: "email")
            .field("password", .string, .required)
            .field("firstName", .string, .required)
            .field("lastName", .string, .required)
            .field("nickName", .string, .required)
            .field("phone", .string, .required)
            .unique(on: "phone")
            .field("slackID", .string, .required)
            .create()
    }

    func revert(on database: Database) async throws {
        return try await database.schema(User.schema).delete()
    }
}
