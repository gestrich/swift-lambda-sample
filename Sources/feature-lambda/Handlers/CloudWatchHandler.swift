//
//  CloudWatchHandler.swift
//  SwiftLambda
//
//  Created by Bill Gestrich on 11/16/25.
//

import AWSLambdaEvents
import AWSLambdaRuntime
import Foundation
import service_server

struct CloudWatchHandler {

    func handle(context: LambdaContext, event: CloudwatchEvent<CloudwatchDetails.Scheduled>) async throws -> String {
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
}
