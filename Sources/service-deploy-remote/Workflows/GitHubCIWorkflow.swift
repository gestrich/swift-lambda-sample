import Foundation
import sdk_github
import sdk_cli
import service_deploy_core

/// Workflow for GitHub CI operations.
/// Orchestrates git operations and GitHub Actions, yielding state updates via stream.
public struct GitHubCIWorkflow: Sendable {
    private let ghClient: GitHubCLIClient
    private let gitClient: GitClient
    private let repository: String
    private let branch: String
    private let workflowName: String?

    public init(
        ghClient: GitHubCLIClient,
        gitClient: GitClient,
        repository: String,
        branch: String,
        workflowName: String?
    ) {
        self.ghClient = ghClient
        self.gitClient = gitClient
        self.repository = repository
        self.branch = branch
        self.workflowName = workflowName
    }

    /// Creates a workflow from configuration file.
    public static func create(
        projectRoot: String,
        cliClient: CLIClient
    ) throws -> GitHubCIWorkflow {
        guard let config = GitHubConfiguration.loadConfig() else {
            throw DeployError.configurationMissing(
                file: GitHubConfiguration.configPath,
                hint: "Create with: {\"repository\": \"owner/repo\", \"branch\": \"dev\"}"
            )
        }

        let ghClient = GitHubCLIClient(repository: config.repository, cliClient: cliClient)
        let gitClient = GitClient(repoPath: projectRoot, cliClient: cliClient)

        return GitHubCIWorkflow(
            ghClient: ghClient,
            gitClient: gitClient,
            repository: config.repository,
            branch: config.branch,
            workflowName: config.workflowName
        )
    }

    // MARK: - Queries (one-shot)

    /// Get current git and GitHub status.
    /// Returns a StatusSnapshot for refresh operations.
    public func getStatus() async throws -> StatusSnapshot {
        let gitStatus = GitStatus(
            hasUnpushedCommits: try await gitClient.hasCommitsToPush(),
            hasUncommittedChanges: try await gitClient.hasUncommittedChanges(),
            currentBranch: try await gitClient.getCurrentBranch()
        )

        let latestRun = try await ghClient.getLatestWorkflowRun(branch: branch, workflow: workflowName)
        let runInfo = latestRun.map { WorkflowRunInfo(from: $0) }

        return StatusSnapshot(
            gitStatus: gitStatus,
            latestRun: runInfo
        )
    }

    // MARK: - Operations (streaming)

    /// Push commits and deploy via GitHub Actions.
    /// Returns stream of state updates until workflow completes.
    public func pushAndDeploy(
        timeoutMinutes: Int
    ) -> AsyncThrowingStream<State, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await runPushAndDeploy(
                        timeoutMinutes: timeoutMinutes,
                        continuation: continuation
                    )
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    /// Monitor an existing workflow run.
    public func monitorRun(
        runId: String,
        timeoutMinutes: Int
    ) -> AsyncThrowingStream<State, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await runMonitor(
                        runId: runId,
                        timeoutMinutes: timeoutMinutes,
                        continuation: continuation
                    )
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    // MARK: - Private Implementation

    private func runPushAndDeploy(
        timeoutMinutes: Int,
        continuation: AsyncThrowingStream<State, Error>.Continuation
    ) async throws {
        let startTime = Date()

        continuation.yield(.deploying(DeployProgress(step: .checkingGitStatus, startTime: startTime)))
        let gitStatus = GitStatus(
            hasUnpushedCommits: try await gitClient.hasCommitsToPush(),
            hasUncommittedChanges: try await gitClient.hasUncommittedChanges(),
            currentBranch: try await gitClient.getCurrentBranch()
        )

        if gitStatus.hasUnpushedCommits {
            let beforeRunId = try await ghClient.getLatestWorkflowRun(branch: branch, workflow: workflowName)?.id

            continuation.yield(.deploying(DeployProgress(step: .pushing, startTime: startTime)))
            try await gitClient.push()

            continuation.yield(.deploying(DeployProgress(step: .waitingForWorkflow, startTime: startTime)))
            let runId = try await waitForNewRun(afterRunId: beforeRunId, timeout: .seconds(60))

            try await monitorUntilComplete(
                runId: runId,
                timeoutMinutes: timeoutMinutes,
                gitStatus: gitStatus,
                continuation: continuation,
                startTime: startTime
            )
        } else {
            let workflowToTrigger = workflowName ?? "Dev Deploy"
            let beforeRunId = try await ghClient.getLatestWorkflowRun(branch: branch, workflow: workflowName)?.id

            continuation.yield(.deploying(DeployProgress(step: .triggering(workflow: workflowToTrigger), startTime: startTime)))
            try await ghClient.triggerWorkflow(workflow: workflowToTrigger, branch: branch)

            try await Task.sleep(for: .seconds(2))

            continuation.yield(.deploying(DeployProgress(step: .waitingForWorkflow, startTime: startTime)))
            let runId = try await waitForNewRun(afterRunId: beforeRunId, timeout: .seconds(60))

            try await monitorUntilComplete(
                runId: runId,
                timeoutMinutes: timeoutMinutes,
                gitStatus: gitStatus,
                continuation: continuation,
                startTime: startTime
            )
        }
    }

    private func runMonitor(
        runId: String,
        timeoutMinutes: Int,
        continuation: AsyncThrowingStream<State, Error>.Continuation
    ) async throws {
        let startTime = Date()

        let gitStatus = GitStatus(
            hasUnpushedCommits: try await gitClient.hasCommitsToPush(),
            hasUncommittedChanges: try await gitClient.hasUncommittedChanges(),
            currentBranch: try await gitClient.getCurrentBranch()
        )

        try await monitorUntilComplete(
            runId: runId,
            timeoutMinutes: timeoutMinutes,
            gitStatus: gitStatus,
            continuation: continuation,
            startTime: startTime
        )
    }

    private func monitorUntilComplete(
        runId: String,
        timeoutMinutes: Int,
        gitStatus: GitStatus,
        continuation: AsyncThrowingStream<State, Error>.Continuation,
        startTime: Date
    ) async throws {
        let pollInterval: Duration = .seconds(3)
        let timeout: Duration = .seconds(timeoutMinutes * 60)
        let startClock = ContinuousClock.now

        while !Task.isCancelled {
            if ContinuousClock.now - startClock > timeout {
                throw GitHubCIWorkflowError.timeout(operation: "workflow monitoring", duration: timeout)
            }

            let detail = try await ghClient.getRunDetail(runId: runId)

            if detail.isCompleted {
                if detail.isSuccess {
                    continuation.yield(.completed(.success(runId: runId, gitStatus: gitStatus)))
                } else {
                    continuation.yield(.completed(.failed(
                        runId: runId,
                        reason: detail.conclusion ?? "unknown",
                        gitStatus: gitStatus
                    )))
                }
                continuation.finish()
                return
            }

            continuation.yield(.deploying(DeployProgress(
                step: .monitoring(runId: runId),
                startTime: startTime,
                runDetail: detail
            )))

            try await Task.sleep(for: pollInterval)
        }

        continuation.finish()
    }

    private func waitForNewRun(afterRunId: String?, timeout: Duration) async throws -> String {
        let startClock = ContinuousClock.now
        let pollInterval: Duration = .seconds(2)

        while ContinuousClock.now - startClock < timeout {
            if let run = try await ghClient.getLatestWorkflowRun(branch: branch, workflow: workflowName) {
                if let afterId = afterRunId {
                    if let newIdInt = Int(run.id), let afterIdInt = Int(afterId), newIdInt > afterIdInt {
                        return run.id
                    }
                } else {
                    return run.id
                }
            }
            try await Task.sleep(for: pollInterval)
        }

        throw GitHubCIWorkflowError.timeout(operation: "waiting for new workflow run", duration: timeout)
    }
}

// MARK: - State Types

extension GitHubCIWorkflow {
    /// Lightweight snapshot for status refresh (not a completed operation).
    public struct StatusSnapshot: Sendable, Equatable {
        public let gitStatus: GitStatus
        public let latestRun: WorkflowRunInfo?

        public init(gitStatus: GitStatus, latestRun: WorkflowRunInfo?) {
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
    public struct Snapshot: Sendable, Equatable {
        public let status: Status
        public let gitStatus: GitStatus
        public let runDetail: GitHubRunDetail?

        public enum Status: Sendable, Equatable {
            case idle(lastRun: WorkflowRunInfo?)
            case success(runId: String)
            case failed(runId: String, reason: String)
        }

        public init(status: Status, gitStatus: GitStatus, runDetail: GitHubRunDetail?) {
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

        public static func success(runId: String, gitStatus: GitStatus) -> Snapshot {
            Snapshot(status: .success(runId: runId), gitStatus: gitStatus, runDetail: nil)
        }

        public static func failed(runId: String, reason: String, gitStatus: GitStatus) -> Snapshot {
            Snapshot(status: .failed(runId: runId, reason: reason), gitStatus: gitStatus, runDetail: nil)
        }

        public static func idle(lastRun: WorkflowRunInfo?, gitStatus: GitStatus) -> Snapshot {
            Snapshot(status: .idle(lastRun: lastRun), gitStatus: gitStatus, runDetail: nil)
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

        public static let empty = GitStatus(
            hasUnpushedCommits: false,
            hasUncommittedChanges: false,
            currentBranch: ""
        )
    }

    /// State yielded by a running workflow.
    public enum State: Sendable, Equatable {
        case deploying(DeployProgress)
        case completed(Snapshot)

        /// Start time from any in-progress state
        public var startTime: Date? {
            if case .deploying(let p) = self { return p.startTime }
            return nil
        }

        /// Final snapshot if completed
        public var completedSnapshot: Snapshot? {
            if case .completed(let snapshot) = self { return snapshot }
            return nil
        }
    }

    /// Progress during deployment operations
    public struct DeployProgress: Sendable, Equatable {
        public let step: Step
        public let startTime: Date
        public let runDetail: GitHubRunDetail?

        public init(step: Step, startTime: Date, runDetail: GitHubRunDetail? = nil) {
            self.step = step
            self.startTime = startTime
            self.runDetail = runDetail
        }
    }

    /// Steps in a deployment operation
    public enum Step: Sendable, Equatable {
        case checkingGitStatus
        case pushing
        case triggering(workflow: String)
        case waitingForWorkflow
        case monitoring(runId: String)
    }
}

// MARK: - Errors

public enum GitHubCIWorkflowError: Error, LocalizedError {
    case timeout(operation: String, duration: Duration)
    case workflowFailed(runId: String, conclusion: String)

    public var errorDescription: String? {
        switch self {
        case .timeout(let operation, let duration):
            return "Timeout during \(operation) after \(duration)"
        case .workflowFailed(let runId, let conclusion):
            return "Workflow \(runId) failed: \(conclusion)"
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
