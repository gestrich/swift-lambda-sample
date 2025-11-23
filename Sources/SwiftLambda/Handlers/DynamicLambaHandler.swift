//
//  DynamicLambdaHandler.swift
//  SwiftLambda
//
//  Created by Bill Gestrich on 11/16/25.
//

import AWSLambdaEvents
import AWSLambdaRuntime
import Foundation
import SwiftServerApp

/// Dynamic Lambda handler that routes events to specialized handlers based on event type
///
/// This handler uses a union type pattern (LambdaEvent) to automatically route incoming
/// Lambda invocations to the appropriate handler based on the JSON structure of the event.
///
/// Supported event types:
/// - API Gateway requests (HTTP requests via API Gateway)
/// - CloudWatch scheduled events (EventBridge cron-based invocations)
/// - Direct invocations (direct Lambda calls via CLI, SDK, Step Functions, etc.)
///   - CreateUser (currently supported)
///   - Future: DeleteUser, UpdateSettings, etc. (easily extensible)
struct DynamicLambdaHandler: LambdaHandler {
    typealias Event = LambdaEvent
    typealias Output = LambdaResponse

    func handle(_ event: LambdaEvent, context: LambdaContext) async throws -> LambdaResponse {
        do {
            switch event {
            case .apiGateway(let request):
                return try await handleAPIGateway(request: request, context: context)

            case .cloudWatchScheduled(let scheduledEvent):
                return try await handleCloudWatchScheduled(event: scheduledEvent, context: context)

            case .directInvocation(let directEvent):
                return try await handleDirectInvocation(event: directEvent, context: context)
            }
        } catch {
            context.logger.error("Error description: \(String(describing: error))")
            throw error
        }
    }

    // MARK: - Route Handlers

    /// Handles HTTP requests from API Gateway
    ///
    /// Called when: User makes HTTP request through API Gateway
    /// Example: `curl -X GET https://{api-gateway-url}/prod/api/health`
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

    /// Handles direct Lambda invocations
    ///
    /// Called when: Lambda is invoked directly (not via API Gateway or CloudWatch)
    /// Examples:
    /// - AWS CLI: `aws lambda invoke --payload '{"email":"...","firstName":"..."}'`
    /// - Another Lambda function calling this one
    /// - AWS SDK direct invocation
    /// - AWS Step Functions
    ///
    /// Note: This is NOT a CloudWatch event - it's a direct function invocation
    private func handleDirectInvocation(event: DirectInvocationEvent, context: LambdaContext) async throws -> LambdaResponse {
        switch event {
        case .createUser(let user):
            let handler = CreateUserHandler()
            let result = try await handler.handle(context: context, event: user)
            let jsonData = try JSONEncoder().encode(result)
            let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
            return .string(jsonString)

        // Future direct invocation types will be handled here:
        // case .deleteUser(let request):
        //     let handler = DeleteUserHandler()
        //     let result = try await handler.handle(context: context, event: request)
        //     return .string(result)
        }
    }
}
