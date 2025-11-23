//
//  AWSAuthConfiguration.swift
//  SwiftDeploy
//
//  AWS authentication configuration for deployment tooling
//

import Foundation

/// AWS authentication configuration for SwiftDeploy CLI
public struct AWSAuthConfiguration: Codable, Sendable {
    public let profileName: String
    public let useAWSVault: Bool

    public init(profileName: String, useAWSVault: Bool = false) {
        self.profileName = profileName
        self.useAWSVault = useAWSVault
    }

    // MARK: - Configuration File

    /// Path to AWS configuration file
    public static var configPath: String {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        return homeDir.appendingPathComponent(".swiftSampleDemo/aws-config.json").path
    }

    /// Load AWS auth configuration from file
    /// - Returns: Configuration if file exists and is valid, nil otherwise
    public static func loadConfig() -> AWSAuthConfiguration? {
        guard FileManager.default.fileExists(atPath: configPath) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: configPath))
            return try JSONDecoder().decode(AWSAuthConfiguration.self, from: data)
        } catch {
            print("Warning: Failed to read AWS config from \(configPath): \(error)")
            return nil
        }
    }
}
