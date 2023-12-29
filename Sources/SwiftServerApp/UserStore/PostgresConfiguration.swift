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
    
    public init(name: String, identifier: String, host: String, port: Int, tableName: String, userName: String, userPassword: String){
        self.name = name
        self.identifier = identifier
        self.host = host
        self.port = port
        self.tableName = tableName
        self.username = userName
        self.userPassword = userPassword
    }
    
}
