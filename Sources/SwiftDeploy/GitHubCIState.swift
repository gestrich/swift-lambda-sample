import CLIKit
import Foundation
import Observation

/// State for GitHub CI workflow tracking
@MainActor
@Observable
public final class GitHubCIState {
    /// Current status of the GitHub Actions workflow
    public enum Status: Equatable, Sendable {
        case unknown
        case loading
        case idle(lastRun: WorkflowRunInfo?)
        case deploying(runId: String)
        case success(runId: String)
        case failed(runId: String, reason: String)

        public var isDeploying: Bool {
            if case .deploying = self { return true }
            return false
        }

        public var canDeploy: Bool {
            switch self {
            case .loading, .deploying:
                return false
            default:
                return true
            }
        }

        public var runId: String? {
            switch self {
            case .deploying(let id), .success(let id), .failed(let id, _):
                return id
            case .idle(let lastRun):
                return lastRun?.id
            default:
                return nil
            }
        }
    }

    /// Information about a workflow run (summary)
    public struct WorkflowRunInfo: Equatable, Sendable {
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

    // MARK: - Properties

    public private(set) var status: Status = .unknown
    public private(set) var runDetail: GitHubRunDetail?
    public private(set) var hasUnpushedCommits: Bool = false
    public private(set) var hasUncommittedChanges: Bool = false
    public private(set) var currentBranch: String = ""

    // MARK: - Public Methods

    public init() {}

    public func setLoading() {
        status = .loading
        runDetail = nil
    }

    public func setIdle(lastRun: WorkflowRunInfo?) {
        status = .idle(lastRun: lastRun)
    }

    public func setDeploying(runId: String) {
        status = .deploying(runId: runId)
    }

    public func updateRunDetail(_ detail: GitHubRunDetail) {
        runDetail = detail
    }

    public func setSuccess(runId: String) {
        status = .success(runId: runId)
    }

    public func setFailed(runId: String, reason: String) {
        status = .failed(runId: runId, reason: reason)
    }

    public func updateGitStatus(hasUnpushedCommits: Bool, hasUncommittedChanges: Bool, branch: String) {
        self.hasUnpushedCommits = hasUnpushedCommits
        self.hasUncommittedChanges = hasUncommittedChanges
        self.currentBranch = branch
    }

    public func clearRunDetail() {
        runDetail = nil
    }
}
