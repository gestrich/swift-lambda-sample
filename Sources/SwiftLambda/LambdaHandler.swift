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
    typealias Output = String

    func handle(_ event: LambdaEvent, context: LambdaContext) async throws -> String {

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

    private func handleAPIGateway(request: APIGatewayRequest, context: LambdaContext) async throws -> String {
        let handler = APIGWHandler()
        let response = try await handler.handle(context: context, event: request)

        // Convert APIGatewayResponse to JSON string for unified return type
        let encoder = JSONEncoder()
        let data = try encoder.encode(response)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private func handleCloudWatchScheduled(event: CloudwatchEvent<CloudwatchDetails.Scheduled>, context: LambdaContext) async throws -> String {
        context.logger.info("CloudWatch scheduled event received", metadata: [
            "id": .string(event.id),
            "source": .string(event.source),
            "time": .string(event.time.description),
            "region": .string(event.region.rawValue)
        ])

        // Initialize services to get access to S3
        let services = try await ServiceComposer()

        do {
            // Write a timestamped file to S3 when scheduled event fires
            let timestamp = ISO8601DateFormatter().string(from: event.time)
            let content = "CloudWatch scheduled event fired at \(timestamp)\nEvent ID: \(event.id)\nSource: \(event.source)\nRegion: \(event.region.rawValue)"

            try await services.app.uploadToS3(key: "scheduled-event-\(timestamp).txt", content: content)

            context.logger.info("Successfully wrote scheduled event file to S3")

            try await services.shutdown()
            return "CloudWatch scheduled event processed successfully - file written to S3"
        } catch {
            context.logger.error("Failed to process scheduled event", metadata: [
                "error": .string(String(describing: error))
            ])
            try await services.shutdown()
            throw error
        }
    }

    private func handleDirectCreateUser(user: CreateUser, context: LambdaContext) async throws -> String {
        let handler = CreateUserHandler()
        return try await handler.handle(context: context, event: user)
    }
}
