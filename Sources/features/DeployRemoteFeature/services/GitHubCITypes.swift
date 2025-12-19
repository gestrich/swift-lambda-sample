import Foundation
import GitHubSDK

// MARK: - Shared State Types for GitHub CI Use Cases

/// Lightweight snapshot for status refresh (not a completed operation).
public struct GitHubCIStatusSnapshot: Sendable, Equatable {
    public let gitStatus: GitHubCIGitStatus
    public let latestRun: WorkflowRunInfo?

    public init(gitStatus: GitHubCIGitStatus, latestRun: WorkflowRunInfo?) {
        self.gitStatus = gitStatus
        self.latestRun = latestRun
    }

    /// Whether there's an in-progress run that should be monitored
    public var inProgressRunId: String? {
        guard let run = latestRun, run.isInProgress else { return nil }
        return run.id
    }
}

/// Complete snapshot of GitHub CI state (yielded on completion).
/// Contains all data needed for display.
public struct GitHubCISnapshot: Sendable, Equatable {
    public let status: Status
    public let gitStatus: GitHubCIGitStatus
    public let runDetail: GitHubRunDetail?

    public enum Status: Sendable, Equatable {
        case idle(lastRun: WorkflowRunInfo?)
        case success(runId: String)
        case failed(runId: String, reason: String)
    }

    public init(status: Status, gitStatus: GitHubCIGitStatus, runDetail: GitHubRunDetail?) {
        self.status = status
        self.gitStatus = gitStatus
        self.runDetail = runDetail
    }

    // MARK: - Convenience Accessors

    public var runId: String? {
        switch status {
        case .idle(let lastRun): return lastRun?.id
        case .success(let id), .failed(let id, _): return id
        }
    }

    public var canDeploy: Bool { true }

    // MARK: - Factory Methods

    public static func success(runId: String, gitStatus: GitHubCIGitStatus) -> GitHubCISnapshot {
        GitHubCISnapshot(status: .success(runId: runId), gitStatus: gitStatus, runDetail: nil)
    }

    public static func failed(runId: String, reason: String, gitStatus: GitHubCIGitStatus) -> GitHubCISnapshot {
        GitHubCISnapshot(status: .failed(runId: runId, reason: reason), gitStatus: gitStatus, runDetail: nil)
    }

    public static func idle(lastRun: WorkflowRunInfo?, gitStatus: GitHubCIGitStatus) -> GitHubCISnapshot {
        GitHubCISnapshot(status: .idle(lastRun: lastRun), gitStatus: gitStatus, runDetail: nil)
    }
}

/// Git status information
public struct GitHubCIGitStatus: Sendable, Equatable {
    public let hasUnpushedCommits: Bool
    public let hasUncommittedChanges: Bool
    public let currentBranch: String

    public init(hasUnpushedCommits: Bool, hasUncommittedChanges: Bool, currentBranch: String) {
        self.hasUnpushedCommits = hasUnpushedCommits
        self.hasUncommittedChanges = hasUncommittedChanges
        self.currentBranch = currentBranch
    }

    public static let empty = GitHubCIGitStatus(
        hasUnpushedCommits: false,
        hasUncommittedChanges: false,
        currentBranch: ""
    )
}

/// State yielded by GitHub CI streaming use cases.
public enum GitHubCIState: Sendable, Equatable {
    case deploying(GitHubCIDeployProgress)
    case completed(GitHubCISnapshot)

    /// Start time from any in-progress state
    public var startTime: Date? {
        if case .deploying(let p) = self { return p.startTime }
        return nil
    }

    /// Final snapshot if completed
    public var completedSnapshot: GitHubCISnapshot? {
        if case .completed(let snapshot) = self { return snapshot }
        return nil
    }
}

/// Progress during deployment operations
public struct GitHubCIDeployProgress: Sendable, Equatable {
    public let step: GitHubCIStep
    public let startTime: Date
    public let runDetail: GitHubRunDetail?

    public init(step: GitHubCIStep, startTime: Date, runDetail: GitHubRunDetail? = nil) {
        self.step = step
        self.startTime = startTime
        self.runDetail = runDetail
    }
}

/// Steps in a deployment operation
public enum GitHubCIStep: Sendable, Equatable {
    case checkingGitStatus
    case pushing
    case triggering(workflow: String)
    case waitingForWorkflow
    case monitoring(runId: String)
}

// MARK: - Errors

public enum GitHubCIUseCaseError: Error, LocalizedError {
    case timeout(operation: String, duration: Duration)
    case githubActionsFailed(runId: String, conclusion: String)

    public var errorDescription: String? {
        switch self {
        case .timeout(let operation, let duration):
            return "Timeout during \(operation) after \(duration)"
        case .githubActionsFailed(let runId, let conclusion):
            return "GitHub Actions run \(runId) failed: \(conclusion)"
        }
    }
}

// MARK: - WorkflowRunInfo Extension

extension WorkflowRunInfo {
    /// Create from a GitHubWorkflowRun
    public init(from run: GitHubWorkflowRun) {
        self.init(
            id: run.id,
            status: run.status,
            conclusion: run.conclusion,
            title: run.displayTitle,
            createdAt: Self.parseGitHubDate(run.createdAt)
        )
    }

    private static func parseGitHubDate(_ dateString: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: dateString) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: dateString)
    }
}
