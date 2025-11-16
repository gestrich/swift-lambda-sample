//
//  CloudwatchHandler.swift
//
//
//  Created by Bill Gestrich on 10/23/21.
//

import AWSLambdaRuntime
import Foundation
import SwiftServerApp

public struct CreateUserHandler {

    //MARK: Handler

    func handle(context: LambdaContext, event: CreateUser) async throws -> String {

        context.logger.log(level: .critical, "Cloud Watch (CreateAnalysisRequest) event received")

        let services = try await ServiceComposer()
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
