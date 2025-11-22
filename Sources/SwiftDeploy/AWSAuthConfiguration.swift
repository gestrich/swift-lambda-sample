//
//  AWSAuthConfiguration.swift
//  SwiftDeploy
//
//  AWS authentication configuration for deployment tooling
//

import Foundation

/// AWS authentication configuration for SwiftDeploy CLI
public struct AWSAuthConfiguration: Codable {
    public let profileName: String

    public init(profileName: String) {
        self.profileName = profileName
    }

    // MARK: - Configuration File

    /// Path to AWS configuration file
    private static var configPath: String {
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

    // MARK: - Profile Resolution

    /// Get AWS profile from CLI option or config file
    /// - Parameter cliProfile: Optional profile from --aws-profile flag
    /// - Returns: Resolved profile name
    /// - Throws: CLIError if no profile is configured
    public static func getProfile(from cliProfile: String?) throws -> String {
        if let cliProfile = cliProfile {
            return cliProfile
        } else if let config = loadConfig() {
            return config.profileName
        } else {
            let errorMessage = """
                AWS profile not specified. Either:
                  1. Pass --aws-profile <name>, OR
                  2. Configure profileName in ~/.swiftSampleDemo/aws-config.json

                Example aws-config.json:
                {
                  "profileName": "production"
                }
                """
            throw CLIError.invalidCommand(errorMessage)
        }
    }
}
