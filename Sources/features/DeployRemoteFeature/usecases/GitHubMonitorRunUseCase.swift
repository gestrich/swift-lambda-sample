import Foundation
import GitHubSDK
import CLISDK
import Uniflow

/// Use case for monitoring an existing GitHub Actions run.
/// Polls the run status and yields state updates until completion.
public struct GitHubMonitorRunUseCase: StreamingUseCase {
    public typealias State = GitHubCIState
    public typealias Result = State

    private let ghClient: GitHubCLIClient
    private let gitClient: GitClient

    public init(
        ghClient: GitHubCLIClient,
        gitClient: GitClient
    ) {
        self.ghClient = ghClient
        self.gitClient = gitClient
    }

    // MARK: - Options

    public struct Options: Sendable {
        public let runId: String
        public let timeoutMinutes: Int

        public init(runId: String, timeoutMinutes: Int = 10) {
            self.runId = runId
            self.timeoutMinutes = timeoutMinutes
        }
    }

    // MARK: - StreamingUseCase Conformance

    public func stream(options: Options) -> AsyncThrowingStream<State, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await runMonitor(
                        runId: options.runId,
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

    private func runMonitor(
        runId: String,
        timeoutMinutes: Int,
        continuation: AsyncThrowingStream<State, Error>.Continuation
    ) async throws {
        let startTime = Date()

        let gitStatus = GitHubCIGitStatus(
            hasUnpushedCommits: try await gitClient.hasCommitsToPush(),
            hasUncommittedChanges: try await gitClient.hasUncommittedChanges(),
            currentBranch: try await gitClient.getCurrentBranch()
        )

        try await monitorUntilComplete(
            runId: runId,
            timeoutMinutes: timeoutMinutes,
            gitStatus: gitStatus,
            continuation: continuation,
            startTime: startTime
        )
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
                throw GitHubCIUseCaseError.timeout(operation: "workflow monitoring", duration: timeout)
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
}
