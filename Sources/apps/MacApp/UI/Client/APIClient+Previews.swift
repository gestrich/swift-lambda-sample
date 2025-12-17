import ClientService

extension APIClient {
    /// A placeholder APIClient for SwiftUI previews.
    /// Note: This client uses a non-functional URL and won't make real network requests.
    static var preview: APIClient {
        APIClient(baseURL: "http://localhost:8080/api", serviceName: "Preview")
    }
}
