//
//  User.swift
//  
//
//  Created by Bill Gestrich on 12/9/23.
//

import FluentKit
import Foundation

final public class User: Model, Equatable {
    public static let schema = "user_schema" //"user" would conflict with reserved table name.
    
    @ID(key: .id)
    public var id: UUID?
    
    @Field(key: "email")
    public var email: String
    
    //Don't actually do this - shouldn't store user secrets in plain text.
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
    
    public init(){
        
    }
    
    public init(email: String, password: String, firstName: String, lastName: String, nickName: String, phone: String, slackID: String){
        self.email = email
        self.password = password
        self.firstName = firstName
        self.lastName = lastName
        self.nickName = nickName
        self.phone = phone
        self.slackID = slackID
    }
    
    //MARK: Equatable
    
    public static func == (lhs: User, rhs: User) -> Bool {
        return lhs.id == rhs.id
    }
}

struct CreatePostgresUser: AsyncMigration {
    func prepare(on database: Database) async throws  {
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
