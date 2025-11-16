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
        let handler = SwiftLambdaHandler()
        let adapter = LambdaHandlerAdapter(handler: handler)
        let codableAdapter = LambdaCodableAdapter(encoder: JSONEncoder(), decoder: JSONDecoder(), handler: adapter)
        let runtime = LambdaRuntime(handler: codableAdapter)
        try await runtime.run()
    }
}

struct SwiftLambdaHandler: LambdaHandler {
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

    private func handleAPIGateway(request: APIGatewayRequest, context: LambdaContext) async throws -> LambdaResponse {
        let handler = APIGWHandler()
        let response = try await handler.handle(context: context, event: request)
        return .apiGateway(response)
    }

    private func handleCloudWatchScheduled(event: CloudwatchEvent<CloudwatchDetails.Scheduled>, context: LambdaContext) async throws -> LambdaResponse {
        let handler = CloudWatchHandler()
        let result = try await handler.handle(context: context, event: event)
        return .string(result)
    }

    private func handleDirectCreateUser(user: CreateUser, context: LambdaContext) async throws -> LambdaResponse {
        let handler = CreateUserHandler()
        let result = try await handler.handle(context: context, event: user)
        return .string(result)
    }
}
