//
//  APIClient.swift
//  SwiftLambda
//
//  Created by Bill Gestrich on 11/23/25.
//

import Foundation

@Observable
@MainActor
public class APIClient {
    public var baseURL: String

    /// Mode for API client - determines whether to wrap requests in API Gateway format
    public var mode: APIClientMode = .remote

    private let session: URLSession

    /// Initialize with specific base URL and mode
    public init(baseURL: String, mode: APIClientMode = .remote) {
        self.session = URLSession.shared
        self.baseURL = baseURL
        self.mode = mode
    }

    /// Convenience initializer for local Lambda mode
    public convenience init(localPort: Int) {
        let baseURL = "http://localhost:\(localPort)"
        let endpoint = "\(baseURL)/invoke"
        self.init(baseURL: baseURL, mode: .local(endpoint: endpoint))
    }

    // MARK: - File Operations

    /// Upload file with custom data and filename
    public func uploadFile(fileName: String, data: Data) async throws -> String {
        let endpoint = "/api/files"

        let uploadRequest = FileUploadRequest(
            fileName: fileName,
            data: data.base64EncodedString()
        )

        let requestBody = try JSONEncoder().encode(uploadRequest)

        let (responseData, _) = try await performRequest(
            endpoint: endpoint,
            method: "POST",
            body: requestBody,
            headers: ["Content-Type": "application/json"]
        )

        guard let result = String(data: responseData, encoding: .utf8) else {
            throw APIError.invalidResponse
        }
        return result
    }

    /// List all uploaded files
    public func listFiles() async throws -> [String] {
        let endpoint = "/api/files"

        let (data, _) = try await performRequest(
            endpoint: endpoint,
            method: "GET",
            body: nil
        )

        return try decode([String].self, from: data)
    }

    /// Download a specific file
    public func downloadFile(fileName: String) async throws -> Data {
        let endpoint = "/api/files/\(fileName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? fileName)"

        let (data, _) = try await performRequest(
            endpoint: endpoint,
            method: "GET",
            body: nil
        )

        // Try to decode as base64 response
        if let jsonData = try? JSONDecoder().decode(FileDownloadResponse.self, from: data) {
            guard let decodedData = Data(base64Encoded: jsonData.data) else {
                throw APIError.invalidResponse
            }
            return decodedData
        }

        // Otherwise return raw data
        return data
    }

    /// Delete a specific file
    public func deleteFile(fileName: String) async throws -> String {
        let endpoint = "/api/files/\(fileName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? fileName)"

        let (responseData, _) = try await performRequest(
            endpoint: endpoint,
            method: "DELETE",
            body: nil
        )

        guard let result = String(data: responseData, encoding: .utf8) else {
            throw APIError.invalidResponse
        }
        return result
    }

    // MARK: - Database Operations

    public func initializeDatabase() async throws -> String {
        let endpoint = "/api/database"

        let (data, _) = try await performRequest(
            endpoint: endpoint,
            method: "POST",
            body: nil
        )

        guard let result = String(data: data, encoding: .utf8) else {
            throw APIError.invalidResponse
        }
        return result
    }

    // MARK: - User Operations

    public func listUsers() async throws -> [User] {
        let endpoint = "/api/users"

        let (data, _) = try await performRequest(
            endpoint: endpoint,
            method: "GET",
            body: nil
        )

        return try decode([User].self, from: data)
    }

    public func getUser(id: UUID) async throws -> User {
        let endpoint = "/api/users/\(id.uuidString)"

        let (data, _) = try await performRequest(
            endpoint: endpoint,
            method: "GET",
            body: nil
        )

        return try decode(User.self, from: data)
    }

    public func createUser(_ userRequest: CreateUserRequest) async throws -> User {
        let endpoint = "/api/users"

        let requestBody = try JSONEncoder().encode(userRequest)

        let (data, _) = try await performRequest(
            endpoint: endpoint,
            method: "POST",
            body: requestBody,
            headers: ["Content-Type": "application/json"]
        )

        return try decode(User.self, from: data)
    }

    public func updateUser(id: UUID, _ userRequest: UpdateUserRequest) async throws -> User {
        let endpoint = "/api/users/\(id.uuidString)"

        let requestBody = try JSONEncoder().encode(userRequest)

        let (data, _) = try await performRequest(
            endpoint: endpoint,
            method: "PUT",
            body: requestBody,
            headers: ["Content-Type": "application/json"]
        )

        return try decode(User.self, from: data)
    }

    public func deleteUser(id: UUID) async throws {
        let endpoint = "/api/users/\(id.uuidString)"

        let (_, _) = try await performRequest(
            endpoint: endpoint,
            method: "DELETE",
            body: nil
        )
    }

    // MARK: - Helper Methods

    private func makeURL(endpoint: String) throws -> URL {
        switch mode {
        case .remote:
            // Remote mode: baseURL + endpoint
            let urlString = baseURL + endpoint
            guard let url = URL(string: urlString) else {
                throw APIError.invalidURL
            }
            return url
        case .local(let invokeEndpoint):
            // Local mode: use /invoke endpoint
            guard let url = URL(string: invokeEndpoint) else {
                throw APIError.invalidURL
            }
            return url
        }
    }

    /// Unified method to perform HTTP requests with automatic wrapping/unwrapping for local Lambda mode
    private func performRequest(endpoint: String, method: String, body: Data?, headers: [String: String] = [:]) async throws -> (Data, URLResponse) {
        let url = try makeURL(endpoint: endpoint)
        var request = URLRequest(url: url)

        switch mode {
        case .remote:
            // Remote mode: direct request
            request.httpMethod = method
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
            request.httpBody = body

        case .local:
            // Local mode: wrap in API Gateway format
            request.httpMethod = "POST"  // Always POST to /invoke
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let wrappedBody = try wrapRequest(path: endpoint, method: method, body: body, headers: headers)
            request.httpBody = wrappedBody
        }

        let (responseData, response) = try await session.data(for: request)

        switch mode {
        case .remote:
            // Remote mode: validate HTTP response
            try validateResponse(response, data: responseData)
            return (responseData, response)

        case .local:
            // Local mode: unwrap API Gateway response
            let unwrappedData = try unwrapResponse(data: responseData)
            return (unwrappedData, response)
        }
    }

    /// Wrap request in API Gateway format for local Lambda mode
    private func wrapRequest(path: String, method: String, body: Data?, headers: [String: String] = [:]) throws -> Data {
        let bodyString: String?
        if let body = body {
            bodyString = String(data: body, encoding: .utf8)
        } else {
            bodyString = nil
        }

        let wrapper = APIGatewayRequestWrapper(
            resource: path,
            path: path,
            httpMethod: method,
            headers: headers,
            body: bodyString
        )

        return try JSONEncoder().encode(wrapper)
    }

    /// Unwrap API Gateway response from local Lambda
    private func unwrapResponse(data: Data) throws -> Data {
        // Try to decode as API Gateway response wrapper
        do {
            let wrapper = try JSONDecoder().decode(APIGatewayResponseWrapper.self, from: data)

            guard (200...299).contains(wrapper.statusCode) else {
                let bodyData = wrapper.body.data(using: .utf8)
                throw APIError.httpError(statusCode: wrapper.statusCode, data: bodyData)
            }

            guard let responseData = wrapper.body.data(using: .utf8) else {
                throw APIError.invalidResponse
            }

            return responseData
        } catch let decodingError as DecodingError {
            throw APIError.localDecodingError(decodingError, data: data)
        } catch {
            throw error
        }
    }

    private func validateResponse(_ response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.httpError(statusCode: httpResponse.statusCode, data: data)
        }
    }

    /// Decode JSON data, throwing detailed error with raw response on failure
    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw APIError.decodingError(error, data: data)
        }
    }
}

public enum APIError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int, message: String)
    case decodingError(underlyingError: Error, rawResponse: String)
    case localDecodingError(underlyingError: Error, rawResponse: String)
    case networkError(Error)

    /// Create an HTTP error from status code and response data
    static func httpError(statusCode: Int, data: Data?) -> APIError {
        let message = extractErrorMessage(from: data)
        return .httpError(statusCode: statusCode, message: message)
    }

    /// Create a decoding error from underlying error and response data
    static func decodingError(_ error: Error, data: Data) -> APIError {
        let rawResponse = extractErrorMessage(from: data)
        return .decodingError(underlyingError: error, rawResponse: rawResponse)
    }

    /// Create a local decoding error from underlying error and response data
    static func localDecodingError(_ error: Error, data: Data) -> APIError {
        let rawResponse = extractErrorMessage(from: data)
        return .localDecodingError(underlyingError: error, rawResponse: rawResponse)
    }

    /// Extract error message from response data
    private static func extractErrorMessage(from data: Data?) -> String {
        guard let data = data else {
            return "Unknown error (no response data)"
        }
        return String(data: data, encoding: .utf8) ?? "Unknown error (binary response)"
    }

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let statusCode, let message):
            return "HTTP \(statusCode): \(message)"
        case .decodingError(let underlyingError, let rawResponse):
            return """
            Failed to decode response: \(underlyingError.localizedDescription)

            Raw response received:
            \(rawResponse)
            """
        case .localDecodingError(let underlyingError, let rawResponse):
            return """
            Failed to decode local Lambda response wrapper

            Underlying error: \(underlyingError.localizedDescription)

            Raw response received:
            \(rawResponse)
            """
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}

/// Configuration for API client behavior
public enum APIClientMode {
    /// Remote mode - calls API Gateway directly
    case remote
    /// Local mode - wraps requests in API Gateway format and hits /invoke endpoint
    case local(endpoint: String)
}
