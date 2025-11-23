import Client
import Foundation
import SwiftDeploy

enum ConnectionMode: String, Codable {
    case remote
    case local
}

/// Manages API configuration persistence for the MacApp
@MainActor
@Observable
class APIConfiguration {
    var remoteURL: String?
    var mode: ConnectionMode
    var isLoadingRemoteURL: Bool = false

    private let modeKey = "macApp.mode"

    // Local endpoint from LocalDevelopmentService
    private var localEndpoint: String {
        LocalDevelopmentService(workingDirectory: FileManager.default.currentDirectoryPath).localEndpoint
    }

    init() {
        // Load mode from UserDefaults
        if let modeString = UserDefaults.standard.string(forKey: modeKey),
           let savedMode = ConnectionMode(rawValue: modeString) {
            self.mode = savedMode
        } else {
            self.mode = .remote  // Default to remote
        }
    }

    /// Fetch the API Gateway URL from deployed CDK stack
    func fetchRemoteURLFromCDK() async {
        isLoadingRemoteURL = true
        defer { isLoadingRemoteURL = false }

        // Load AWS config
        guard let awsConfig = AWSAuthConfiguration.loadConfig() else {
            print("Warning: No AWS config found at ~/.swiftSampleDemo/aws-config.json")
            return
        }

        // Check if aws-vault is enabled (not supported in GUI apps)
        if awsConfig.useAWSVault {
            print("Error: aws-vault is not supported in MacApp (GUI apps cannot access keychain)")
            print("Solution: Update ~/.swiftSampleDemo/aws-config.json and set \"useAWSVault\": false")
            print("Then ensure your AWS credentials are in ~/.aws/credentials")
            return
        }

        do {
            let deploymentService = DeploymentService(
                projectRoot: FileManager.default.currentDirectoryPath,
                awsConfig: awsConfig
            )

            if let apiURL = try await deploymentService.getAPIGatewayURL() {
                self.remoteURL = apiURL
            }
        } catch {
            print("Error fetching API Gateway URL: \(error)")
        }
    }

    func save() {
        // Only save the mode preference - URL is fetched from CDK, local endpoint is hardcoded
        UserDefaults.standard.set(mode.rawValue, forKey: modeKey)
    }

    func clear() {
        remoteURL = nil
        mode = .remote
        UserDefaults.standard.removeObject(forKey: modeKey)
    }

    var isConfigured: Bool {
        switch mode {
        case .local:
            return true  // Local endpoint is always configured (hardcoded)
        case .remote:
            return remoteURL != nil
        }
    }

    func createAPIClient() -> APIClient? {
        switch mode {
        case .local:
            return APIClient(
                baseURL: "http://localhost:8080",
                mode: .localLambda(endpoint: localEndpoint)
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
