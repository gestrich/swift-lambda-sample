import CLIKit
import Foundation
import Observation
import SwiftDeploy

/// Observable model for GitHub CI operations
/// Holds UI state and delegates operations to GitHubActionsService
@MainActor
@Observable
public final class GitHubCIModel {
    // MARK: - State (source of truth)

    public private(set) var ciStatus = GitHubCIStatus()

    // MARK: - Configuration

    public let config: GitHubConfiguration

    // MARK: - Private Services

    private let actionsService: GitHubActionsService

    // MARK: - Init

    public init(repoPath: String, config: GitHubConfiguration, cliService: CLIService) {
        self.config = config
        self.actionsService = GitHubActionsService(repoPath: repoPath, config: config, cliService: cliService)
    }

    // MARK: - UI State Operations

    /// Refresh GitHub CI status including git state and latest workflow run.
    /// If an in-progress run is detected, automatically starts monitoring it.
    public func refreshStatus() async {
        guard !ciStatus.status.isDeploying else { return }

        ciStatus.status = .loading

        do {
            let gitStatus = try await actionsService.getGitStatus()

            ciStatus.hasUnpushedCommits = gitStatus.hasUnpushedCommits
            ciStatus.hasUncommittedChanges = gitStatus.hasUncommittedChanges
            ciStatus.currentBranch = gitStatus.currentBranch

            if let latestRun = try await actionsService.getLatestWorkflowRun() {
                if !latestRun.isCompleted {
                    ciStatus.status = .deploying(runId: latestRun.id)
                    Task {
                        await self.monitorWorkflowRun(runId: latestRun.id)
                    }
                } else {
                    let runInfo = GitHubCIStatus.WorkflowRunInfo(
                        id: latestRun.id,
                        status: latestRun.status,
                        conclusion: latestRun.conclusion,
                        title: latestRun.displayTitle,
                        createdAt: parseGitHubDate(latestRun.createdAt)
                    )
                    ciStatus.status = .idle(lastRun: runInfo)
                }
            } else {
                ciStatus.status = .idle(lastRun: nil)
            }
        } catch {
            print("Failed to refresh GitHub CI status: \(error)")
            ciStatus.status = .idle(lastRun: nil)
        }
    }

    /// Push commits and deploy via GitHub Actions with polling progress
    public func pushAndDeploy(output: CLIOutputStream? = nil) async throws {
        ciStatus.runDetail = nil

        do {
            ciStatus.status = .deploying(runId: "pending")

            let runId = try await actionsService.pushAndTriggerWorkflow(output: output)

            ciStatus.status = .deploying(runId: runId)

            await monitorWorkflowRun(runId: runId)
        } catch {
            ciStatus.status = .failed(runId: "", reason: error.localizedDescription)
            throw error
        }
    }

    /// Open workflow logs in browser
    public func viewWorkflowLogs(runId: String) async throws {
        try await actionsService.openWorkflowLogs(runId: runId)
    }

    // MARK: - Private Helpers

    private func monitorWorkflowRun(runId: String) async {
        for await progress in actionsService.monitorWorkflowRun(runId: runId) {
            switch progress {
            case .inProgress(let detail):
                ciStatus.runDetail = detail
            case .success(let runId):
                ciStatus.status = .success(runId: runId)
                ciStatus.runDetail = nil
            case .failed(let reason):
                ciStatus.status = .failed(runId: runId, reason: reason)
                ciStatus.runDetail = nil
            }
        }
    }

    private func parseGitHubDate(_ dateString: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: dateString) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: dateString)
    }
}

/// State for GitHub CI workflow tracking
public struct GitHubCIStatus: Equatable {
    public enum RunStatus: Equatable {
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
    public struct WorkflowRunInfo: Equatable {
        public let id: String
        public let status: String
        public let conclusion: String?
        public let title: String
        public let createdAt: Date?

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

    public var status: RunStatus = .unknown
    public var runDetail: GitHubRunDetail?
    public var hasUnpushedCommits: Bool = false
    public var hasUncommittedChanges: Bool = false
    public var currentBranch: String = ""

    public init() {}
}
