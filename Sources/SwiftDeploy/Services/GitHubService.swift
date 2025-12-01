import CLIKit
import Foundation
import Observation

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

/// Service for GitHub Actions operations with UI state management
@MainActor
@Observable
public final class GitHubService {
    // MARK: - State (source of truth)

    public private(set) var ciStatus = GitHubCIStatus()

    // MARK: - Configuration

    public let config: GitHubConfiguration

    // MARK: - Private Services

    private let ghCLIService: GitHubCLIService
    private let gitService: GitService

    // MARK: - Init

    public init(repoPath: String, config: GitHubConfiguration) {
        self.config = config
        self.ghCLIService = GitHubCLIService(repository: config.repository)
        self.gitService = GitService(repoPath: repoPath)
    }

    // MARK: - UI State Operations

    /// Refresh GitHub CI status including git state and latest workflow run.
    /// If an in-progress run is detected, automatically starts monitoring it.
    public func refreshStatus() async {
        // Don't refresh if we're already deploying
        guard !ciStatus.status.isDeploying else { return }

        ciStatus.status = .loading

        do {
            let hasUnpushed = try await gitService.hasCommitsToPush()
            let hasUncommitted = try await gitService.hasUncommittedChanges()

            ciStatus.hasUnpushedCommits = hasUnpushed
            ciStatus.hasUncommittedChanges = hasUncommitted
            ciStatus.currentBranch = config.branch

            if let latestRun = try await ghCLIService.getLatestWorkflowRun(branch: config.branch) {
                // Check if the latest run is in progress - if so, monitor it
                if !latestRun.isCompleted {
                    ciStatus.status = .deploying(runId: latestRun.id)
                    // Start monitoring in background
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
    public func pushAndDeploy() async throws {
        ciStatus.runDetail = nil

        // Check if we have commits to push
        let hasCommitsToPush = try await gitService.hasCommitsToPush()

        var runIdToWatch: String?

        if hasCommitsToPush {
            // Get the current latest run ID before pushing
            let beforeRunId = try await ghCLIService.getLatestWorkflowRun(branch: config.branch)?.id

            ciStatus.status = .deploying(runId: "pending")

            try await gitService.push()

            // Poll for a new run to appear
            runIdToWatch = try await waitForNewRun(
                branch: config.branch,
                afterRunId: beforeRunId
            )
        } else {
            // No commits to push - trigger workflow manually
            ciStatus.status = .deploying(runId: "pending")

            try await ghCLIService.triggerWorkflow(workflow: "Dev Deploy", branch: config.branch)

            // Wait for the triggered run to appear
            let beforeRunId = try await ghCLIService.getLatestWorkflowRun(branch: config.branch)?.id
            try await Task.sleep(for: .seconds(2))
            runIdToWatch = try await waitForNewRun(
                branch: config.branch,
                afterRunId: beforeRunId
            )
        }

        guard let runId = runIdToWatch else {
            throw DeployError.deploymentFailed(reason: "Could not find new workflow run")
        }

        ciStatus.status = .deploying(runId: runId)

        // Monitor the workflow until completion
        await monitorWorkflowRun(runId: runId)
    }

    /// Open workflow logs in browser
    public func viewWorkflowLogs(runId: String) async throws {
        let url = "https://github.com/\(config.repository)/actions/runs/\(runId)"

        let cliService = CLIService.shared
        let result = try await cliService.execute(
            command: "open",
            arguments: [url],
            printCommand: false
        )

        guard result.isSuccess else {
            throw DeployError.commandFailed(
                command: "open \(url)",
                exitCode: result.exitCode,
                stderr: result.stderr
            )
        }
    }

    // MARK: - CLI Operations (for CLI commands without UI state)
    // These methods are nonisolated because they don't touch ciStatus state

    /// Get the latest workflow run ID (or nil if none exist)
    nonisolated public func getLatestRunId(branch: String) async throws -> Int? {
        guard let run = try await ghCLIService.getLatestWorkflowRun(branch: branch) else {
            return nil
        }
        return Int(run.id)
    }

    /// Wait for a NEW workflow run to appear (newer than afterRunId) and complete
    nonisolated public func waitForNewWorkflowCompletion(
        branch: String,
        afterRunId: Int?,
        timeoutMinutes: Int = 10
    ) async throws {
        print("\n⏳ Waiting for new GitHub Actions workflow to start...")

        let maxAttempts = timeoutMinutes * 6 // Check every 10 seconds
        let pollInterval: UInt64 = 10_000_000_000 // 10 seconds in nanoseconds

        var attempts = 0
        var trackedRunId: Int?

        // Wait for a new run to appear
        while attempts < maxAttempts {
            let runs = try await ghCLIService.listWorkflowRuns(branch: branch, limit: 1)

            guard let latestRun = runs.first else {
                print("  No workflow runs found yet, waiting...")
                try await Task.sleep(nanoseconds: pollInterval)
                attempts += 1
                continue
            }

            guard let id = Int(latestRun.id) else {
                throw CLIServiceError.invalidOutput(reason: "Could not parse workflow run ID")
            }

            // Check if this is a new run (greater ID = newer)
            if let afterId = afterRunId, id <= afterId {
                print("  Waiting for new workflow (current: \(id), waiting for: >\(afterId))...")
                try await Task.sleep(nanoseconds: pollInterval)
                attempts += 1
                continue
            }

            // We found the new run!
            if trackedRunId == nil {
                trackedRunId = id
                print("  Found new workflow run \(id)")
            }

            print("  Workflow run \(id): status=\(latestRun.status), conclusion=\(latestRun.conclusion ?? "none")")

            // Check if completed
            if latestRun.isCompleted {
                if latestRun.wasSuccessful {
                    print("\n✅ Workflow completed successfully")
                    return
                } else {
                    throw DeployError.deploymentFailed(reason: "Workflow failed with conclusion: \(latestRun.conclusion ?? "unknown")")
                }
            }

            attempts += 1
            try await Task.sleep(nanoseconds: pollInterval)
        }

        throw CLIServiceError.timeout(command: "GitHub Actions workflow", duration: Double(timeoutMinutes * 60))
    }

    /// Get the latest workflow run status
    nonisolated public func getLatestRunStatus(branch: String) async throws -> (status: String, conclusion: String?) {
        guard let run = try await ghCLIService.getLatestWorkflowRun(branch: branch) else {
            throw CLIServiceError.invalidOutput(reason: "No workflow runs found")
        }
        return (run.status, run.conclusion)
    }

    /// View workflow logs (prints to console)
    nonisolated public func viewLogs(runId: String) async throws {
        let logs = try await ghCLIService.viewWorkflowRun(runId: runId, showLog: true)
        print(logs)
    }

    /// Trigger a workflow manually and wait for it to complete
    nonisolated public func triggerWorkflowAndWait(
        workflowName: String,
        branch: String,
        timeoutMinutes: Int = 10
    ) async throws {
        print("\n🔄 Triggering GitHub Actions workflow '\(workflowName)' on branch '\(branch)'...")

        // Get the current latest run ID before triggering
        let beforeRunId = try await getLatestRunId(branch: branch)

        // Trigger the workflow
        try await ghCLIService.triggerWorkflow(workflow: workflowName, branch: branch)

        print("✅ Workflow triggered successfully")

        // Wait for the NEW workflow to appear and complete
        try await waitForNewWorkflowCompletion(
            branch: branch,
            afterRunId: beforeRunId,
            timeoutMinutes: timeoutMinutes
        )
    }

    // MARK: - Private Helpers

    /// Monitor a workflow run until completion, updating the UI with progress
    private func monitorWorkflowRun(runId: String) async {
        let pollInterval: Duration = .seconds(3)
        let maxPollTime: Duration = .seconds(15 * 60)
        let startTime = ContinuousClock.now

        while true {
            // Check timeout
            if ContinuousClock.now - startTime > maxPollTime {
                ciStatus.status = .failed(runId: runId, reason: "Timeout waiting for workflow")
                return
            }

            do {
                let detail = try await ghCLIService.getRunDetail(runId: runId)
                ciStatus.runDetail = detail

                if detail.isCompleted {
                    if detail.isSuccess {
                        ciStatus.status = .success(runId: runId)
                    } else {
                        let reason = detail.conclusion ?? "unknown"
                        ciStatus.status = .failed(runId: runId, reason: reason)
                    }
                    // Clear detail after completion
                    ciStatus.runDetail = nil
                    return
                }

                try await Task.sleep(for: pollInterval)
            } catch {
                // If we fail to get details, wait and retry
                try? await Task.sleep(for: pollInterval)
            }
        }
    }

    private func waitForNewRun(
        branch: String,
        afterRunId: String?,
        maxAttempts: Int = 30
    ) async throws -> String? {
        for attempt in 0..<maxAttempts {
            if let run = try await ghCLIService.getLatestWorkflowRun(branch: branch) {
                if let afterId = afterRunId {
                    // Compare numerically if possible
                    if let newIdInt = Int(run.id), let afterIdInt = Int(afterId), newIdInt > afterIdInt {
                        return run.id
                    }
                } else {
                    // No previous run, so any run is new
                    return run.id
                }
            }

            if attempt < maxAttempts - 1 {
                try await Task.sleep(for: .seconds(2))
            }
        }

        return nil
    }

    private func parseGitHubDate(_ dateString: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: dateString) {
            return date
        }
        // Try without fractional seconds
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: dateString)
    }
}
