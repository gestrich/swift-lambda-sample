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

    // Note: This workflow yields WorkflowState.updatingLambda for progress.
    // On completion, it finishes the stream without yielding .completed
    // since Lambda updates don't change infrastructure state.
    // The app layer restores the prior snapshot on stream completion.

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
    /// - Returns: AsyncThrowingStream that yields WorkflowState updates.
    ///   Note: This workflow finishes without yielding `.completed` since
    ///   Lambda updates don't change infrastructure state.
    public func run(options: Options = Options()) -> AsyncThrowingStream<WorkflowState, Error> {
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
        continuation: AsyncThrowingStream<WorkflowState, Error>.Continuation
    ) async throws {
        let startTime = Date()

        if options.skipPush {
            continuation.yield(.updatingLambda(WorkflowState.UpdateLambdaProgress(
                step: .checkingGitStatus,
                startTime: startTime
            )))
            continuation.yield(.updatingLambda(WorkflowState.UpdateLambdaProgress(
                step: .triggeringWorkflow,
                startTime: startTime
            )))

            try await githubClient.triggerWorkflowAndWait(
                workflowName: options.workflowName,
                timeoutMinutes: options.timeoutMinutes
            )

            // Stream finishes without .completed - Lambda updates don't change infrastructure
            continuation.finish()
            return
        }

        continuation.yield(.updatingLambda(WorkflowState.UpdateLambdaProgress(
            step: .checkingGitStatus,
            startTime: startTime
        )))
        let hasCommitsToPush = try await gitClient.hasCommitsToPush()

        if hasCommitsToPush {
            let beforeRunId = try await githubClient.getLatestRunId()

            continuation.yield(.updatingLambda(WorkflowState.UpdateLambdaProgress(
                step: .pushing,
                startTime: startTime
            )))
            try await gitClient.push()

            continuation.yield(.updatingLambda(WorkflowState.UpdateLambdaProgress(
                step: .waitingForWorkflow,
                startTime: startTime
            )))
            try await githubClient.waitForNewWorkflowCompletion(
                afterRunId: beforeRunId,
                timeoutMinutes: options.timeoutMinutes
            )
        } else {
            continuation.yield(.updatingLambda(WorkflowState.UpdateLambdaProgress(
                step: .triggeringWorkflow,
                startTime: startTime
            )))
            try await githubClient.triggerWorkflowAndWait(
                workflowName: options.workflowName,
                timeoutMinutes: options.timeoutMinutes
            )
        }

        // Stream finishes without .completed - Lambda updates don't change infrastructure
        continuation.finish()
    }
}
