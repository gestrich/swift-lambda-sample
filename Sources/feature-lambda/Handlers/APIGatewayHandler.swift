//
//  APIGatewayHandler.swift
//  SwiftLambda
//
//  Created by Bill Gestrich on 12/25/23.
//

import AWSLambdaEvents
import AWSLambdaRuntime
import Client
import Foundation
import HTTPTypes
import service_server

struct APIGWHandler {

    //MARK: Handler

    func handle(context: LambdaContext, event: APIGatewayRequest) async throws -> APIGatewayResponse {

        // Log every incoming request for debugging
        context.logger.info("API Gateway request received", metadata: [
            "path": .string(event.path),
            "method": .string(event.httpMethod.rawValue),
            "requestId": .string(context.requestID)
        ])

        //TODO: The Lambda.InitializationContext can hold resources that can be reused on every request.
        //It may be more performant to use that to hold onto our database connections.
        let services = try await ServiceComposer()

        do {
            let response = try await route(event: event, app: services.app)
            try await services.shutdown()

            // Log successful responses
            context.logger.info("API Gateway response", metadata: [
                "statusCode": .stringConvertible(response.statusCode.code),
                "requestId": .string(context.requestID)
            ])

            return response
        } catch {
            try await services.shutdown()
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
        case "health":
            // Health check endpoint - always returns 200 OK
            let healthResponse = [
                "status": "healthy",
                "timestamp": ISO8601DateFormatter().string(from: Date()),
                "service": "swift-lambda-sample"
            ]
            return try healthResponse.apiGatewayOkResponse()

        case "checkError":
            // Test endpoint that always throws an error for testing error logging
            throw APIGWHandlerError.general(description: "Test error from checkError endpoint - this is intentional for testing error logs")

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
        case "files":
            switch event.httpMethod {
            case .get:
                // GET /api/files - list all files
                // GET /api/files/{fileName} - download specific file
                guard urlComponents.count > 1 else {
                    let files = try await app.listS3Files()
                    return try files.apiGatewayOkResponse()
                }

                let fileName = urlComponents[1].removingPercentEncoding ?? urlComponents[1]
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

            case .delete:
                // DELETE /api/files/{fileName} - delete file
                guard urlComponents.count > 1 else {
                    throw APIGWHandlerError.general(description: "File name required for delete")
                }

                let fileName = urlComponents[1].removingPercentEncoding ?? urlComponents[1]
                try await app.deleteS3File(key: fileName)
                return try "File deleted: \(fileName)".apiGatewayOkResponse()

            default:
                throw APIGWHandlerError.general(description: "Method not handled: \(event.httpMethod)")
            }
        case "reminders":
            switch event.httpMethod {
            case .get:
                // GET /api/reminders - list all reminders
                // GET /api/reminders/{id} - get specific reminder
                guard urlComponents.count > 1 else {
                    let reminders = try await app.listReminders()
                    return try reminders.apiGatewayOkResponse()
                }

                let id = urlComponents[1].removingPercentEncoding ?? urlComponents[1]
                guard let reminder = try await app.getReminder(id: id) else {
                    return try "Reminder not found: \(id)".createAPIGatewayJSONResponse(statusCode: .notFound)
                }
                return try reminder.apiGatewayOkResponse()

            case .post:
                // POST /api/reminders - create reminder
                guard let bodyString = event.body,
                      let bodyData = bodyString.data(using: .utf8) else {
                    throw APIGWHandlerError.general(description: "Missing body data")
                }

                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let createRequest = try decoder.decode(CreateReminderRequest.self, from: bodyData)
                let reminder = try await app.createReminder(createRequest)
                return try reminder.createAPIGatewayJSONResponse(statusCode: .created)

            case .put:
                // PUT /api/reminders/{id} - update reminder
                guard urlComponents.count > 1 else {
                    return try "Reminder id required".createAPIGatewayJSONResponse(statusCode: .badRequest)
                }

                guard let bodyString = event.body,
                      let bodyData = bodyString.data(using: .utf8) else {
                    throw APIGWHandlerError.general(description: "Missing body data")
                }

                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let updateRequest = try decoder.decode(UpdateReminderRequest.self, from: bodyData)
                let id = urlComponents[1].removingPercentEncoding ?? urlComponents[1]
                let reminder = try await app.updateReminder(id: id, request: updateRequest)
                return try reminder.apiGatewayOkResponse()

            case .delete:
                // DELETE /api/reminders/{id} - delete reminder
                guard urlComponents.count > 1 else {
                    throw APIGWHandlerError.general(description: "Reminder id required for delete")
                }

                let id = urlComponents[1].removingPercentEncoding ?? urlComponents[1]
                try await app.deleteReminder(id: id)
                return APIGatewayResponse(statusCode: .noContent)

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

                let updateRequest = try JSONDecoder().decode(UpdateUser.self, from: bodyData)

                let uuid = urlComponents[1]
                guard let user = try await app.getUser(id: uuid) else {
                    return try "User not found: \(uuid)".createAPIGatewayJSONResponse(statusCode: .notFound)
                }

                user.applyUpdateUserRequest(updateRequest)
                return try await app.updateUser(user).createAPIGatewayJSONResponse(statusCode: .ok)

            case .delete:

                guard urlComponents.count > 1 else {
                    return APIGatewayResponse(statusCode: .notFound)
                }

                let uuid = urlComponents[1]
                guard let user = try await app.getUser(id: uuid) else {
                    return try "User not found: \(uuid)".createAPIGatewayJSONResponse(statusCode: .notFound)
                }

                try await app.deleteUser(user)
                return APIGatewayResponse(statusCode: .noContent)

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
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        guard let jsonData = try? encoder.encode(self) else {
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
