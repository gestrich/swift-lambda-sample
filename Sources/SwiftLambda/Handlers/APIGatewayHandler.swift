//
//  APIGatewayHandler.swift
//  SwiftLambda
//
//  Created by Bill Gestrich on 12/25/23.
//

import AWSLambdaEvents
import AWSLambdaRuntime
import Foundation
import HTTPTypes
import SwiftServerApp

struct APIGWHandler {

    //MARK: Handler

    func handle(context: LambdaContext, event: APIGatewayRequest) async throws -> APIGatewayResponse {

        //TODO: The Lambda.InitializationContext can hold resources that can be reused on every request.
        //It may be more performant to use that to hold onto our database connections.
        let services = try await ServiceComposer()

        do {
            let response = try await route(event: event, app: services.app)
            try await services.shutdown()
            return response
        } catch {
            //We have to shut down out resources before they deallocate so we catch then rethrow
            context.logger.error("API Gateway handler error: \(error)")
            context.logger.error("Error type: \(type(of: error))")
            context.logger.error("Error description: \(String(reflecting: error))")
            context.logger.error("Request path: \(event.path)")
            context.logger.error("Request method: \(event.httpMethod)")
            try await services.shutdown()
            //Note that error always results in a 500 status code returned (expected)
            throw error
        }
    }

    func route(event: APIGatewayRequest, app: SwiftServerApp) async throws -> APIGatewayResponse {

        let leadingPathPart = "api" // Use this if you there a leading part in your path, like "api" or "stage"

        let urlComponents: [String]
        if !leadingPathPart.isEmpty {
            urlComponents = event.path.urlComponentsAfter(targetComponent: leadingPathPart)
        } else {
            urlComponents = event.path.split(separator: "/").map(String.init)
        }

        guard let firstComponent = urlComponents.first else {
            throw APIGWHandlerError.general(description: "No path available")
        }

        switch firstComponent {
        case "database":
            switch event.httpMethod {
            case .post:
                try await app.initializeDatabase()
                return try "Database Initialized".apiGatewayOkResponse()
            case .delete:
                try await app.resetDatabase()
                return try "Database Reset".apiGatewayOkResponse()
            default:
                throw APIGWHandlerError.general(description: "Method not handled: \(event.httpMethod)")
            }
        case "file":
            let _ = try await app.uploadAndDownloadS3File()
            return try "File uploaded and downloaded".apiGatewayOkResponse()
        case "files":
            switch event.httpMethod {
            case .get:
                // GET /api/files - list all files
                // GET /api/files/{fileName} - download specific file
                guard urlComponents.count > 1 else {
                    // Hardcoded test - bypass all S3 logic
                    return try "Files list test".apiGatewayOkResponse()
                    // let files = try await app.listS3Files()
                    // return try files.apiGatewayOkResponse()
                }

                let fileName = urlComponents[1]
                guard let fileData = try await app.downloadS3File(key: fileName) else {
                    return try "File not found: \(fileName)".createAPIGatewayJSONResponse(statusCode: .notFound)
                }

                let response = FileDownloadResponse(
                    fileName: fileName,
                    data: fileData.base64EncodedString()
                )
                return try response.apiGatewayOkResponse()

            case .post:
                // POST /api/files - upload file
                guard let bodyString = event.body,
                      let bodyData = bodyString.data(using: .utf8) else {
                    throw APIGWHandlerError.general(description: "Missing body data")
                }

                let uploadRequest = try JSONDecoder().decode(FileUploadRequest.self, from: bodyData)
                guard let fileData = Data(base64Encoded: uploadRequest.data) else {
                    throw APIGWHandlerError.general(description: "Invalid base64 data")
                }

                try await app.uploadS3File(key: uploadRequest.fileName, data: fileData)
                return try "File uploaded: \(uploadRequest.fileName)".apiGatewayOkResponse()

            default:
                throw APIGWHandlerError.general(description: "Method not handled: \(event.httpMethod)")
            }
        case "users":
            switch event.httpMethod {
            case .get:
                
                guard urlComponents.count > 1 else {
                    return try await app.getUsers().apiGatewayOkResponse()
                }

                let uuid = urlComponents[1]
                guard let user = try await app.getUser(id: uuid) else {
                    return try "User Not Found: \(uuid)".createAPIGatewayJSONResponse(statusCode: .notFound)
                }
                return try user.apiGatewayOkResponse()

            case .post:

                guard let bodyString = event.body,
                      let bodyData = bodyString.data(using: .utf8) else {
                    throw APIGWHandlerError.general(description: "Missing body data")
                }

                let userRequest = try JSONDecoder().decode(CreateUser.self, from: bodyData)
                return try await app.createUser(userRequest).createAPIGatewayJSONResponse(statusCode: .created)

            case .put:

                guard urlComponents.count > 1 else {
                    return try "User uuid required".createAPIGatewayJSONResponse(statusCode: .notFound)
                }

                guard let bodyString = event.body,
                      let bodyData = bodyString.data(using: .utf8) else {
                    throw APIGWHandlerError.general(description: "Missing body data")
                }

                let userRequest = try JSONDecoder().decode(CreateUser.self, from: bodyData)

                let uuid = urlComponents[1]
                guard let user = try await app.getUser(id: uuid) else {
                    return try "User not found: \(uuid)".createAPIGatewayJSONResponse(statusCode: .notFound)
                }

                user.applyCreateUserRequest(userRequest)
                return try await app.updateUser(user).createAPIGatewayJSONResponse(statusCode: .created)

            case .delete:

                guard urlComponents.count > 1 else {
                    return APIGatewayResponse(statusCode: .notFound)
                }

                let uuid = urlComponents[1]
                guard let user = try await app.getUser(id: uuid) else {
                    return try "User not found: \(uuid)".createAPIGatewayJSONResponse(statusCode: .notFound)
                }

                try await app.deleteUser(user)
                return APIGatewayResponse(statusCode: .ok, headers: ["Content-Type": "application/json"])

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
    func apiGatewayOkResponse() throws -> APIGatewayResponse {
        return try createAPIGatewayJSONResponse(statusCode: .ok)
    }

    func createAPIGatewayJSONResponse(statusCode: HTTPResponse.Status) throws -> APIGatewayResponse {

        guard let jsonData = try? JSONEncoder().encode(self) else {
            throw APIGWHandlerError.general(description: "Could not convert object to json data")
        }

        let jsonString = String(data: jsonData, encoding: .utf8)
        return APIGatewayResponse(statusCode: statusCode, headers: ["Content-Type": "application/json"], body: jsonString)
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
