//
//  GitHubConfiguration.swift
//  SwiftDeploy
//
//  GitHub configuration for CI/CD integration with file persistence
//

import Foundation
import service_storage
import sdk_github

/// GitHub configuration for SwiftDeploy with file persistence
/// This extends the SDK's GitHubActionsConfiguration with file loading/saving capabilities
public struct GitHubConfiguration: Codable, Sendable {
    /// Repository in "owner/repo" format (e.g., "gestrich/swift-lambda-sample")
    public let repository: String

    /// Branch to monitor for CI/CD (e.g., "dev", "main")
    public let branch: String

    /// Workflow name or filename to monitor (e.g., "deploy_dev.yml" or "Dev Deploy")
    /// If nil, monitors the latest run from any workflow
    public let workflowName: String?

    private static let storageService = LocalStorageService()

    public init(repository: String, branch: String, workflowName: String? = nil) {
        self.repository = repository
        self.branch = branch
        self.workflowName = workflowName
    }

    // MARK: - Configuration File

    /// Path to GitHub configuration file
    public static var configPath: String {
        storageService.filePath(for: GitHubConfigFileKey.self)
    }

    /// Load GitHub configuration from file
    /// - Returns: Configuration if file exists and is valid, nil otherwise
    public static func loadConfig() -> GitHubConfiguration? {
        guard FileManager.default.fileExists(atPath: configPath) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: configPath))
            return try JSONDecoder().decode(GitHubConfiguration.self, from: data)
        } catch {
            print("Warning: Failed to read GitHub config from \(configPath): \(error)")
            return nil
        }
    }

    /// Save configuration to file
    public func save() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)

        let url = URL(fileURLWithPath: Self.configPath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url)
    }

    // MARK: - Derived Properties

    /// Owner part of the repository (e.g., "gestrich")
    public var owner: String {
        repository.components(separatedBy: "/").first ?? ""
    }

    /// Repo name part of the repository (e.g., "swift-lambda-sample")
    public var repoName: String {
        repository.components(separatedBy: "/").last ?? ""
    }

    // MARK: - SDK Conversion

    /// Convert to SDK configuration type
    public func toSDKConfiguration() -> GitHubActionsConfiguration {
        GitHubActionsConfiguration(
            repository: repository,
            branch: branch,
            workflowName: workflowName
        )
    }
}

// MARK: - Storage Keys

/// Storage key for GitHub configuration file
public struct GitHubConfigFileKey: StorageFileKey {
    public static let filename = "github-config.json"
}
