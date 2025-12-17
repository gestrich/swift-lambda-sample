import AppKit
import sdk_cli
import sdk_github
import Foundation
import Observation
import service_deploy_remote
import workflows_deploy_remote

/// Observable model for GitHub CI operations.
/// This is a thin model that uses GitHubCIWorkflow and maintains observable state.
///
/// Per the layered architecture:
/// - App layer (this model): @Observable state + UI coordination
/// - Service layer (workflow): Multi-step orchestration, returns AsyncThrowingStream
/// - SDK layer (clients): Stateless execute/query operations
@MainActor
@Observable
public final class GitHubCIModel {
    // MARK: - Unified State Machine

    /// Single source of truth for all model state
    public private(set) var state: ModelState = .uninitialized

    // MARK: - Configuration

    public let repository: String
    public let branch: String

    // MARK: - Private

    private let workflow: GitHubCIWorkflow

    // MARK: - Init

    /// Initialize with a workflow and configuration.
    /// Note: Does NOT automatically refresh status. Call `refresh()` explicitly after init.
    public init(workflow: GitHubCIWorkflow, repository: String, branch: String) {
        self.workflow = workflow
        self.repository = repository
        self.branch = branch
    }

    /// Convenience initializer that creates the workflow from configuration.
    public convenience init(projectRoot: String, config: GitHubConfiguration, cliClient: CLIClient) {
        let ghClient = GitHubCLIClient(repository: config.repository, cliClient: cliClient)
        let gitClient = GitClient(repoPath: projectRoot, cliClient: cliClient)

        let workflow = GitHubCIWorkflow(
            ghClient: ghClient,
            gitClient: gitClient,
            repository: config.repository,
            branch: config.branch,
            workflowName: config.workflowName
        )

        self.init(
            workflow: workflow,
            repository: config.repository,
            branch: config.branch
        )
    }

    // MARK: - Derived State (Convenience Accessors)

    public var isIdle: Bool { state.isIdle }
    public var canDeploy: Bool { state.canDeploy }

    // MARK: - Refresh Operations

    /// Refresh status from GitHub.
    /// If an operation is in progress, automatically starts monitoring it.
    public func refresh() async {
        guard state.isIdle else { return }

        let prior = state.snapshot
        state = .loading(prior: prior)

        do {
            let statusSnapshot = try await workflow.getStatus()

            // Check if a workflow run is in progress and resume monitoring
            if let inProgressId = statusSnapshot.inProgressRunId {
                await monitorRun(runId: inProgressId, timeoutMinutes: 20)
            } else {
                state = .ready(GitHubCIWorkflow.Snapshot.idle(
                    lastRun: statusSnapshot.latestRun,
                    gitStatus: statusSnapshot.gitStatus
                ))
            }
        } catch {
            print("Failed to refresh GitHub CI status: \(error)")
            state = .ready(GitHubCIWorkflow.Snapshot.failed(
                runId: "",
                reason: error.localizedDescription,
                gitStatus: prior?.gitStatus ?? .empty
            ))
        }
    }

    // MARK: - Deploy Operations

    /// Push commits and deploy via GitHub Actions.
    public func pushAndDeploy(timeoutMinutes: Int = 20) async {
        guard state.canDeploy else { return }

        let prior = state.snapshot

        do {
            for try await workflowState in workflow.pushAndDeploy(timeoutMinutes: timeoutMinutes) {
                state = ModelState(from: workflowState, prior: prior)
            }
        } catch {
            state = .ready(GitHubCIWorkflow.Snapshot.failed(
                runId: "",
                reason: error.localizedDescription,
                gitStatus: prior?.gitStatus ?? .empty
            ))
        }
    }

    /// Monitor an existing workflow run.
    public func monitorRun(runId: String, timeoutMinutes: Int) async {
        let prior = state.snapshot

        do {
            for try await workflowState in workflow.monitorRun(runId: runId, timeoutMinutes: timeoutMinutes) {
                state = ModelState(from: workflowState, prior: prior)
            }
        } catch {
            state = .ready(GitHubCIWorkflow.Snapshot.failed(
                runId: runId,
                reason: error.localizedDescription,
                gitStatus: prior?.gitStatus ?? .empty
            ))
        }
    }

    /// Open workflow logs in browser.
    public func viewWorkflowLogs(runId: String) {
        let url = "https://github.com/\(repository)/actions/runs/\(runId)"
        if let nsURL = URL(string: url) {
            NSWorkspace.shared.open(nsURL)
        }
    }

    // MARK: - Nested Types

    /// Unified state machine for the GitHub CI model.
    /// Uses service-layer types (GitHubCIWorkflow.State, Snapshot) for actual state,
    /// while ModelState handles app-layer concerns (loading, prior preservation).
    public enum ModelState: Equatable {
        case uninitialized
        case loading(prior: GitHubCIWorkflow.Snapshot?)
        case ready(GitHubCIWorkflow.Snapshot)
        case operating(GitHubCIWorkflow.State, prior: GitHubCIWorkflow.Snapshot?)

        // MARK: - Convenience Initializer

        /// Construct ModelState from a workflow state plus app-layer prior.
        /// This is the key integration point between workflows and the model.
        public init(from workflowState: GitHubCIWorkflow.State, prior: GitHubCIWorkflow.Snapshot?) {
            if let snapshot = workflowState.completedSnapshot {
                self = .ready(snapshot)
            } else {
                self = .operating(workflowState, prior: prior)
            }
        }

        // MARK: - Convenience Accessors

        public var snapshot: GitHubCIWorkflow.Snapshot? {
            switch self {
            case .uninitialized: return nil
            case .loading(let prior): return prior
            case .ready(let snapshot): return snapshot
            case .operating(_, let prior): return prior
            }
        }

        public var workflowState: GitHubCIWorkflow.State? {
            if case .operating(let state, _) = self { return state }
            return nil
        }

        public var isIdle: Bool {
            switch self {
            case .uninitialized, .ready: return true
            case .loading, .operating: return false
            }
        }

        public var canDeploy: Bool {
            switch self {
            case .ready(let snapshot): return snapshot.canDeploy
            case .uninitialized: return true
            case .loading, .operating: return false
            }
        }

        /// Run detail from workflow state (for UI during monitoring)
        public var runDetail: GitHubRunDetail? {
            guard case .operating(let workflowState, _) = self,
                  case .deploying(let progress) = workflowState else {
                return nil
            }
            return progress.runDetail
        }

        /// Operation start time (for elapsed time display)
        public var operationStartTime: Date? {
            workflowState?.startTime
        }

        /// Whether currently deploying
        public var isDeploying: Bool {
            if case .operating = self { return true }
            return false
        }

        /// Current run ID (from various states)
        public var runId: String? {
            switch self {
            case .uninitialized, .loading:
                return nil
            case .ready(let snapshot):
                return snapshot.runId
            case .operating(let workflowState, _):
                if case .deploying(let progress) = workflowState,
                   case .monitoring(let runId) = progress.step {
                    return runId
                }
                return nil
            }
        }

        // MARK: - Git Status Accessors

        public var gitStatus: GitHubCIWorkflow.GitStatus {
            snapshot?.gitStatus ?? .empty
        }

        public var hasUnpushedCommits: Bool {
            gitStatus.hasUnpushedCommits
        }

        public var hasUncommittedChanges: Bool {
            gitStatus.hasUncommittedChanges
        }

        public var currentBranch: String {
            gitStatus.currentBranch
        }
    }
}
