import Client
import Foundation
import SwiftDeploy

/// Connection mode for the API
enum ConnectionMode: String, Codable {
    case remote         // AWS API Gateway
    case localXcode     // Native macOS build (fast)
    case localLinux     // Docker container build (AWS-compatible)

    var displayName: String {
        switch self {
        case .remote:
            return "Remote (API Gateway)"
        case .localXcode:
            return "Local Xcode (Native)"
        case .localLinux:
            return "Local Linux (Container)"
        }
    }

    var detailText: String {
        switch self {
        case .remote:
            return "Connect to deployed AWS API Gateway"
        case .localXcode:
            return "Native macOS build - fast iteration, best for development"
        case .localLinux:
            return "Docker container build - matches AWS Lambda environment"
        }
    }
}

/// Manages API configuration persistence for the MacApp
@MainActor
@Observable
class APIConfiguration {
    var remoteURL: String?
    var mode: ConnectionMode
    var isLoadingRemoteURL: Bool = false

    private let modeKey = "macApp.mode"

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
            let remoteService = RemoteService(
                projectRoot: FileManager.default.currentDirectoryPath,
                awsConfig: awsConfig
            )

            if let apiURL = try await remoteService.getAPIGatewayURL() {
                self.remoteURL = apiURL
            }
        } catch {
            print("Error fetching API Gateway URL: \(error)")
        }
    }

    func save() {
        UserDefaults.standard.set(mode.rawValue, forKey: modeKey)
    }

    func clear() {
        remoteURL = nil
        mode = .remote
        UserDefaults.standard.removeObject(forKey: modeKey)
    }

    var isConfigured: Bool {
        switch mode {
        case .localXcode, .localLinux:
            return true  // Local services are always available
        case .remote:
            return remoteURL != nil
        }
    }
}
