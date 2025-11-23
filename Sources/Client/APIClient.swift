import Foundation

/// Configuration for API client behavior
public enum APIClientMode {
    /// Standard mode - calls API Gateway directly
    case apiGateway
    /// Local Lambda mode - wraps requests in API Gateway format and hits /invoke endpoint
    case localLambda(endpoint: String)
}

@Observable
@MainActor
public class APIClient {
    public static let shared = APIClient()

    public var baseURL: String {
        didSet {
            UserDefaults.standard.set(baseURL, forKey: "apiBaseURL")
        }
    }

    /// Mode for API client - determines whether to wrap requests in API Gateway format
    public var mode: APIClientMode = .apiGateway

    private let session: URLSession

    public init() {
        self.session = URLSession.shared
        // Load saved URL or use default
        if let savedURL = UserDefaults.standard.string(forKey: "apiBaseURL") {
            self.baseURL = savedURL
        } else {
            self.baseURL = "https://5kawxqr7e4.execute-api.us-east-1.amazonaws.com/prod"
        }
    }

    /// Initialize with specific mode
    public init(baseURL: String, mode: APIClientMode = .apiGateway) {
        self.session = URLSession.shared
        self.baseURL = baseURL
        self.mode = mode
    }

    // MARK: - File Operations

    /// Test file upload (uploads hardcoded test file)
    public func testFileUpload() async throws -> String {
        // Upload a test file using the files endpoint
        let testContent = "Hello World! This data was written/read from S3."
        guard let data = testContent.data(using: .utf8) else {
            throw APIError.invalidResponse
        }

        return try await uploadFile(fileName: "hello-world.text", data: data)
    }

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

        do {
            let fileList = try JSONDecoder().decode([String].self, from: data)
            return fileList
        } catch {
            throw APIError.decodingError(error)
        }
    }

    /// Download a specific file
    public func downloadFile(fileName: String) async throws -> Data {
        let endpoint = "/api/files/\(fileName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? fileName)"
        let url = try makeURL(endpoint: endpoint)

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)

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
        let url = try makeURL(endpoint: endpoint)

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"

        let (responseData, response) = try await session.data(for: request)
        try validateResponse(response, data: responseData)

        guard let result = String(data: responseData, encoding: .utf8) else {
            throw APIError.invalidResponse
        }
        return result
    }

    // MARK: - Database Operations

    public func initializeDatabase() async throws -> String {
        let endpoint = "/api/database"
        let url = try makeURL(endpoint: endpoint)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)

        guard let result = String(data: data, encoding: .utf8) else {
            throw APIError.invalidResponse
        }
        return result
    }

    // MARK: - User Operations

    public func listUsers() async throws -> [User] {
        let endpoint = "/api/users"
        let url = try makeURL(endpoint: endpoint)

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)

        do {
            let users = try JSONDecoder().decode([User].self, from: data)
            return users
        } catch {
            throw APIError.decodingError(error)
        }
    }

    public func getUser(id: UUID) async throws -> User {
        let endpoint = "/api/users/\(id.uuidString)"
        let url = try makeURL(endpoint: endpoint)

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)

        do {
            let user = try JSONDecoder().decode(User.self, from: data)
            return user
        } catch {
            throw APIError.decodingError(error)
        }
    }

    public func createUser(_ userRequest: CreateUserRequest) async throws -> User {
        let endpoint = "/api/users"
        let url = try makeURL(endpoint: endpoint)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            request.httpBody = try JSONEncoder().encode(userRequest)
        } catch {
            throw APIError.networkError(error)
        }

        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)

        do {
            let user = try JSONDecoder().decode(User.self, from: data)
            return user
        } catch {
            throw APIError.decodingError(error)
        }
    }

    public func updateUser(id: UUID, _ userRequest: UpdateUserRequest) async throws -> User {
        let endpoint = "/api/users/\(id.uuidString)"
        let url = try makeURL(endpoint: endpoint)

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            request.httpBody = try JSONEncoder().encode(userRequest)
        } catch {
            throw APIError.networkError(error)
        }

        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)

        do {
            let user = try JSONDecoder().decode(User.self, from: data)
            return user
        } catch {
            throw APIError.decodingError(error)
        }
    }

    public func deleteUser(id: UUID) async throws {
        let endpoint = "/api/users/\(id.uuidString)"
        let url = try makeURL(endpoint: endpoint)

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"

        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)
    }

    // MARK: - Helper Methods

    private func makeURL(endpoint: String) throws -> URL {
        switch mode {
        case .apiGateway:
            // Standard mode: baseURL + endpoint
            let urlString = baseURL + endpoint
            guard let url = URL(string: urlString) else {
                throw APIError.invalidURL
            }
            return url
        case .localLambda(let invokeEndpoint):
            // Local Lambda mode: use /invoke endpoint
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
        case .apiGateway:
            // Standard mode: direct request
            request.httpMethod = method
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
            request.httpBody = body

        case .localLambda:
            // Local Lambda mode: wrap in API Gateway format
            request.httpMethod = "POST"  // Always POST to /invoke
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let wrappedBody = try wrapRequest(path: endpoint, method: method, body: body, headers: headers)
            request.httpBody = wrappedBody
        }

        let (responseData, response) = try await session.data(for: request)

        switch mode {
        case .apiGateway:
            // Standard mode: validate HTTP response
            try validateResponse(response, data: responseData)
            return (responseData, response)

        case .localLambda:
            // Local Lambda mode: unwrap API Gateway response
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
        let wrapper = try JSONDecoder().decode(APIGatewayResponseWrapper.self, from: data)

        guard (200...299).contains(wrapper.statusCode) else {
            throw APIError.httpError(statusCode: wrapper.statusCode, message: wrapper.body)
        }

        guard let responseData = wrapper.body.data(using: .utf8) else {
            throw APIError.invalidResponse
        }

        return responseData
    }

    private func validateResponse(_ response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw APIError.httpError(statusCode: httpResponse.statusCode, message: message)
        }
    }
}

public enum APIError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int, message: String)
    case decodingError(Error)
    case networkError(Error)

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let statusCode, let message):
            return "HTTP \(statusCode): \(message)"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}
