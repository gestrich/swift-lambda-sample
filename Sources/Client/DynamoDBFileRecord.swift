//
//  DynamoDBFileRecord.swift
//  SwiftLambda
//
//  Created by Bill Gestrich on 12/6/25.
//

import Foundation

public struct DynamoDBFileRecord: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let fileName: String
    public let fileSize: Int
    public let contentType: String
    public let data: String  // base64 encoded
    public let createdAt: Date
    public let updatedAt: Date

    public init(id: String, fileName: String, fileSize: Int, contentType: String, data: String, createdAt: Date, updatedAt: Date) {
        self.id = id
        self.fileName = fileName
        self.fileSize = fileSize
        self.contentType = contentType
        self.data = data
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
