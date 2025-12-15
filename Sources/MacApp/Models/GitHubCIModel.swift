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

        // Fetch status from GitHub immediately on init
        Task {
            await self.refreshStatus()
        }
    }

    // MARK: - UI State Operations

    /// Refresh GitHub CI status including git state and latest workflow run.
    /// If an in-progress run is detected, automatically starts monitoring it.
    public func refreshStatus() async {
        guard !ciStatus.status.isDeploying else { return }

        ciStatus.status = .loading

        do {
            let snapshot = try await actionsService.getFullStatus()

            ciStatus.hasUnpushedCommits = snapshot.gitStatus.hasUnpushedCommits
            ciStatus.hasUncommittedChanges = snapshot.gitStatus.hasUncommittedChanges
            ciStatus.currentBranch = snapshot.gitStatus.currentBranch

            if let inProgressId = snapshot.inProgressRunId {
                ciStatus.status = .deploying(runId: inProgressId)
                Task { await monitorWorkflowRun(runId: inProgressId) }
            } else {
                ciStatus.status = .idle(lastRun: snapshot.latestRun)
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

    public var status: RunStatus = .unknown
    public var runDetail: GitHubRunDetail?
    public var hasUnpushedCommits: Bool = false
    public var hasUncommittedChanges: Bool = false
    public var currentBranch: String = ""

    public init() {}
}
