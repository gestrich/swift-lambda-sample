import sdk_cli
import sdk_github
import Foundation

// Re-export SDK types for backwards compatibility
public typealias GitHubActionsService = GitHubActionsClient
public typealias GitService = GitClient
public typealias GitHubCLIService = GitHubCLIClient

// Also export the SDK types directly for use with new code
@_exported import class sdk_github.GitClient
@_exported import class sdk_github.GitHubActionsClient
@_exported import class sdk_github.GitHubCLIClient

// Re-export all SDK types that were previously defined here
// These are now in sdk-github but consumers expect them from service-deploy
@_exported import struct sdk_github.GitStatus
@_exported import enum sdk_github.WorkflowProgress
@_exported import struct sdk_github.GitHubCISnapshot
@_exported import struct sdk_github.WorkflowRunInfo
@_exported import struct sdk_github.GitHubWorkflowRun
@_exported import struct sdk_github.GitHubRunDetail
@_exported import struct sdk_github.GitHubJob
@_exported import struct sdk_github.GitHubStep
@_exported import struct sdk_github.GitHubPullRequest

/// Factory function to create GitHubActionsClient from service-layer GitHubConfiguration
public func makeGitHubActionsClient(
    repoPath: String,
    config: GitHubConfiguration,
    cliClient: CLIClient
) -> GitHubActionsClient {
    GitHubActionsClient(repoPath: repoPath, config: config.toSDKConfiguration(), cliClient: cliClient)
}
