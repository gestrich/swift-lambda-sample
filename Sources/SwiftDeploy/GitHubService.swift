import Foundation

/// Service for GitHub Actions operations
public actor GitHubService {
    private let ghService: GitHubCLIService

    public init(owner: String, repo: String) {
        self.ghService = GitHubCLIService(repository: "\(owner)/\(repo)")
    }

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
                throw CLIError.invalidOutput(reason: "Could not parse workflow run ID")
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
                    throw CLIError.deploymentFailed(reason: "Workflow failed with conclusion: \(latestRun.conclusion ?? "unknown")")
                }
            }

            attempts += 1
            try await Task.sleep(nanoseconds: pollInterval)
        }

        throw CLIError.timeout(command: "GitHub Actions workflow", duration: Double(timeoutMinutes * 60))
    }

    /// Get the latest workflow run status
    public func getLatestRunStatus(branch: String) async throws -> (status: String, conclusion: String?) {
        guard let run = try await ghService.getLatestWorkflowRun(branch: branch) else {
            throw CLIError.invalidOutput(reason: "No workflow runs found")
        }

        return (run.status, run.conclusion)
    }

    /// View workflow logs
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
}
