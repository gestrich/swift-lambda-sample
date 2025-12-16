import Foundation
import sdk_cli
import sdk_github

/// Workflow for updating Lambda code via GitHub Actions.
/// Orchestrates git operations and workflow monitoring, returning progress via stream.
public struct UpdateLambdaWorkflow: Sendable {
    private let gitClient: GitClient
    private let githubClient: GitHubActionsClient

    public init(
        gitClient: GitClient,
        githubClient: GitHubActionsClient
    ) {
        self.gitClient = gitClient
        self.githubClient = githubClient
    }

    /// Creates a workflow by loading GitHub configuration from disk.
    /// - Parameters:
    ///   - projectRoot: Root directory of the project
    ///   - cliClient: CLI client for executing commands
    /// - Throws: `DeployError.configurationMissing` if GitHub config file doesn't exist
    public static func create(
        projectRoot: String,
        cliClient: CLIClient
    ) throws -> UpdateLambdaWorkflow {
        guard let githubConfig = GitHubConfiguration.loadConfig() else {
            throw DeployError.configurationMissing(
                file: GitHubConfiguration.configPath,
                hint: "Create with: {\"repository\": \"owner/repo\", \"branch\": \"dev\"}"
            )
        }

        let gitClient = GitClient(repoPath: projectRoot, cliClient: cliClient)
        let githubClient = GitHubActionsClient(
            repoPath: projectRoot,
            config: githubConfig.toSDKConfiguration(),
            cliClient: cliClient
        )

        return UpdateLambdaWorkflow(
            gitClient: gitClient,
            githubClient: githubClient
        )
    }

    /// Progress updates from the update lambda workflow.
    public struct Progress: Sendable {
        public let step: Step
        public let detail: Detail?

        public enum Step: Sendable, Equatable {
            case checkingGitStatus
            case pushing
            case triggeringWorkflow
            case waitingForWorkflow
            case complete
        }

        public enum Detail: Sendable {
            case gitStatus(hasCommitsToPush: Bool)
            case workflowProgress(WorkflowProgress)
            case skippedPush
        }

        public init(step: Step, detail: Detail? = nil) {
            self.step = step
            self.detail = detail
        }
    }

    /// Options for the update lambda workflow.
    public struct Options: Sendable {
        public let skipPush: Bool
        public let workflowName: String
        public let timeoutMinutes: Int

        public init(
            skipPush: Bool = false,
            workflowName: String = "Dev Deploy",
            timeoutMinutes: Int = 10
        ) {
            self.skipPush = skipPush
            self.workflowName = workflowName
            self.timeoutMinutes = timeoutMinutes
        }
    }

    /// Run the update lambda workflow.
    public func run(options: Options = Options()) -> AsyncThrowingStream<Progress, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    try await runWorkflow(options: options, continuation: continuation)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func runWorkflow(
        options: Options,
        continuation: AsyncThrowingStream<Progress, Error>.Continuation
    ) async throws {
        if options.skipPush {
            continuation.yield(Progress(step: .checkingGitStatus, detail: .skippedPush))
            continuation.yield(Progress(step: .triggeringWorkflow))

            try await githubClient.triggerWorkflowAndWait(
                workflowName: options.workflowName,
                timeoutMinutes: options.timeoutMinutes
            )

            continuation.yield(Progress(step: .complete))
            continuation.finish()
            return
        }

        continuation.yield(Progress(step: .checkingGitStatus))
        let hasCommitsToPush = try await gitClient.hasCommitsToPush()
        continuation.yield(Progress(step: .checkingGitStatus, detail: .gitStatus(hasCommitsToPush: hasCommitsToPush)))

        if hasCommitsToPush {
            let beforeRunId = try await githubClient.getLatestRunId()

            continuation.yield(Progress(step: .pushing))
            try await gitClient.push()

            continuation.yield(Progress(step: .waitingForWorkflow))
            try await githubClient.waitForNewWorkflowCompletion(
                afterRunId: beforeRunId,
                timeoutMinutes: options.timeoutMinutes
            )
        } else {
            continuation.yield(Progress(step: .triggeringWorkflow))
            try await githubClient.triggerWorkflowAndWait(
                workflowName: options.workflowName,
                timeoutMinutes: options.timeoutMinutes
            )
        }

        continuation.yield(Progress(step: .complete))
        continuation.finish()
    }
}
