//
//  APIGatewayHandler.swift
//  SwiftLambda
//
//  Created by Bill Gestrich on 12/25/23.
//

import AWSLambdaEvents
import AWSLambdaHelpers
import AWSLambdaRuntime
import Foundation
import NIO
import NIOHelpers
import SwiftServerApp

struct APIGWHandler: EventLoopLambdaHandler {

    typealias In = APIGateway.Request
    typealias Out = APIGateway.Response

    //MARK: EventLoopLambdaHandler conformance

    func handle(context: Lambda.Context, event: APIGateway.Request) -> EventLoopFuture<APIGateway.Response> {
        return context.eventLoop.asyncFuture {
            return try await handle(context: context, event: event)
        }
    }


    //Async variant
    func handle(context: Lambda.Context, event: APIGateway.Request) async throws -> APIGateway.Response {

        //TODO: The Lambda.InitializationContext can hold resources that can be reused on every request.
        //It may be more performant to use that to hold onto our database connections.
        let services = ServiceComposer(eventLoop: context.eventLoop)

        do {
            let response = try await route(event: event, app: services.app)
            try await services.shutdown()
            return response
        } catch {
            //We have to shut down out resources before they deallocate so we catch then rethrow
            print(String(reflecting: error))
            try await services.shutdown()
            //Note that error always results in a 500 status code returned (expected)
            throw error
        }
    }

    func route(event: In, app: SwiftServerApp) async throws -> APIGateway.Response {

        let leadingPathPart = "" // Use this if you there a leading part in your path, like "api" or "stage"

        let urlComponents: [String]
        if !leadingPathPart.isEmpty {
            urlComponents = event.path.urlComponentsAfter(targetComponent: "stage")
        } else {
            urlComponents = event.path.split(separator: "/").map(String.init)
        }

        guard let firstComponent = urlComponents.first else {
            throw APIGWHandlerError.general(description: "No path available")
        }

        switch firstComponent {
        case "database":
            switch event.httpMethod {
            case .POST:
                try await app.initializeDatabase()
                return try "Database Initialized".apiGatewayOkResponse()
            case .DELETE:
                try await app.resetDatabase()
                return try "Database Reset".apiGatewayOkResponse()
            default:
                throw APIGWHandlerError.general(description: "Method not handled: \(event.httpMethod)")
            }
        case "file":
            let _ = try await app.uploadAndDownloadS3File()
            return try "File uploaded and downloaded".apiGatewayOkResponse()
        case "users":
            switch event.httpMethod {
            case .GET:
                
                guard urlComponents.count > 1 else {
                    return try await app.getUsers().apiGatewayOkResponse()
                }

                let uuid = urlComponents[1]
                guard let user = try await app.getUser(id: uuid) else {
                    return try "User Not Found: \(uuid)".createAPIGatewayJSONResponse(statusCode: .notFound)
                }
                return try user.apiGatewayOkResponse()

            case .POST:

                guard let bodyData = event.bodyData() else {
                    throw APIGWHandlerError.general(description: "Missing body data")
                }

                let userRequest = try JSONDecoder().decode(CreateUser.self, from: bodyData)
                return try await app.createUser(userRequest).createAPIGatewayJSONResponse(statusCode: .created)

            case .PUT:

                guard urlComponents.count > 1 else {
                    return try "User uuid required".createAPIGatewayJSONResponse(statusCode: .notFound)
                }

                guard let bodyData = event.bodyData() else {
                    throw APIGWHandlerError.general(description: "Missing body data")
                }

                let userRequest = try JSONDecoder().decode(CreateUser.self, from: bodyData)

                let uuid = urlComponents[1]
                guard let user = try await app.getUser(id: uuid) else {
                    return try "User not found: \(uuid)".createAPIGatewayJSONResponse(statusCode: .notFound)
                }

                user.applyCreateUserRequest(userRequest)
                return try await app.updateUser(user).createAPIGatewayJSONResponse(statusCode: .created)

            case .DELETE:

                guard urlComponents.count > 1 else {
                    return APIGateway.Response(statusCode: .notFound)
                }

                let uuid = urlComponents[1]
                guard let user = try await app.getUser(id: uuid) else {
                    return try "User not found: \(uuid)".createAPIGatewayJSONResponse(statusCode: .notFound)
                }

                try await app.deleteUser(user)
                return APIGateway.Response(statusCode: .ok, headers: ["Content-Type": "application/json"])

            default:
                throw APIGWHandlerError.general(description: "Method not handled: \(event.httpMethod)")
            }
        default:
            return try "Path Not Found: \(firstComponent)".createAPIGatewayJSONResponse(statusCode: .notFound)
        }
    }
}

enum APIGWHandlerError: LocalizedError {
    case general (description: String)

    var errorDescription: String? {
        switch self {
        case .general(let description):
            return description
        }
    }
}

extension Encodable {
    //TODO: There is some overlap in the swift-server-utilities method name.
    func apiGatewayOkResponse() throws -> APIGateway.Response {
        return try createAPIGatewayJSONResponse(statusCode: .ok)
    }

    func createAPIGatewayJSONResponse(statusCode: HTTPResponseStatus) throws -> APIGateway.Response {

        guard let jsonData = try? JSONEncoder().encode(self) else {
            throw APIGWHandlerError.general(description: "Could not convert object to json data")
        }

        let jsonString = String(data: jsonData, encoding: .utf8)
        return APIGateway.Response(statusCode: statusCode, headers: ["Content-Type": "application/json"], body: jsonString)
    }
}

extension String {
    func urlComponentsAfter(targetComponent: String) -> [String] {
        let allParts = split(separator: "/")
        var partFound = false
        var result = [String]()
        for currComponent in allParts {
            if partFound {
                result.append(String(currComponent))
            }

            if currComponent == targetComponent {
                partFound = true
            }
        }

        return result
    }
}

extension User {
    func applyCreateUserRequest(_ createUser: CreateUser) {
        email = createUser.email
        password = createUser.password
        firstName = createUser.firstName
        lastName = createUser.lastName
        nickName = createUser.nickName
        phone = createUser.phone
        slackID = createUser.slackID
    }
}
