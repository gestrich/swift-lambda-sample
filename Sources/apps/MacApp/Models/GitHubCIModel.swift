import AppKit
import CLISDK
import DeployCoreService
import GitHubSDK
import Foundation
import Observation
import DeployRemoteFeature

/// Observable model for GitHub CI operations.
/// This is a thin model that uses GitHub CI workflows and maintains observable state.
///
/// Per the layered architecture:
/// - App layer (this model): @Observable state + UI coordination
/// - Service layer (workflows): Multi-step orchestration, returns AsyncThrowingStream
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

    private let pushAndDeployUseCase: GitHubPushAndDeployUseCase
    private let monitorRunUseCase: GitHubMonitorRunUseCase
    private let statusQuery: GitHubStatusQuery

    // MARK: - Init

    /// Initialize with use cases and configuration.
    /// Automatically refreshes status on init.
    public init(
        pushAndDeployUseCase: GitHubPushAndDeployUseCase,
        monitorRunUseCase: GitHubMonitorRunUseCase,
        statusQuery: GitHubStatusQuery,
        repository: String,
        branch: String
    ) {
        self.pushAndDeployUseCase = pushAndDeployUseCase
        self.monitorRunUseCase = monitorRunUseCase
        self.statusQuery = statusQuery
        self.repository = repository
        self.branch = branch
        Task { await refresh() }
    }

    /// Convenience initializer that loads config from disk.
    /// - Throws: If GitHub configuration is not found.
    public convenience init(projectRoot: String) throws {
        guard let config = GitHubConfiguration.loadConfig() else {
            throw DeployError.configurationMissing(
                file: GitHubConfiguration.configPath,
                hint: "Create GitHub configuration file"
            )
        }
        let cliClient = CLIClient(defaultWorkingDirectory: projectRoot)
        self.init(projectRoot: projectRoot, config: config, cliClient: cliClient)
    }

    /// Convenience initializer that creates the use cases from configuration.
    public convenience init(projectRoot: String, config: GitHubConfiguration, cliClient: CLIClient) {
        let ghClient = GitHubCLIClient(repository: config.repository, cliClient: cliClient)
        let gitClient = GitClient(repoPath: projectRoot, cliClient: cliClient)

        let pushAndDeployUseCase = GitHubPushAndDeployUseCase(
            ghClient: ghClient,
            gitClient: gitClient,
            branch: config.branch,
            workflowName: config.workflowName
        )

        let monitorRunUseCase = GitHubMonitorRunUseCase(
            ghClient: ghClient,
            gitClient: gitClient
        )

        let statusQuery = GitHubStatusQuery(
            ghClient: ghClient,
            gitClient: gitClient,
            branch: config.branch,
            workflowName: config.workflowName
        )

        self.init(
            pushAndDeployUseCase: pushAndDeployUseCase,
            monitorRunUseCase: monitorRunUseCase,
            statusQuery: statusQuery,
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
            let statusSnapshot = try await statusQuery.execute()

            // Check if a workflow run is in progress and resume monitoring
            if let inProgressId = statusSnapshot.inProgressRunId {
                await monitorRun(runId: inProgressId, timeoutMinutes: 20)
            } else {
                state = .ready(GitHubCISnapshot.idle(
                    lastRun: statusSnapshot.latestRun,
                    gitStatus: statusSnapshot.gitStatus
                ))
            }
        } catch {
            print("Failed to refresh GitHub CI status: \(error)")
            state = .ready(GitHubCISnapshot.failed(
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
            let options = GitHubPushAndDeployUseCase.Options(timeoutMinutes: timeoutMinutes)
            for try await useCaseState in pushAndDeployUseCase.stream(options: options) {
                state = ModelState(from: useCaseState, prior: prior)
            }
        } catch {
            state = .ready(GitHubCISnapshot.failed(
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
            let options = GitHubMonitorRunUseCase.Options(runId: runId, timeoutMinutes: timeoutMinutes)
            for try await useCaseState in monitorRunUseCase.stream(options: options) {
                state = ModelState(from: useCaseState, prior: prior)
            }
        } catch {
            state = .ready(GitHubCISnapshot.failed(
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
    /// Uses service-layer types (GitHubCIState, GitHubCISnapshot) for actual state,
    /// while ModelState handles app-layer concerns (loading, prior preservation).
    public enum ModelState: Equatable {
        case uninitialized
        case loading(prior: GitHubCISnapshot?)
        case ready(GitHubCISnapshot)
        case operating(GitHubCIState, prior: GitHubCISnapshot?)

        // MARK: - Convenience Initializer

        /// Construct ModelState from a workflow state plus app-layer prior.
        /// This is the key integration point between workflows and the model.
        public init(from workflowState: GitHubCIState, prior: GitHubCISnapshot?) {
            if let snapshot = workflowState.completedSnapshot {
                self = .ready(snapshot)
            } else {
                self = .operating(workflowState, prior: prior)
            }
        }

        // MARK: - Convenience Accessors

        public var snapshot: GitHubCISnapshot? {
            switch self {
            case .uninitialized: return nil
            case .loading(let prior): return prior
            case .ready(let snapshot): return snapshot
            case .operating(_, let prior): return prior
            }
        }

        public var workflowState: GitHubCIState? {
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

        public var gitStatus: GitHubCIGitStatus {
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
