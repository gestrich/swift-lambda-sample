import Foundation
import CLISDK
import d_sdk_github
import c_service_deploy_core
import c_service_deploy_remote

/// Workflow for updating Lambda code via GitHub Actions.
/// Orchestrates git operations and workflow monitoring, returning progress via stream.
public struct UpdateLambdaWorkflow: Sendable {
    private let gitClient: GitClient
    private let ghClient: GitHubCLIClient
    private let branch: String
    private let workflowName: String?

    public init(
        gitClient: GitClient,
        ghClient: GitHubCLIClient,
        branch: String,
        workflowName: String?
    ) {
        self.gitClient = gitClient
        self.ghClient = ghClient
        self.branch = branch
        self.workflowName = workflowName
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
        let ghClient = GitHubCLIClient(repository: githubConfig.repository, cliClient: cliClient)

        return UpdateLambdaWorkflow(
            gitClient: gitClient,
            ghClient: ghClient,
            branch: githubConfig.branch,
            workflowName: githubConfig.workflowName
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

            try await triggerAndWaitForCompletion(
                workflowName: options.workflowName,
                timeoutMinutes: options.timeoutMinutes,
                continuation: continuation,
                startTime: startTime
            )

            continuation.finish()
            return
        }

        continuation.yield(.updatingLambda(WorkflowState.UpdateLambdaProgress(
            step: .checkingGitStatus,
            startTime: startTime
        )))
        let hasCommitsToPush = try await gitClient.hasCommitsToPush()

        if hasCommitsToPush {
            let beforeRunId = try await ghClient.getLatestWorkflowRun(branch: branch, workflow: workflowName)?.id

            continuation.yield(.updatingLambda(WorkflowState.UpdateLambdaProgress(
                step: .pushing,
                startTime: startTime
            )))
            try await gitClient.push()

            continuation.yield(.updatingLambda(WorkflowState.UpdateLambdaProgress(
                step: .waitingForWorkflow,
                startTime: startTime
            )))

            let runId = try await waitForNewRun(afterRunId: beforeRunId, timeout: .seconds(60))
            try await monitorUntilComplete(
                runId: runId,
                timeoutMinutes: options.timeoutMinutes,
                continuation: continuation,
                startTime: startTime
            )
        } else {
            continuation.yield(.updatingLambda(WorkflowState.UpdateLambdaProgress(
                step: .triggeringWorkflow,
                startTime: startTime
            )))
            try await triggerAndWaitForCompletion(
                workflowName: options.workflowName,
                timeoutMinutes: options.timeoutMinutes,
                continuation: continuation,
                startTime: startTime
            )
        }

        continuation.finish()
    }

    // MARK: - Private Helpers

    private func triggerAndWaitForCompletion(
        workflowName: String,
        timeoutMinutes: Int,
        continuation: AsyncThrowingStream<WorkflowState, Error>.Continuation,
        startTime: Date
    ) async throws {
        let beforeRunId = try await ghClient.getLatestWorkflowRun(branch: branch, workflow: self.workflowName)?.id

        try await ghClient.triggerWorkflow(workflow: workflowName, branch: branch)

        try await Task.sleep(for: .seconds(2))

        continuation.yield(.updatingLambda(WorkflowState.UpdateLambdaProgress(
            step: .waitingForWorkflow,
            startTime: startTime
        )))

        let runId = try await waitForNewRun(afterRunId: beforeRunId, timeout: .seconds(60))
        try await monitorUntilComplete(
            runId: runId,
            timeoutMinutes: timeoutMinutes,
            continuation: continuation,
            startTime: startTime
        )
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

        throw UpdateLambdaWorkflowError.timeout(operation: "waiting for new workflow run", duration: timeout)
    }

    private func monitorUntilComplete(
        runId: String,
        timeoutMinutes: Int,
        continuation: AsyncThrowingStream<WorkflowState, Error>.Continuation,
        startTime: Date
    ) async throws {
        let pollInterval: Duration = .seconds(10)
        let timeout: Duration = .seconds(timeoutMinutes * 60)
        let startClock = ContinuousClock.now

        while !Task.isCancelled {
            if ContinuousClock.now - startClock > timeout {
                throw UpdateLambdaWorkflowError.timeout(operation: "workflow monitoring", duration: timeout)
            }

            let detail = try await ghClient.getRunDetail(runId: runId)

            if detail.isCompleted {
                if detail.isSuccess {
                    return
                } else {
                    throw UpdateLambdaWorkflowError.workflowFailed(
                        runId: runId,
                        conclusion: detail.conclusion ?? "unknown"
                    )
                }
            }

            continuation.yield(.updatingLambda(WorkflowState.UpdateLambdaProgress(
                step: .monitoringWorkflow(runId: runId),
                startTime: startTime,
                runDetail: detail
            )))

            try await Task.sleep(for: pollInterval)
        }
    }
}

// MARK: - Errors

public enum UpdateLambdaWorkflowError: Error, LocalizedError {
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
