//
//  CreateUserHandler.swift
//  SwiftLambda
//
//  Handles direct Lambda invocations with CreateUser payload
//
//  Created by Bill Gestrich on 10/23/21.
//

import AWSLambdaRuntime
import Foundation

/// Handles direct CreateUser invocations
///
/// This handler is called when Lambda receives a direct invocation with a CreateUser JSON payload.
/// This is NOT a CloudWatch event - it's a direct function call from:
/// - AWS CLI: `aws lambda invoke --payload '{"email":"...","firstName":"..."}'`
/// - Another Lambda function
/// - AWS SDK calls
/// - Step Functions
public struct CreateUserHandler {

    //MARK: Handler

    func handle(context: LambdaContext, event: CreateUser) async throws -> User {

        context.logger.info("Direct CreateUser invocation received", metadata: [
            "email": .string(event.email),
            "firstName": .string(event.firstName),
            "lastName": .string(event.lastName)
        ])

        let services = try await ServiceComposer()
        let app = services.app

        do {
            let user = try await app.createUser(event)
            try await services.shutdown()
            return user
        } catch {
            //We have to shut down out resources before they deallocate so we catch then rethrow
            try await services.shutdown()
            print(String(reflecting: error))
            //Note that error always results in a 500 status code returned (expected)
            throw error
        }
    }

}
