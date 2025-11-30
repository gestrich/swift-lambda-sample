import CLIKit
import Foundation

/// Service for GitHub Actions operations with UI state management
public actor GitHubService {
    private let ghService: GitHubCLIService
    private let gitService: GitService
    private let repository: String

    /// Shared state for UI updates (MainActor isolated)
    public let ciState: GitHubCIState

    public init(repoPath: String, owner: String, repo: String) {
        self.repository = "\(owner)/\(repo)"
        self.ghService = GitHubCLIService(repository: repository)
        self.gitService = GitService(repoPath: repoPath)
        self.ciState = GitHubCIState()
    }

    // MARK: - UI State Operations

    /// Refresh GitHub CI status including git state and latest workflow run.
    /// If an in-progress run is detected, automatically starts monitoring it.
    public func refreshStatus() async {
        // Don't refresh if we're already deploying
        guard await !ciState.status.isDeploying else { return }

        await ciState.setLoading()

        do {
            let currentBranch = try await gitService.getCurrentBranch()
            let hasUnpushed = try await gitService.hasCommitsToPush()
            let hasUncommitted = try await gitService.hasUncommittedChanges()

            await ciState.updateGitStatus(
                hasUnpushedCommits: hasUnpushed,
                hasUncommittedChanges: hasUncommitted,
                branch: currentBranch
            )

            if let latestRun = try await ghService.getLatestWorkflowRun(branch: currentBranch) {
                // Check if the latest run is in progress - if so, monitor it
                if !latestRun.isCompleted {
                    await ciState.setDeploying(runId: latestRun.id)
                    // Start monitoring in background
                    Task {
                        await self.monitorWorkflowRun(runId: latestRun.id)
                    }
                } else {
                    let runInfo = GitHubCIState.WorkflowRunInfo(
                        id: latestRun.id,
                        status: latestRun.status,
                        conclusion: latestRun.conclusion,
                        title: latestRun.displayTitle,
                        createdAt: parseGitHubDate(latestRun.createdAt)
                    )
                    await ciState.setIdle(lastRun: runInfo)
                }
            } else {
                await ciState.setIdle(lastRun: nil)
            }
        } catch {
            print("Failed to refresh GitHub CI status: \(error)")
            await ciState.setIdle(lastRun: nil)
        }
    }

    /// Push commits and deploy via GitHub Actions with polling progress
    /// This method updates the ciState with structured job/step data
    public func pushAndDeploy() async throws {
        await ciState.clearRunDetail()

        let currentBranch = try await gitService.getCurrentBranch()

        // Check if we have commits to push
        let hasCommitsToPush = try await gitService.hasCommitsToPush()

        var runIdToWatch: String?

        if hasCommitsToPush {
            // Get the current latest run ID before pushing
            let beforeRunId = try await ghService.getLatestWorkflowRun(branch: currentBranch)?.id

            await ciState.setDeploying(runId: "pending")

            try await gitService.push()

            // Poll for a new run to appear
            runIdToWatch = try await waitForNewRun(
                branch: currentBranch,
                afterRunId: beforeRunId
            )
        } else {
            // No commits to push - trigger workflow manually
            await ciState.setDeploying(runId: "pending")

            try await ghService.triggerWorkflow(workflow: "Dev Deploy", branch: currentBranch)

            // Wait for the triggered run to appear
            let beforeRunId = try await ghService.getLatestWorkflowRun(branch: currentBranch)?.id
            try await Task.sleep(for: .seconds(2))
            runIdToWatch = try await waitForNewRun(
                branch: currentBranch,
                afterRunId: beforeRunId
            )
        }

        guard let runId = runIdToWatch else {
            throw DeployError.deploymentFailed(reason: "Could not find new workflow run")
        }

        await ciState.setDeploying(runId: runId)

        // Monitor the workflow until completion
        await monitorWorkflowRun(runId: runId)
    }

    /// Open workflow logs in browser
    public func viewWorkflowLogs(runId: String) async throws {
        let url = "https://github.com/\(repository)/actions/runs/\(runId)"

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

    // MARK: - Legacy Operations (for CLI commands)

    /// Get the latest workflow run ID (or nil if none exist)
    public func getLatestRunId(branch: String) async throws -> Int? {
        guard let run = try await ghService.getLatestWorkflowRun(branch: branch) else {
            return nil
        }
        return Int(run.id)
    }

    /// Wait for a NEW workflow run to appear (newer than afterRunId) and complete
    public func waitForNewWorkflowCompletion(
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
            let runs = try await ghService.listWorkflowRuns(branch: branch, limit: 1)

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
    public func getLatestRunStatus(branch: String) async throws -> (status: String, conclusion: String?) {
        guard let run = try await ghService.getLatestWorkflowRun(branch: branch) else {
            throw CLIServiceError.invalidOutput(reason: "No workflow runs found")
        }
        return (run.status, run.conclusion)
    }

    /// View workflow logs (prints to console)
    public func viewLogs(runId: String) async throws {
        let logs = try await ghService.viewWorkflowRun(runId: runId, showLog: true)
        print(logs)
    }

    /// Trigger a workflow manually and wait for it to complete
    public func triggerWorkflowAndWait(
        workflowName: String,
        branch: String,
        timeoutMinutes: Int = 10
    ) async throws {
        print("\n🔄 Triggering GitHub Actions workflow '\(workflowName)' on branch '\(branch)'...")

        // Get the current latest run ID before triggering
        let beforeRunId = try await getLatestRunId(branch: branch)

        // Trigger the workflow
        try await ghService.triggerWorkflow(workflow: workflowName, branch: branch)

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
                await ciState.setFailed(runId: runId, reason: "Timeout waiting for workflow")
                return
            }

            do {
                let detail = try await ghService.getRunDetail(runId: runId)
                await ciState.updateRunDetail(detail)

                if detail.isCompleted {
                    if detail.isSuccess {
                        await ciState.setSuccess(runId: runId)
                    } else {
                        let reason = detail.conclusion ?? "unknown"
                        await ciState.setFailed(runId: runId, reason: reason)
                    }
                    // Clear detail after completion
                    await ciState.clearRunDetail()
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
            if let run = try await ghService.getLatestWorkflowRun(branch: branch) {
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
