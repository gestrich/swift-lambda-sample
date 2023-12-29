//
//  CloudwatchHandler.swift
//
//
//  Created by Bill Gestrich on 10/23/21.
//

import AWSLambdaRuntime
import Foundation
import NIO
import SwiftServerApp

public struct CreateUserHandler: EventLoopLambdaHandler {

    public typealias In = CreateUser
    public typealias Out = String

    //MARK: EventLoopLambdaHandler conformance

    public func handle(context: Lambda.Context, event: In) -> EventLoopFuture<Out> {

        let future = context.eventLoop.asyncFuture {
            return try await handle(context: context, event: event)
        }

        return future
    }


    //Async variant
    func handle(context: Lambda.Context, event: In) async throws -> Out {

        context.logger.log(level: .critical, "Cloud Watch (CreateAnalysisRequest) event received")

        let services = ServiceComposer(eventLoop: context.eventLoop)
        let app = services.app

        do {
            let response = try await app.createUser(event)
            try await services.shutdown()
            return response
        } catch {
            //We have to shut down out resources before they deallocate so we catch then rethrow
            try await services.shutdown()
            print(String(reflecting: error))
            //Note that error always results in a 500 status code returned (expected)
            throw error
        }
    }

}
