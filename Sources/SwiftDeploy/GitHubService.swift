import Foundation

/// Service for GitHub Actions operations
public actor GitHubService {
    private let cliService: CLIService
    private let owner: String
    private let repo: String

    public init(owner: String, repo: String) {
        self.cliService = CLIService.shared
        self.owner = owner
        self.repo = repo
    }

    /// Wait for the latest workflow run to complete
    public func waitForWorkflowCompletion(
        branch: String,
        timeoutMinutes: Int = 10
    ) async throws {
        print("\n⏳ Waiting for GitHub Actions workflow to complete...")

        let maxAttempts = timeoutMinutes * 6 // Check every 10 seconds
        let pollInterval: UInt64 = 10_000_000_000 // 10 seconds in nanoseconds

        var attempts = 0
        var runId: String?

        // First, find the latest run
        while attempts < maxAttempts {
            let listResult = try await cliService.execute(
                command: "gh",
                arguments: [
                    "run", "list",
                    "--repo", "\(owner)/\(repo)",
                    "--branch", branch,
                    "--limit", "1",
                    "--json", "databaseId,status,conclusion"
                ],
                printCommand: false
            )

            guard listResult.isSuccess else {
                throw CLIError.executionFailed(
                    command: "gh run list",
                    exitCode: listResult.exitCode,
                    stderr: listResult.stderr
                )
            }

            guard let data = listResult.stdout.data(using: .utf8),
                  let runs = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                  let latestRun = runs.first else {
                print("  No workflow runs found yet, waiting...")
                try await Task.sleep(nanoseconds: pollInterval)
                attempts += 1
                continue
            }

            guard let id = latestRun["databaseId"] as? Int else {
                throw CLIError.invalidOutput(reason: "Could not parse workflow run ID")
            }

            runId = String(id)

            let status = latestRun["status"] as? String ?? "unknown"
            let conclusion = latestRun["conclusion"] as? String

            print("  Workflow run \(id): status=\(status), conclusion=\(conclusion ?? "none")")

            // Check if completed
            if status == "completed" {
                if conclusion == "success" {
                    print("\n✅ Workflow completed successfully")
                    return
                } else {
                    throw CLIError.deploymentFailed(reason: "Workflow failed with conclusion: \(conclusion ?? "unknown")")
                }
            }

            attempts += 1
            try await Task.sleep(nanoseconds: pollInterval)
        }

        throw CLIError.timeout(command: "GitHub Actions workflow", duration: Double(timeoutMinutes * 60))
    }

    /// Get the latest workflow run status
    public func getLatestRunStatus(branch: String) async throws -> (status: String, conclusion: String?) {
        let result = try await cliService.execute(
            command: "gh",
            arguments: [
                "run", "list",
                "--repo", "\(owner)/\(repo)",
                "--branch", branch,
                "--limit", "1",
                "--json", "status,conclusion"
            ],
            printCommand: false
        )

        guard result.isSuccess else {
            throw CLIError.executionFailed(
                command: "gh run list",
                exitCode: result.exitCode,
                stderr: result.stderr
            )
        }

        guard let data = result.stdout.data(using: .utf8),
              let runs = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let latestRun = runs.first else {
            throw CLIError.invalidOutput(reason: "No workflow runs found")
        }

        let status = latestRun["status"] as? String ?? "unknown"
        let conclusion = latestRun["conclusion"] as? String

        return (status, conclusion)
    }

    /// View workflow logs
    public func viewLogs(runId: String) async throws {
        let result = try await cliService.execute(
            command: "gh",
            arguments: [
                "run", "view",
                runId,
                "--repo", "\(owner)/\(repo)",
                "--log"
            ]
        )

        guard result.isSuccess else {
            throw CLIError.executionFailed(
                command: "gh run view",
                exitCode: result.exitCode,
                stderr: result.stderr
            )
        }

        print(result.stdout)
    }
}
