import Foundation
import GitHubSDK
import CLISDK

/// Query for fetching current git and GitHub status.
/// This is a one-shot query (not a streaming workflow) that returns a status snapshot.
public struct GitHubStatusQuery: Sendable {
    private let ghClient: GitHubCLIClient
    private let gitClient: GitClient
    private let branch: String
    private let workflowName: String?

    public init(
        ghClient: GitHubCLIClient,
        gitClient: GitClient,
        branch: String,
        workflowName: String?
    ) {
        self.ghClient = ghClient
        self.gitClient = gitClient
        self.branch = branch
        self.workflowName = workflowName
    }

    /// Get current git and GitHub status.
    /// Returns a StatusSnapshot for refresh operations.
    public func execute() async throws -> GitHubCIStatusSnapshot {
        let gitStatus = GitHubCIGitStatus(
            hasUnpushedCommits: try await gitClient.hasCommitsToPush(),
            hasUncommittedChanges: try await gitClient.hasUncommittedChanges(),
            currentBranch: try await gitClient.getCurrentBranch()
        )

        let latestRun = try await ghClient.getLatestWorkflowRun(branch: branch, workflow: workflowName)
        let runInfo = latestRun.map { WorkflowRunInfo(from: $0) }

        return GitHubCIStatusSnapshot(
            gitStatus: gitStatus,
            latestRun: runInfo
        )
    }
}
