//
//  LambdaEvent.swift
//  SwiftLambda
//
//  Union type for handling multiple Lambda event sources
//

import AWSLambdaEvents
import Foundation
import SwiftServerApp

/// Union type that can represent multiple Lambda event sources
public enum LambdaEvent: Decodable {
    case apiGateway(APIGatewayRequest)
    case cloudWatchScheduled(CloudwatchEvent<CloudwatchDetails.Scheduled>)
    case directCreateUser(CreateUser)

    public init(from decoder: Decoder) throws {
        // Try to decode as API Gateway request first (most common)
        if let apiGatewayRequest = try? APIGatewayRequest(from: decoder) {
            self = .apiGateway(apiGatewayRequest)
            return
        }

        // Try to decode as CloudWatch scheduled event
        if let scheduledEvent = try? CloudwatchEvent<CloudwatchDetails.Scheduled>(from: decoder) {
            self = .cloudWatchScheduled(scheduledEvent)
            return
        }

        // Try to decode as direct CreateUser invocation
        if let createUser = try? CreateUser(from: decoder) {
            self = .directCreateUser(createUser)
            return
        }

        // If none matched, throw an error
        throw DecodingError.dataCorrupted(
            DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Unable to decode event into any known Lambda event type (APIGateway, CloudWatch, or CreateUser)"
            )
        )
    }
}
