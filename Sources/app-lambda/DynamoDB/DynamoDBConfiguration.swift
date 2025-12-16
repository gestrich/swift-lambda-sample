//
//  DynamoDBConfiguration.swift
//  SwiftLambda
//
//  Created by Bill Gestrich on 12/6/25.
//

import Foundation

public struct DynamoDBConfiguration: Codable {
    public let tableName: String
    public let endpoint: String?

    public init(tableName: String, endpoint: String?) {
        self.tableName = tableName
        self.endpoint = endpoint
    }
}
