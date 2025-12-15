//
//  AWSAuthConfiguration.swift
//  SwiftDeploy
//
//  AWS authentication configuration for deployment tooling
//

import Foundation
import service_storage

/// AWS authentication configuration for SwiftDeploy CLI
public struct AWSAuthConfiguration: Codable, Sendable {
    public let profileName: String
    public let useAWSVault: Bool

    private static let storageService = LocalStorageService()

    public init(profileName: String, useAWSVault: Bool = false) {
        self.profileName = profileName
        self.useAWSVault = useAWSVault
    }

    // MARK: - Configuration File

    /// Path to AWS configuration file
    public static var configPath: String {
        storageService.filePath(for: AWSConfigFileKey.self)
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

    /// Save AWS auth configuration to file
    /// - Throws: Error if unable to create directory or write file
    public func save() throws {
        let url = URL(fileURLWithPath: Self.configPath)
        let directory = url.deletingLastPathComponent()

        // Create directory if needed
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try data.write(to: url)
    }
}

// MARK: - Storage Keys

/// Storage key for AWS configuration file
public struct AWSConfigFileKey: StorageFileKey {
    public static let filename = "aws-config.json"
}
