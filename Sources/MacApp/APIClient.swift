import Foundation

enum APIError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int, message: String)
    case decodingError(Error)
    case networkError(Error)

    var errorDescription: String? {
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

@MainActor
class APIClient: ObservableObject {
    static let shared = APIClient()

    @Published var baseURL: String {
        didSet {
            UserDefaults.standard.set(baseURL, forKey: "apiBaseURL")
        }
    }

    private let session: URLSession

    init() {
        self.session = URLSession.shared
        // Load saved URL or use default
        if let savedURL = UserDefaults.standard.string(forKey: "apiBaseURL") {
            self.baseURL = savedURL
        } else {
            self.baseURL = "https://5kawxqr7e4.execute-api.us-east-1.amazonaws.com/prod"
        }
    }

    // MARK: - File Operations

    /// Test file upload (uploads hardcoded test file)
    func testFileUpload() async throws -> String {
        // Upload a test file using the files endpoint
        let testContent = "Hello World! This data was written/read from S3."
        guard let data = testContent.data(using: .utf8) else {
            throw APIError.invalidResponse
        }

        return try await uploadFile(fileName: "hello-world.text", data: data)
    }

    /// Upload file with custom data and filename
    func uploadFile(fileName: String, data: Data) async throws -> String {
        let endpoint = "/api/files"
        let url = try makeURL(endpoint: endpoint)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let uploadRequest = FileUploadRequest(
            fileName: fileName,
            data: data.base64EncodedString()
        )

        do {
            request.httpBody = try JSONEncoder().encode(uploadRequest)
        } catch {
            throw APIError.networkError(error)
        }

        let (responseData, response) = try await session.data(for: request)
        try validateResponse(response, data: responseData)

        guard let result = String(data: responseData, encoding: .utf8) else {
            throw APIError.invalidResponse
        }
        return result
    }

    /// List all uploaded files
    func listFiles() async throws -> [String] {
        let endpoint = "/api/files"
        let url = try makeURL(endpoint: endpoint)

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)

        do {
            let fileList = try JSONDecoder().decode([String].self, from: data)
            return fileList
        } catch {
            throw APIError.decodingError(error)
        }
    }

    /// Download a specific file
    func downloadFile(fileName: String) async throws -> Data {
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

    // MARK: - Database Operations

    func initializeDatabase() async throws -> String {
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

    func listUsers() async throws -> [User] {
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

    func getUser(id: UUID) async throws -> User {
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

    func createUser(_ userRequest: CreateUserRequest) async throws -> User {
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

    func updateUser(id: UUID, _ userRequest: UpdateUserRequest) async throws -> User {
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

    func deleteUser(id: UUID) async throws {
        let endpoint = "/api/users/\(id.uuidString)"
        let url = try makeURL(endpoint: endpoint)

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"

        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)
    }

    // MARK: - Helper Methods

    private func makeURL(endpoint: String) throws -> URL {
        let urlString = baseURL + endpoint
        guard let url = URL(string: urlString) else {
            throw APIError.invalidURL
        }
        return url
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
