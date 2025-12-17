import Foundation

/// Configuration for GitHub Actions operations
public struct GitHubActionsConfiguration: Codable, Sendable {
    /// Repository in "owner/repo" format (e.g., "gestrich/swift-lambda-sample")
    public let repository: String

    /// Branch to monitor for CI/CD (e.g., "dev", "main")
    public let branch: String

    /// Workflow name or filename to monitor (e.g., "deploy_dev.yml" or "Dev Deploy")
    /// If nil, monitors the latest run from any workflow
    public let workflowName: String?

    public init(repository: String, branch: String, workflowName: String? = nil) {
        self.repository = repository
        self.branch = branch
        self.workflowName = workflowName
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
}

/// Git status information
public struct GitStatus: Sendable, Equatable {
    public let hasUnpushedCommits: Bool
    public let hasUncommittedChanges: Bool
    public let currentBranch: String

    public init(hasUnpushedCommits: Bool, hasUncommittedChanges: Bool, currentBranch: String) {
        self.hasUnpushedCommits = hasUnpushedCommits
        self.hasUncommittedChanges = hasUncommittedChanges
        self.currentBranch = currentBranch
    }
}

/// Information about a workflow run (UI-ready summary)
public struct WorkflowRunInfo: Sendable, Equatable {
    public let id: String
    public let status: String
    public let conclusion: String?
    public let title: String
    public let createdAt: Date?

    public init(id: String, status: String, conclusion: String?, title: String, createdAt: Date?) {
        self.id = id
        self.status = status
        self.conclusion = conclusion
        self.title = title
        self.createdAt = createdAt
    }

    public var isSuccess: Bool {
        conclusion == "success"
    }

    public var isFailed: Bool {
        guard let conclusion else { return false }
        return ["failure", "cancelled", "timed_out"].contains(conclusion)
    }

    public var isInProgress: Bool {
        status == "in_progress" || status == "queued" || status == "pending"
    }

    /// Relative time string (e.g., "2 min ago")
    public var relativeTime: String {
        guard let createdAt else { return "" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: createdAt, relativeTo: Date())
    }
}

extension WorkflowRunInfo {
    /// Create WorkflowRunInfo from a GitHubWorkflowRun
    public init(from run: GitHubWorkflowRun) {
        self.id = run.id
        self.status = run.status
        self.conclusion = run.conclusion
        self.title = run.displayTitle
        self.createdAt = Self.parseGitHubDate(run.createdAt)
    }

    /// Parse GitHub date string to Date
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
