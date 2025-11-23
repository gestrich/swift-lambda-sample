import Client
import Foundation

enum ConnectionMode: String, Codable {
    case remote
    case local
}

/// Manages API configuration persistence for the MacApp
@MainActor
@Observable
class APIConfiguration {
    var remoteURL: String?
    var localEndpoint: String?
    var mode: ConnectionMode

    private let remoteURLKey = "macApp.remoteURL"
    private let localEndpointKey = "macApp.localEndpoint"
    private let modeKey = "macApp.mode"

    init() {
        // Load saved configuration from UserDefaults (no defaults)
        self.remoteURL = UserDefaults.standard.string(forKey: remoteURLKey)
        self.localEndpoint = UserDefaults.standard.string(forKey: localEndpointKey)

        // Load mode enum
        if let modeString = UserDefaults.standard.string(forKey: modeKey),
           let savedMode = ConnectionMode(rawValue: modeString) {
            self.mode = savedMode
        } else {
            self.mode = .remote  // Default to remote
        }
    }

    func save() {
        if let remoteURL = remoteURL {
            UserDefaults.standard.set(remoteURL, forKey: remoteURLKey)
        }
        if let localEndpoint = localEndpoint {
            UserDefaults.standard.set(localEndpoint, forKey: localEndpointKey)
        }
        UserDefaults.standard.set(mode.rawValue, forKey: modeKey)
    }

    func clear() {
        remoteURL = nil
        localEndpoint = nil
        mode = .remote
        UserDefaults.standard.removeObject(forKey: remoteURLKey)
        UserDefaults.standard.removeObject(forKey: localEndpointKey)
        UserDefaults.standard.removeObject(forKey: modeKey)
    }

    var isConfigured: Bool {
        switch mode {
        case .local:
            return localEndpoint != nil
        case .remote:
            return remoteURL != nil
        }
    }

    func createAPIClient() -> APIClient? {
        switch mode {
        case .local:
            guard let endpoint = localEndpoint else { return nil }
            return APIClient(
                baseURL: "http://localhost:8080",
                mode: .localLambda(endpoint: endpoint)
            )
        case .remote:
            guard let url = remoteURL else { return nil }
            return APIClient(
                baseURL: url,
                mode: .apiGateway
            )
        }
    }
}
