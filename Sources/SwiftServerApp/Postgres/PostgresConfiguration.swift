//
//  PostgresConfiguration.swift
//
//
//  Created by Bill Gestrich on 12/9/23.
//

import FluentKit
import FluentPostgresDriver
import FluentSQLiteDriver
import Foundation

public struct PostgresConfiguration: Codable {

    public var name: String
    public var identifier: String
    public var host: String
    public var port: Int
    public var tableName: String
    public var username: String
    public var userPassword: String
    /// When true, TLS is enabled (production/AWS RDS). When false, TLS is disabled (local development).
    public var enableTLS: Bool

    public init(name: String, identifier: String, host: String, port: Int, tableName: String, userName: String, userPassword: String, enableTLS: Bool) {
        self.name = name
        self.identifier = identifier
        self.host = host
        self.port = port
        self.tableName = tableName
        self.username = userName
        self.userPassword = userPassword
        self.enableTLS = enableTLS
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        identifier = try container.decode(String.self, forKey: .identifier)
        host = try container.decode(String.self, forKey: .host)
        port = try container.decode(Int.self, forKey: .port)
        tableName = try container.decode(String.self, forKey: .tableName)
        username = try container.decode(String.self, forKey: .username)
        userPassword = try container.decode(String.self, forKey: .userPassword)
        // Default to false (local development) if not present in JSON
        enableTLS = try container.decodeIfPresent(Bool.self, forKey: .enableTLS) ?? false
    }
}
