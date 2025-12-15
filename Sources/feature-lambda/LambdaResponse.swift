//
//  LambdaResponse.swift
//  SwiftLambda
//
//  Created for swift-aws-lambda-runtime 2.0 migration
//

import AWSLambdaEvents
import Foundation

/// Union type for different Lambda response types
/// This allows us to return different response types based on the event type
public enum LambdaResponse: Encodable {
    case apiGateway(APIGatewayResponse)
    case string(String)

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .apiGateway(let response):
            // Encode the APIGatewayResponse directly
            try response.encode(to: encoder)
        case .string(let string):
            // Encode as a single value
            var container = encoder.singleValueContainer()
            try container.encode(string)
        }
    }
}
