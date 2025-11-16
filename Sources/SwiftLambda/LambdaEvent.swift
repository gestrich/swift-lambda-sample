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
///
/// Uses failable initializers to attempt decoding each event type in order.
/// Returns nil if the JSON doesn't match any known event structure.
///
/// **Framework Integration:**
/// This initializer is NOT called directly by application code. Instead, it's automatically
/// invoked by the swift-aws-lambda-runtime framework:
///
/// 1. AWS Lambda Runtime sends JSON event data
/// 2. LambdaRuntime receives the raw event
/// 3. LambdaCodableAdapter (configured in @main) calls JSONDecoder().decode(LambdaEvent.self, from: eventData)
/// 4. JSONDecoder automatically calls this init(from:) method
/// 5. This method tries to decode as each event type until one succeeds
/// 6. The decoded LambdaEvent is passed to DynamicLambdaHandler.handle()
public enum LambdaEvent: Decodable {
    case apiGateway(APIGatewayRequest)
    case cloudWatchScheduled(CloudwatchEvent<CloudwatchDetails.Scheduled>)
    case directInvocation(DirectInvocationEvent)

    public init(from decoder: Decoder) throws {
        // Try to decode as API Gateway request first (most common)
        // Note: APIGatewayRequest is from AWSLambdaEvents, so we use try? since we can't add failable init
        if let apiGatewayRequest = try? APIGatewayRequest(from: decoder) {
            self = .apiGateway(apiGatewayRequest)
            return
        }

        // Try to decode as CloudWatch scheduled event
        // Note: CloudwatchEvent is from AWSLambdaEvents, so we use try? since we can't add failable init
        if let scheduledEvent = try? CloudwatchEvent<CloudwatchDetails.Scheduled>(from: decoder) {
            self = .cloudWatchScheduled(scheduledEvent)
            return
        }

        // Try to decode as direct invocation (CreateUser, etc.)
        // Uses our custom failable initializer
        if let directInvocation = DirectInvocationEvent(from: decoder) {
            self = .directInvocation(directInvocation)
            return
        }

        // If none matched, throw an error
        throw DecodingError.dataCorrupted(
            DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Unable to decode event into any known Lambda event type (APIGateway, CloudWatch, or DirectInvocation)"
            )
        )
    }
}
