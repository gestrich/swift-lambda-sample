//
//  LambdaHandler.swift
//
//
//  Created by Bill Gestrich on 10/23/21.
//

import AWSLambdaEvents
import AWSLambdaRuntime
import Foundation
import SwiftServerApp

@main
struct MyLambda {
    static func main() async throws {
        let handler = DynamicLambdaHandler()
        let adapter = LambdaHandlerAdapter(handler: handler)
        let codableAdapter = LambdaCodableAdapter(encoder: JSONEncoder(), decoder: JSONDecoder(), handler: adapter)
        let runtime = LambdaRuntime(handler: codableAdapter)
        try await runtime.run()
    }
}

/// Dynamic Lambda handler that routes events to specialized handlers based on event type
///
/// This handler uses a union type pattern (LambdaEvent) to automatically route incoming
/// Lambda invocations to the appropriate handler based on the JSON structure of the event.
///
/// Supported event types:
/// - API Gateway requests (HTTP requests via API Gateway)
/// - CloudWatch scheduled events (EventBridge cron-based invocations)
/// - Direct CreateUser invocations (direct Lambda calls with CreateUser payload)
struct DynamicLambdaHandler: LambdaHandler {
    typealias Event = LambdaEvent
    typealias Output = LambdaResponse

    func handle(_ event: LambdaEvent, context: LambdaContext) async throws -> LambdaResponse {

        switch event {
        case .apiGateway(let request):
            return try await handleAPIGateway(request: request, context: context)

        case .cloudWatchScheduled(let scheduledEvent):
            return try await handleCloudWatchScheduled(event: scheduledEvent, context: context)

        case .directCreateUser(let createUser):
            return try await handleDirectCreateUser(user: createUser, context: context)
        }
    }

    // MARK: - Route Handlers

    /// Handles HTTP requests from API Gateway
    ///
    /// Called when: User makes HTTP request through API Gateway
    /// Example: `curl -X POST https://{api-gateway-url}/prod/api/file`
    private func handleAPIGateway(request: APIGatewayRequest, context: LambdaContext) async throws -> LambdaResponse {
        let handler = APIGWHandler()
        let response = try await handler.handle(context: context, event: request)
        return .apiGateway(response)
    }

    /// Handles CloudWatch EventBridge scheduled events
    ///
    /// Called when: EventBridge rule fires on schedule (cron expression)
    /// Example: Daily at 6:00 AM UTC via `cron(0 6 * * ? *)`
    /// The event is automatically sent by AWS - no manual invocation needed
    private func handleCloudWatchScheduled(event: CloudwatchEvent<CloudwatchDetails.Scheduled>, context: LambdaContext) async throws -> LambdaResponse {
        let handler = CloudWatchHandler()
        let result = try await handler.handle(context: context, event: event)
        return .string(result)
    }

    /// Handles direct CreateUser invocations
    ///
    /// Called when: Lambda is invoked directly with CreateUser JSON payload
    /// Examples:
    /// - AWS CLI: `aws lambda invoke --payload '{"email":"...","firstName":"..."}'`
    /// - Another Lambda function calling this one
    /// - AWS SDK direct invocation
    /// - AWS Step Functions
    ///
    /// Note: This is NOT a CloudWatch event - it's a direct function invocation
    private func handleDirectCreateUser(user: CreateUser, context: LambdaContext) async throws -> LambdaResponse {
        let handler = CreateUserHandler()
        let result = try await handler.handle(context: context, event: user)
        return .string(result)
    }
}
