//
//  LambdaHandler.swift
//
//
//  Created by Bill Gestrich on 10/23/21.
//

import AWSLambdaEvents
import AWSLambdaRuntime
import Foundation

/// Main entry point for the Swift Lambda function.
///
/// **Initialization Flow:**
/// 1. Creates a `DynamicLambdaHandler` to route events to appropriate handlers
/// 2. Wraps it with `LambdaHandlerAdapter` (from AWS Lambda Runtime framework)
/// 3. Wraps that with `LambdaCodableAdapter` for automatic JSON encoding/decoding
/// 4. Creates the `LambdaRuntime` and runs it indefinitely, waiting for invocations
///
/// **Event Decoding:**
/// The `LambdaCodableAdapter` automatically calls `JSONDecoder().decode(LambdaEvent.self, from: eventData)`
/// when an invocation arrives, which triggers `LambdaEvent.init(from:)` to detect the event type.
/// This is framework behavior - there are no direct calls to this initializer in our code.
///
/// **Supported Event Types:**
/// - API Gateway requests (HTTP endpoints)
/// - CloudWatch scheduled events (EventBridge cron)
/// - Direct invocations (CLI, SDK, Step Functions)
@main
struct MyLambda {
    static func main() async throws {
        // Create the main event routing handler
        let handler = DynamicLambdaHandler()

        // Wrap with Lambda Runtime adapters for framework integration
        let adapter = LambdaHandlerAdapter(handler: handler)
        let codableAdapter = LambdaCodableAdapter(encoder: JSONEncoder(), decoder: JSONDecoder(), handler: adapter)

        // Start the Lambda Runtime - this runs indefinitely, processing invocations
        let runtime = LambdaRuntime(handler: codableAdapter)
        try await runtime.run()
    }
}
