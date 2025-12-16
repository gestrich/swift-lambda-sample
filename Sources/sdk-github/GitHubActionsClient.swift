import sdk_cli
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

/// Client for GitHub Actions operations
/// Provides high-level operations that return results without storing UI state
public actor GitHubActionsClient {
    private let ghCLIClient: GitHubCLIClient
    private let gitClient: GitClient
    private let cliClient: CLIClient
    private let config: GitHubActionsConfiguration

    // MARK: - State Management

    /// Current state of the GitHub Actions client
    private var currentState: State = .idle

    /// Continuations for state stream subscribers
    private var continuations: [UUID: AsyncStream<State>.Continuation] = [:]

    // MARK: - Init

    public init(repoPath: String, config: GitHubActionsConfiguration, cliClient: CLIClient) {
        self.config = config
        self.cliClient = cliClient
        self.ghCLIClient = GitHubCLIClient(repository: config.repository, cliClient: cliClient)
        self.gitClient = GitClient(repoPath: repoPath, cliClient: cliClient)
    }

    // MARK: - State Stream

    /// Subscribe to state changes
    /// Returns an AsyncStream that yields state updates
    public nonisolated func states() -> AsyncStream<State> {
        AsyncStream { continuation in
            let id = UUID()

            Task {
                await self.addContinuation(id: id, continuation: continuation)

                continuation.onTermination = { @Sendable _ in
                    Task { await self.removeContinuation(id: id) }
                }
            }
        }
    }

    /// Get the current state (for synchronous queries)
    public func getState() -> State {
        currentState
    }

    /// Add a continuation to track
    private func addContinuation(id: UUID, continuation: AsyncStream<State>.Continuation) {
        continuations[id] = continuation
        continuation.yield(currentState)
    }

    /// Remove a continuation when stream is cancelled
    private func removeContinuation(id: UUID) {
        continuations.removeValue(forKey: id)
    }

    /// Publish a state change to all subscribers
    private func publish(_ state: State) {
        currentState = state
        for continuation in continuations.values {
            continuation.yield(state)
        }
    }

    // MARK: - Configuration

    public nonisolated var repository: String {
        config.repository
    }

    public nonisolated var branch: String {
        config.branch
    }

    // MARK: - Git Status Queries

    /// Get current git status (uncommitted changes, unpushed commits, current branch)
    public func getGitStatus() async throws -> GitStatus {
        let hasUnpushed = try await gitClient.hasCommitsToPush()
        let hasUncommitted = try await gitClient.hasUncommittedChanges()
        let currentBranch = try await gitClient.getCurrentBranch()

        return GitStatus(
            hasUnpushedCommits: hasUnpushed,
            hasUncommittedChanges: hasUncommitted,
            currentBranch: currentBranch
        )
    }

    /// Get complete GitHub CI status snapshot (git status + latest workflow run)
    /// Returns ready-to-display data with all transformations applied
    public func getFullStatus() async throws -> GitHubCISnapshot {
        let gitStatus = try await getGitStatus()
        let latestRun = try await getLatestWorkflowRun()

        let runInfo = latestRun.map { run in
            WorkflowRunInfo(
                id: run.id,
                status: run.status,
                conclusion: run.conclusion,
                title: run.displayTitle,
                createdAt: Self.parseGitHubDate(run.createdAt)
            )
        }

        let inProgressId = latestRun?.isCompleted == false ? latestRun?.id : nil

        return GitHubCISnapshot(
            gitStatus: gitStatus,
            latestRun: runInfo,
            inProgressRunId: inProgressId
        )
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

    // MARK: - Workflow Run Queries

    /// Get the latest workflow run for the configured branch and workflow
    public func getLatestWorkflowRun() async throws -> GitHubWorkflowRun? {
        return try await ghCLIClient.getLatestWorkflowRun(branch: config.branch, workflow: config.workflowName)
    }

    /// Get the latest workflow run ID (or nil if none exist)
    public func getLatestRunId() async throws -> Int? {
        guard let run = try await ghCLIClient.getLatestWorkflowRun(branch: config.branch, workflow: config.workflowName) else {
            return nil
        }
        return Int(run.id)
    }

    /// Get detailed run information with jobs and steps
    public func getRunDetail(runId: String) async throws -> GitHubRunDetail {
        return try await ghCLIClient.getRunDetail(runId: runId)
    }

    /// Get the latest workflow run status
    public func getLatestRunStatus() async throws -> (status: String, conclusion: String?) {
        guard let run = try await ghCLIClient.getLatestWorkflowRun(branch: config.branch, workflow: config.workflowName) else {
            throw GitHubClientError.workflowRunNotFound
        }
        return (run.status, run.conclusion)
    }

    // MARK: - Workflow Operations

    /// Push commits and trigger a deployment workflow
    /// Returns the new workflow run ID
    public func pushAndTriggerWorkflow(output: CLIOutputStream? = nil) async throws -> String {
        let workflowName = config.workflowName ?? "push"
        publish(.triggering(workflow: workflowName))

        do {
            let hasCommitsToPush = try await gitClient.hasCommitsToPush()

            if hasCommitsToPush {
                let beforeRunId = try await ghCLIClient.getLatestWorkflowRun(branch: config.branch, workflow: config.workflowName)?.id
                try await gitClient.push(output: output)

                guard let newRunId = try await waitForNewRun(afterRunId: beforeRunId) else {
                    let error = GitHubClientError.timeout(operation: "Could not find new workflow run after push", duration: 60)
                    publish(.failed(error: error.localizedDescription))
                    throw error
                }
                publish(.completed(runId: newRunId))
                return newRunId
            } else {
                return try await triggerWorkflow(output: output)
            }
        } catch {
            if case .failed = currentState {
                // Already published failure
            } else {
                publish(.failed(error: error.localizedDescription))
            }
            throw error
        }
    }

    /// Trigger a workflow manually and return the run ID
    public func triggerWorkflow(output: CLIOutputStream? = nil) async throws -> String {
        let workflowToTrigger = config.workflowName ?? "Dev Deploy"
        publish(.triggering(workflow: workflowToTrigger))

        do {
            let beforeRunId = try await ghCLIClient.getLatestWorkflowRun(branch: config.branch, workflow: config.workflowName)?.id

            try await ghCLIClient.triggerWorkflow(workflow: workflowToTrigger, branch: config.branch, output: output)

            try await Task.sleep(for: .seconds(2))

            guard let newRunId = try await waitForNewRun(afterRunId: beforeRunId) else {
                let error = GitHubClientError.timeout(operation: "Could not find new workflow run after trigger", duration: 60)
                publish(.failed(error: error.localizedDescription))
                throw error
            }
            publish(.completed(runId: newRunId))
            return newRunId
        } catch {
            if case .failed = currentState {
                // Already published failure
            } else {
                publish(.failed(error: error.localizedDescription))
            }
            throw error
        }
    }

    /// Trigger a workflow and wait for completion
    public func triggerWorkflowAndWait(
        workflowName: String,
        timeoutMinutes: Int = 20
    ) async throws {
        publish(.triggering(workflow: workflowName))

        print("\n🔄 Triggering GitHub Actions workflow '\(workflowName)' on branch '\(config.branch)'...")

        do {
            let beforeRunId = try await getLatestRunId()

            try await ghCLIClient.triggerWorkflow(workflow: workflowName, branch: config.branch)

            print("✅ Workflow triggered successfully")

            try await waitForNewWorkflowCompletion(afterRunId: beforeRunId, timeoutMinutes: timeoutMinutes)
        } catch {
            if case .failed = currentState {
                // Already published failure
            } else {
                publish(.failed(error: error.localizedDescription))
            }
            throw error
        }
    }

    /// Wait for a NEW workflow run to appear (newer than afterRunId) and complete
    public func waitForNewWorkflowCompletion(
        afterRunId: Int?,
        timeoutMinutes: Int = 20
    ) async throws {
        print("\n⏳ Waiting for new GitHub Actions workflow to start...")

        let maxAttempts = timeoutMinutes * 6 // Check every 10 seconds
        let pollInterval: UInt64 = 10_000_000_000 // 10 seconds in nanoseconds
        let startTime = Date()

        var attempts = 0
        var trackedRunId: Int?

        while attempts < maxAttempts {
            let runs = try await ghCLIClient.listWorkflowRuns(branch: config.branch, limit: 1, workflow: config.workflowName)

            guard let latestRun = runs.first else {
                print("  No workflow runs found yet, waiting...")
                try await Task.sleep(nanoseconds: pollInterval)
                attempts += 1
                continue
            }

            guard let id = Int(latestRun.id) else {
                let error = GitHubClientError.invalidOutput(reason: "Could not parse workflow run ID")
                publish(.failed(error: error.localizedDescription))
                throw error
            }

            if let afterId = afterRunId, id <= afterId {
                print("  Waiting for new workflow (current: \(id), waiting for: >\(afterId))...")
                try await Task.sleep(nanoseconds: pollInterval)
                attempts += 1
                continue
            }

            if trackedRunId == nil {
                trackedRunId = id
                publish(.monitoring(runId: latestRun.id, startTime: startTime))
                print("  Found new workflow run \(id)")
            }

            print("  Workflow run \(id): status=\(latestRun.status), conclusion=\(latestRun.conclusion ?? "none")")

            if latestRun.isCompleted {
                if latestRun.wasSuccessful {
                    publish(.completed(runId: latestRun.id))
                    print("\n✅ Workflow completed successfully")
                    return
                } else {
                    let error = GitHubClientError.commandFailed(
                        command: "GitHub Actions workflow",
                        exitCode: 1,
                        output: "Workflow failed with conclusion: \(latestRun.conclusion ?? "unknown")"
                    )
                    publish(.failed(error: error.localizedDescription))
                    throw error
                }
            }

            attempts += 1
            try await Task.sleep(nanoseconds: pollInterval)
        }

        let error = GitHubClientError.timeout(operation: "GitHub Actions workflow", duration: Double(timeoutMinutes * 60))
        publish(.failed(error: error.localizedDescription))
        throw error
    }

    // MARK: - Monitoring

    /// Monitor a workflow run with progress updates
    /// Returns an AsyncStream that yields progress snapshots until completion
    public nonisolated func monitorWorkflowRun(runId: String) -> AsyncStream<WorkflowProgress> {
        AsyncStream { continuation in
            Task {
                let pollInterval: Duration = .seconds(3)
                let maxPollTime: Duration = .seconds(20 * 60)
                let startTime = ContinuousClock.now

                while !Task.isCancelled {
                    if ContinuousClock.now - startTime > maxPollTime {
                        continuation.yield(.failed(reason: "Timeout waiting for workflow"))
                        continuation.finish()
                        return
                    }

                    do {
                        let detail = try await self.ghCLIClient.getRunDetail(runId: runId)

                        if detail.isCompleted {
                            if detail.isSuccess {
                                continuation.yield(.success(runId: runId))
                            } else {
                                let reason = detail.conclusion ?? "unknown"
                                continuation.yield(.failed(reason: reason))
                            }
                            continuation.finish()
                            return
                        }

                        continuation.yield(.inProgress(detail: detail))

                        try await Task.sleep(for: pollInterval)
                    } catch {
                        try? await Task.sleep(for: pollInterval)
                    }
                }

                continuation.finish()
            }
        }
    }

    // MARK: - Browser/Logs

    /// Get the URL for viewing workflow logs
    public func getWorkflowLogsURL(runId: String) -> String {
        "https://github.com/\(config.repository)/actions/runs/\(runId)"
    }

    /// Open workflow logs in browser
    public func openWorkflowLogs(runId: String) async throws {
        let url = getWorkflowLogsURL(runId: runId)

        let result = try await cliClient.execute(
            command: "open",
            arguments: [url],
            printCommand: false
        )

        guard result.isSuccess else {
            throw GitHubClientError.commandFailed(
                command: "open \(url)",
                exitCode: result.exitCode,
                output: result.output
            )
        }
    }

    /// View workflow logs (prints to console)
    public func viewLogs(runId: String) async throws {
        let logs = try await ghCLIClient.viewWorkflowRun(runId: runId, showLog: true)
        print(logs)
    }

    // MARK: - Private Helpers

    private func waitForNewRun(
        afterRunId: String?,
        maxAttempts: Int = 30
    ) async throws -> String? {
        for attempt in 0..<maxAttempts {
            if let run = try await ghCLIClient.getLatestWorkflowRun(branch: config.branch, workflow: config.workflowName) {
                if let afterId = afterRunId {
                    if let newIdInt = Int(run.id), let afterIdInt = Int(afterId), newIdInt > afterIdInt {
                        return run.id
                    }
                } else {
                    return run.id
                }
            }

            if attempt < maxAttempts - 1 {
                try await Task.sleep(for: .seconds(2))
            }
        }

        return nil
    }
}

// MARK: - Types

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

/// Progress update from workflow monitoring
public enum WorkflowProgress: Sendable {
    case inProgress(detail: GitHubRunDetail)
    case success(runId: String)
    case failed(reason: String)
}

/// Complete snapshot of GitHub CI status (returned by getFullStatus)
public struct GitHubCISnapshot: Sendable, Equatable {
    public let gitStatus: GitStatus
    public let latestRun: WorkflowRunInfo?
    public let inProgressRunId: String?

    public init(gitStatus: GitStatus, latestRun: WorkflowRunInfo?, inProgressRunId: String?) {
        self.gitStatus = gitStatus
        self.latestRun = latestRun
        self.inProgressRunId = inProgressRunId
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

// MARK: - GitHubActionsClient State

extension GitHubActionsClient {
    /// State of the GitHub Actions client operations
    public enum State: Sendable, Equatable {
        /// No operation in progress
        case idle

        /// Triggering a workflow
        case triggering(workflow: String)

        /// Monitoring a workflow run
        case monitoring(runId: String, startTime: Date)

        /// Workflow completed successfully
        case completed(runId: String)

        /// Workflow or operation failed
        case failed(error: String)

        /// Whether an operation is currently in progress
        public var isBusy: Bool {
            switch self {
            case .idle, .completed, .failed:
                return false
            case .triggering, .monitoring:
                return true
            }
        }

        /// Whether a new workflow can be triggered
        public var canTrigger: Bool {
            switch self {
            case .idle, .completed, .failed:
                return true
            case .triggering, .monitoring:
                return false
            }
        }

        /// Human-readable description of the current state
        public var description: String {
            switch self {
            case .idle:
                return "Idle"
            case .triggering(let workflow):
                return "Triggering \(workflow)..."
            case .monitoring(let runId, let startTime):
                let elapsed = Int(Date().timeIntervalSince(startTime))
                return "Monitoring run \(runId) (\(elapsed)s)"
            case .completed(let runId):
                return "Completed (run \(runId))"
            case .failed(let error):
                return "Failed: \(error)"
            }
        }
    }
}
