//
//  AWSAuthConfiguration+Persistence.swift
//  service-deploy
//
//  App-specific persistence for AWSAuthConfiguration
//

import Foundation
import service_storage
import sdk_aws

// Re-export SDK types for feature-mac and other consumers
// This allows feature-mac to depend only on service-deploy, not directly on sdk-aws
@_exported import struct sdk_aws.AWSAuthConfiguration
@_exported import struct sdk_aws.CloudWatchLogEntry
@_exported import enum sdk_aws.CloudWatchLogsProgress

// CloudFormation state types used by views
@_exported import enum sdk_aws.DeploymentState
@_exported import struct sdk_aws.DeploymentProgress
@_exported import struct sdk_aws.ResourceProgress
@_exported import enum sdk_aws.ResourceStatus

// MARK: - Storage Keys

/// Storage key for AWS configuration file
public struct AWSConfigFileKey: StorageFileKey {
    public static let filename = "aws-config.json"
}

// MARK: - Persistence

extension AWSAuthConfiguration {
    private static let storageService = LocalStorageService()

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
