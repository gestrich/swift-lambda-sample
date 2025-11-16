import Foundation

/// Service for interacting with GitHub CLI (gh)
public actor GitHubCLIService {
    private let cliService: CLIService
    private let repository: String

    public init(repository: String = "gestrich/swift-lambda-sample") {
        self.cliService = CLIService.shared
        self.repository = repository
    }

    // MARK: - Workflow Operations

    public struct WorkflowRun: Sendable {
        public let id: String
        public let status: String
        public let conclusion: String?
        public let createdAt: String
        public let headBranch: String
        public let event: String
        public let displayTitle: String

        public var isCompleted: Bool {
            status == "completed"
        }

        public var wasSuccessful: Bool {
            conclusion == "success"
        }
    }

    /// List workflow runs
    public func listWorkflowRuns(
        branch: String? = nil,
        limit: Int = 5,
        workflow: String? = nil
    ) async throws -> [WorkflowRun] {
        var arguments = [
            "run", "list",
            "--repo", repository,
            "--limit", String(limit),
            "--json", "databaseId,status,conclusion,createdAt,headBranch,event,displayTitle"
        ]

        if let branch = branch {
            arguments.append(contentsOf: ["--branch", branch])
        }

        if let workflow = workflow {
            arguments.append(contentsOf: ["--workflow", workflow])
        }

        let result = try await cliService.execute(
            command: "gh",
            arguments: arguments,
            printCommand: false
        )

        guard result.isSuccess else {
            throw CLIError.commandFailed(
                command: "gh run list",
                exitCode: result.exitCode,
                stderr: result.stderr
            )
        }

        guard let data = result.stdout.data(using: .utf8),
              let runs = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw CLIError.invalidOutput(reason: "Failed to parse workflow runs")
        }

        return runs.compactMap { run in
            guard let id = run["databaseId"] as? Int,
                  let status = run["status"] as? String,
                  let createdAt = run["createdAt"] as? String,
                  let headBranch = run["headBranch"] as? String,
                  let event = run["event"] as? String,
                  let displayTitle = run["displayTitle"] as? String else {
                return nil
            }

            return WorkflowRun(
                id: String(id),
                status: status,
                conclusion: run["conclusion"] as? String,
                createdAt: createdAt,
                headBranch: headBranch,
                event: event,
                displayTitle: displayTitle
            )
        }
    }

    /// Get the latest workflow run
    public func getLatestWorkflowRun(branch: String? = nil) async throws -> WorkflowRun? {
        let runs = try await listWorkflowRuns(branch: branch, limit: 1)
        return runs.first
    }

    /// Watch a workflow run (polls until completion)
    public func watchWorkflowRun(runId: String? = nil) async throws {
        var arguments = [
            "run", "watch",
            "--repo", repository
        ]

        if let runId = runId {
            arguments.append(runId)
        }

        let result = try await cliService.execute(
            command: "gh",
            arguments: arguments
        )

        guard result.isSuccess else {
            throw CLIError.commandFailed(
                command: "gh run watch",
                exitCode: result.exitCode,
                stderr: result.stderr
            )
        }
    }

    /// View workflow run details
    public func viewWorkflowRun(runId: String, showLog: Bool = false) async throws -> String {
        var arguments = [
            "run", "view",
            runId,
            "--repo", repository
        ]

        if showLog {
            arguments.append("--log")
        }

        let result = try await cliService.execute(
            command: "gh",
            arguments: arguments,
            printCommand: false
        )

        guard result.isSuccess else {
            throw CLIError.commandFailed(
                command: "gh run view",
                exitCode: result.exitCode,
                stderr: result.stderr
            )
        }

        return result.stdout
    }

    /// Trigger a workflow manually
    public func triggerWorkflow(
        workflow: String,
        branch: String = "dev"
    ) async throws {
        let result = try await cliService.execute(
            command: "gh",
            arguments: [
                "workflow", "run",
                workflow,
                "--repo", repository,
                "--ref", branch
            ]
        )

        guard result.isSuccess else {
            throw CLIError.commandFailed(
                command: "gh workflow run",
                exitCode: result.exitCode,
                stderr: result.stderr
            )
        }
    }

    // MARK: - Pull Request Operations

    /// Create a pull request
    public func createPullRequest(
        title: String,
        body: String,
        base: String = "main",
        head: String? = nil
    ) async throws -> String {
        var arguments = [
            "pr", "create",
            "--repo", repository,
            "--title", title,
            "--body", body,
            "--base", base
        ]

        if let head = head {
            arguments.append(contentsOf: ["--head", head])
        }

        let result = try await cliService.execute(
            command: "gh",
            arguments: arguments
        )

        guard result.isSuccess else {
            throw CLIError.commandFailed(
                command: "gh pr create",
                exitCode: result.exitCode,
                stderr: result.stderr
            )
        }

        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// List pull requests
    public func listPullRequests(state: String = "open") async throws -> [[String: Any]] {
        let result = try await cliService.execute(
            command: "gh",
            arguments: [
                "pr", "list",
                "--repo", repository,
                "--state", state,
                "--json", "number,title,state,headRefName,createdAt",
                "--limit", "10"
            ],
            printCommand: false
        )

        guard result.isSuccess else {
            throw CLIError.commandFailed(
                command: "gh pr list",
                exitCode: result.exitCode,
                stderr: result.stderr
            )
        }

        guard let data = result.stdout.data(using: .utf8),
              let prs = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw CLIError.invalidOutput(reason: "Failed to parse pull requests")
        }

        return prs
    }

    // MARK: - Issue Operations

    /// Create an issue
    public func createIssue(title: String, body: String) async throws -> String {
        let result = try await cliService.execute(
            command: "gh",
            arguments: [
                "issue", "create",
                "--repo", repository,
                "--title", title,
                "--body", body
            ]
        )

        guard result.isSuccess else {
            throw CLIError.commandFailed(
                command: "gh issue create",
                exitCode: result.exitCode,
                stderr: result.stderr
            )
        }

        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Helper Methods

    /// Check if gh CLI is installed and authenticated
    public func checkAuthentication() async throws -> Bool {
        let result = try await cliService.execute(
            command: "gh",
            arguments: ["auth", "status"],
            printCommand: false
        )

        return result.isSuccess
    }
}
