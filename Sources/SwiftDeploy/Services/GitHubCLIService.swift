import CLIKit
import Foundation

/// Service for interacting with GitHub CLI (gh)
public actor GitHubCLIService {
    private let cliService: CLIService
    private let repository: String

    public init(repository: String) {
        self.cliService = CLIService.shared
        self.repository = repository
    }

    // MARK: - Workflow Operations

    /// List workflow runs
    public func listWorkflowRuns(
        branch: String? = nil,
        limit: Int = 5,
        workflow: String? = nil
    ) async throws -> [GitHubWorkflowRun] {
        let command = Gh.Run.List(
            repo: repository,
            branch: branch,
            limit: String(limit),
            workflow: workflow,
            json: "databaseId,status,conclusion,createdAt,headBranch,event,displayTitle"
        )

        let result = try await cliService.executeForResult(command, printCommand: false)

        guard result.isSuccess else {
            throw DeployError.commandFailed(
                command: command.commandString,
                exitCode: result.exitCode,
                stderr: result.stderr
            )
        }

        let parser = GitHubWorkflowRunsParser()
        return try parser.parse(result.stdout)
    }

    /// Get the latest workflow run
    public func getLatestWorkflowRun(branch: String? = nil) async throws -> GitHubWorkflowRun? {
        let runs = try await listWorkflowRuns(branch: branch, limit: 1)
        return runs.first
    }

    /// Watch a workflow run (polls until completion)
    public func watchWorkflowRun(runId: String? = nil) async throws {
        let command = Gh.Run.Watch(runId: runId, repo: repository)

        let result = try await cliService.executeForResult(command)

        guard result.isSuccess else {
            throw DeployError.commandFailed(
                command: command.commandString,
                exitCode: result.exitCode,
                stderr: result.stderr
            )
        }
    }

    /// Watch a workflow run with streaming output
    /// Returns an AsyncStream that yields progress updates until the run completes
    public func watchWorkflowRunStreaming(runId: String? = nil) async -> AsyncStream<StreamOutput> {
        let command = Gh.Run.Watch(runId: runId, repo: repository)
        return await cliService.stream(command)
    }

    /// Get detailed run information with jobs and steps
    public func getRunDetail(runId: String) async throws -> GitHubRunDetail {
        let command = Gh.Run.View.withJobsAndSteps(runId: runId, repo: repository)

        return try await cliService.execute(
            command,
            parser: GitHubRunDetailParser(),
            workingDirectory: nil,
            printCommand: false
        )
    }

    /// View workflow run details
    public func viewWorkflowRun(runId: String, showLog: Bool = false) async throws -> String {
        let command = Gh.Run.View(runId: runId, repo: repository, log: showLog)

        let result = try await cliService.executeForResult(command, printCommand: false)

        guard result.isSuccess else {
            throw DeployError.commandFailed(
                command: command.commandString,
                exitCode: result.exitCode,
                stderr: result.stderr
            )
        }

        return result.stdout
    }

    /// Trigger a workflow manually
    public func triggerWorkflow(
        workflow: String,
        branch: String
    ) async throws {
        let command = Gh.Workflow.Run(workflow: workflow, repo: repository, ref: branch)

        let result = try await cliService.executeForResult(command)

        guard result.isSuccess else {
            throw DeployError.commandFailed(
                command: command.commandString,
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
        let command = Gh.Pr.Create(
            repo: repository,
            title: title,
            body: body,
            base: base,
            head: head
        )

        let result = try await cliService.executeForResult(command)

        guard result.isSuccess else {
            throw DeployError.commandFailed(
                command: command.commandString,
                exitCode: result.exitCode,
                stderr: result.stderr
            )
        }

        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// List pull requests
    public func listPullRequests(state: String = "open") async throws -> [GitHubPullRequest] {
        let command = Gh.Pr.List(
            repo: repository,
            state: state,
            json: "number,title,state,headRefName,createdAt",
            limit: "10"
        )

        let result = try await cliService.executeForResult(command, printCommand: false)

        guard result.isSuccess else {
            throw DeployError.commandFailed(
                command: command.commandString,
                exitCode: result.exitCode,
                stderr: result.stderr
            )
        }

        let parser = GitHubPullRequestsParser()
        return try parser.parse(result.stdout)
    }

    // MARK: - Issue Operations

    /// Create an issue
    public func createIssue(title: String, body: String) async throws -> String {
        let command = Gh.Issue.Create(repo: repository, title: title, body: body)

        let result = try await cliService.executeForResult(command)

        guard result.isSuccess else {
            throw DeployError.commandFailed(
                command: command.commandString,
                exitCode: result.exitCode,
                stderr: result.stderr
            )
        }

        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Helper Methods

    /// Check if gh CLI is installed and authenticated
    public func checkAuthentication() async throws -> Bool {
        let command = Gh.Auth.Status()
        let result = try await cliService.executeForResult(command, printCommand: false)
        return result.isSuccess
    }
}

// MARK: - Legacy Type Alias (for backwards compatibility)

/// Legacy type alias for backwards compatibility
/// Deprecated: Use GitHubWorkflowRun directly
public typealias WorkflowRun = GitHubWorkflowRun
