//
//  APIGatewayResponseWrapper.swift
//  SwiftLambda
//
//  Created by Bill Gestrich on 12/2/25.
//

import Foundation

/// Unwraps API Gateway response format from local Lambda
public struct APIGatewayResponseWrapper: Codable {
    public let statusCode: Int
    public let body: String
    public let headers: [String: String]?
    public let isBase64Encoded: Bool?

    public init(statusCode: Int, body: String, headers: [String: String]? = nil, isBase64Encoded: Bool? = nil) {
        self.statusCode = statusCode
        self.body = body
        self.headers = headers
        self.isBase64Encoded = isBase64Encoded
    }
}
