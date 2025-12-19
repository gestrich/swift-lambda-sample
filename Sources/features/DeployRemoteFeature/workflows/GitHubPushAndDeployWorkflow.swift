import Foundation
import GitHubSDK
import CLISDK
import DeployCoreService
import Uniflow

/// Workflow for pushing commits and deploying via GitHub Actions.
/// Orchestrates git push and GitHub Actions, yielding state updates via stream.
public struct GitHubPushAndDeployWorkflow: StreamingUseCase {
    public typealias State = GitHubCIState
    public typealias Result = State

    private let ghClient: GitHubCLIClient
    private let gitClient: GitClient
    private let branch: String
    private let workflowName: String?

    public init(
        ghClient: GitHubCLIClient,
        gitClient: GitClient,
        branch: String,
        workflowName: String?
    ) {
        self.ghClient = ghClient
        self.gitClient = gitClient
        self.branch = branch
        self.workflowName = workflowName
    }

    // MARK: - Options

    public struct Options: Sendable {
        public let timeoutMinutes: Int

        public init(timeoutMinutes: Int = 10) {
            self.timeoutMinutes = timeoutMinutes
        }
    }

    // MARK: - StreamingWorkflow Conformance

    public func stream(options: Options) -> AsyncThrowingStream<State, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await runPushAndDeploy(
                        timeoutMinutes: options.timeoutMinutes,
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

        continuation.yield(.deploying(GitHubCIDeployProgress(step: .checkingGitStatus, startTime: startTime)))
        let gitStatus = GitHubCIGitStatus(
            hasUnpushedCommits: try await gitClient.hasCommitsToPush(),
            hasUncommittedChanges: try await gitClient.hasUncommittedChanges(),
            currentBranch: try await gitClient.getCurrentBranch()
        )

        if gitStatus.hasUnpushedCommits {
            let beforeRunId = try await ghClient.getLatestWorkflowRun(branch: branch, workflow: workflowName)?.id

            continuation.yield(.deploying(GitHubCIDeployProgress(step: .pushing, startTime: startTime)))
            try await gitClient.push()

            continuation.yield(.deploying(GitHubCIDeployProgress(step: .waitingForWorkflow, startTime: startTime)))
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

            continuation.yield(.deploying(GitHubCIDeployProgress(step: .triggering(workflow: workflowToTrigger), startTime: startTime)))
            try await ghClient.triggerWorkflow(workflow: workflowToTrigger, branch: branch)

            try await Task.sleep(for: .seconds(2))

            continuation.yield(.deploying(GitHubCIDeployProgress(step: .waitingForWorkflow, startTime: startTime)))
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

    private func monitorUntilComplete(
        runId: String,
        timeoutMinutes: Int,
        gitStatus: GitHubCIGitStatus,
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

            continuation.yield(.deploying(GitHubCIDeployProgress(
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
