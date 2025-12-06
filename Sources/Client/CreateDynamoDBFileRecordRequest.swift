//
//  CreateDynamoDBFileRecordRequest.swift
//  SwiftLambda
//
//  Created by Bill Gestrich on 12/6/25.
//

import Foundation

public struct CreateDynamoDBFileRecordRequest: Codable, Sendable {
    public let fileName: String
    public let contentType: String
    public let data: String  // base64 encoded

    public init(fileName: String, contentType: String, data: String) {
        self.fileName = fileName
        self.contentType = contentType
        self.data = data
    }
}
