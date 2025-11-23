//
//  APIGatewayRequestWrapper.swift
//  SwiftLambda
//
//  Created by Bill Gestrich on 11/23/25.
//

import Foundation

/// Models for wrapping/unwrapping API Gateway requests and responses
/// Used when testing Lambda locally (without API Gateway in front)

// MARK: - API Gateway Request Wrapper

/// Wraps HTTP requests in API Gateway request format for local Lambda testing
public struct APIGatewayRequestWrapper: Codable {
    public let resource: String
    public let path: String
    public let httpMethod: String
    public let headers: [String: String]
    public let multiValueHeaders: [String: [String]]
    public let requestContext: RequestContext
    public let body: String?
    public let isBase64Encoded: Bool

    public struct RequestContext: Codable {
        public let resourceId: String
        public let apiId: String
        public let resourcePath: String
        public let httpMethod: String
        public let requestId: String
        public let accountId: String
        public let stage: String
        public let identity: Identity
        public let path: String

        public struct Identity: Codable {
            public let sourceIp: String

            public init(sourceIp: String = "127.0.0.1") {
                self.sourceIp = sourceIp
            }
        }

        public init(
            resourceId: String = "test",
            apiId: String = "test",
            resourcePath: String,
            httpMethod: String,
            requestId: String = "test",
            accountId: String = "123456789012",
            stage: String = "local",
            identity: Identity = Identity(),
            path: String
        ) {
            self.resourceId = resourceId
            self.apiId = apiId
            self.resourcePath = resourcePath
            self.httpMethod = httpMethod
            self.requestId = requestId
            self.accountId = accountId
            self.stage = stage
            self.identity = identity
            self.path = path
        }
    }

    public init(
        resource: String,
        path: String,
        httpMethod: String,
        headers: [String: String] = [:],
        body: String? = nil
    ) {
        self.resource = resource
        self.path = path
        self.httpMethod = httpMethod
        self.headers = headers
        self.multiValueHeaders = [:]
        self.requestContext = RequestContext(
            resourcePath: resource,
            httpMethod: httpMethod,
            path: path
        )
        self.body = body
        self.isBase64Encoded = false
    }
}

// MARK: - API Gateway Response Wrapper

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
