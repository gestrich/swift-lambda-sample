import Foundation
import AWSSDK
import CLISDK
import GitHubSDK
import c_service_deploy_remote

/// Workflow for querying deployment and git status.
/// Orchestrates git status, GitHub Actions status, and CloudFormation stack queries.
public struct DeployStatusWorkflow: Sendable {
    private let gitClient: GitClient
    private let ghClient: GitHubCLIClient?
    private let cfClient: CloudFormationClient
    private let stackName: String
    private let branch: String?
    private let repository: String?
    private let workflowName: String?

    public init(
        gitClient: GitClient,
        ghClient: GitHubCLIClient?,
        cfClient: CloudFormationClient,
        stackName: String,
        branch: String?,
        repository: String?,
        workflowName: String?
    ) {
        self.gitClient = gitClient
        self.ghClient = ghClient
        self.cfClient = cfClient
        self.stackName = stackName
        self.branch = branch
        self.repository = repository
        self.workflowName = workflowName
    }

    /// Components needed for status operations.
    public struct Components: Sendable {
        public let workflow: DeployStatusWorkflow
        public let cfClient: CloudFormationClient
        public let stackName: String
    }

    /// Creates a workflow and associated components by instantiating required clients.
    /// - Parameters:
    ///   - projectRoot: Root directory of the project (for git operations)
    ///   - credentialProvider: AWS credential provider for authentication
    ///   - cliClient: CLI client for executing commands
    ///   - stackName: CloudFormation stack name (defaults to CDKStackConfiguration.defaultStackName)
    /// - Returns: Components containing the workflow and CloudFormation client
    public static func create(
        projectRoot: String,
        credentialProvider: any AWSCredentialProvider,
        cliClient: CLIClient,
        stackName: String = CDKStackConfiguration.defaultStackName
    ) -> Components {
        let cfClient = CloudFormationClient(
            credentialProvider: credentialProvider,
            cliClient: cliClient
        )
        let gitClient = GitClient(repoPath: projectRoot, cliClient: cliClient)
        let githubConfig = GitHubConfiguration.loadConfig()
        let ghClient = githubConfig.map {
            GitHubCLIClient(repository: $0.repository, cliClient: cliClient)
        }

        let workflow = DeployStatusWorkflow(
            gitClient: gitClient,
            ghClient: ghClient,
            cfClient: cfClient,
            stackName: stackName,
            branch: githubConfig?.branch,
            repository: githubConfig?.repository,
            workflowName: githubConfig?.workflowName
        )

        return Components(
            workflow: workflow,
            cfClient: cfClient,
            stackName: stackName
        )
    }

    /// Progress updates from the status workflow.
    public struct Progress: Sendable {
        public let step: Step
        public let detail: Detail?

        public enum Step: Sendable, Equatable {
            case checkingGit
            case checkingGitHub
            case checkingStack
            case complete
        }

        public enum Detail: Sendable {
            case gitStatus(GitStatus)
            case githubStatus(GitHubStatus)
            case githubNotConfigured
            case githubError(String)
            case stackStatus(StackStatus)
            case stackError(String)
            case status(Status)
        }

        public init(step: Step, detail: Detail? = nil) {
            self.step = step
            self.detail = detail
        }
    }

    /// Git status information (re-exported from GitHubSDK for convenience)
    public typealias GitStatus = GitHubSDK.GitStatus

    /// GitHub Actions status information
    public struct GitHubStatus: Sendable, Equatable {
        public let repository: String
        public let branch: String
        public let latestRunStatus: String
        public let latestRunConclusion: String?

        public init(repository: String, branch: String, latestRunStatus: String, latestRunConclusion: String?) {
            self.repository = repository
            self.branch = branch
            self.latestRunStatus = latestRunStatus
            self.latestRunConclusion = latestRunConclusion
        }
    }

    /// CloudFormation stack status
    public enum StackStatus: Sendable {
        case notDeployed
        case deployed(DeployedStack)
        case deploying
        case destroying
        case failed(reason: String)
        case credentialExpired(message: String)
        case unknown(state: String)

        public init(from state: CloudFormationState) {
            switch state {
            case .notDeployed:
                self = .notDeployed
            case .deployed(let stack):
                self = .deployed(stack)
            case .deploying:
                self = .deploying
            case .destroying:
                self = .destroying
            case .failed(let reason):
                self = .failed(reason: reason)
            case .credentialExpired(let message):
                self = .credentialExpired(message: message)
            case .loading, .unknown:
                self = .unknown(state: String(describing: state))
            }
        }
    }

    /// Complete status snapshot
    public struct Status: Sendable {
        public let git: GitStatus
        public let github: GitHubStatus?
        public let stack: StackStatus

        public init(git: GitStatus, github: GitHubStatus?, stack: StackStatus) {
            self.git = git
            self.github = github
            self.stack = stack
        }
    }

    /// Run the status workflow.
    public func run() -> AsyncThrowingStream<Progress, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    try await runWorkflow(continuation: continuation)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func runWorkflow(
        continuation: AsyncThrowingStream<Progress, Error>.Continuation
    ) async throws {
        // Phase 1: Git status
        continuation.yield(Progress(step: .checkingGit))
        let gitStatus = try await fetchGitStatus()
        continuation.yield(Progress(step: .checkingGit, detail: .gitStatus(gitStatus)))

        // Phase 2: GitHub Actions status
        continuation.yield(Progress(step: .checkingGitHub))
        let githubStatus = await fetchGitHubStatus(continuation: continuation)

        // Phase 3: CloudFormation stack status
        continuation.yield(Progress(step: .checkingStack))
        let stackStatus = await fetchStackStatus(continuation: continuation)

        // Complete with full status
        let fullStatus = Status(git: gitStatus, github: githubStatus, stack: stackStatus)
        continuation.yield(Progress(step: .complete, detail: .status(fullStatus)))
        continuation.finish()
    }

    private func fetchGitStatus() async throws -> GitStatus {
        let hasUncommitted = try await gitClient.hasUncommittedChanges()
        let hasCommitsToPush = try await gitClient.hasCommitsToPush()
        let currentBranch = try await gitClient.getCurrentBranch()

        return GitStatus(
            hasUnpushedCommits: hasCommitsToPush,
            hasUncommittedChanges: hasUncommitted,
            currentBranch: currentBranch
        )
    }

    private func fetchGitHubStatus(
        continuation: AsyncThrowingStream<Progress, Error>.Continuation
    ) async -> GitHubStatus? {
        guard let ghClient, let repository, let branch else {
            continuation.yield(Progress(step: .checkingGitHub, detail: .githubNotConfigured))
            return nil
        }

        do {
            let latestRun = try await ghClient.getLatestWorkflowRun(branch: branch, workflow: workflowName)
            guard let run = latestRun else {
                let githubStatus = GitHubStatus(
                    repository: repository,
                    branch: branch,
                    latestRunStatus: "none",
                    latestRunConclusion: nil
                )
                continuation.yield(Progress(step: .checkingGitHub, detail: .githubStatus(githubStatus)))
                return githubStatus
            }
            let githubStatus = GitHubStatus(
                repository: repository,
                branch: branch,
                latestRunStatus: run.status,
                latestRunConclusion: run.conclusion
            )
            continuation.yield(Progress(step: .checkingGitHub, detail: .githubStatus(githubStatus)))
            return githubStatus
        } catch {
            continuation.yield(Progress(step: .checkingGitHub, detail: .githubError(error.localizedDescription)))
            return nil
        }
    }

    private func fetchStackStatus(
        continuation: AsyncThrowingStream<Progress, Error>.Continuation
    ) async -> StackStatus {
        do {
            let state = try await cfClient.queryState(stackName: stackName)
            let stackStatus = StackStatus(from: state)
            continuation.yield(Progress(step: .checkingStack, detail: .stackStatus(stackStatus)))
            return stackStatus
        } catch {
            let errorMessage = error.localizedDescription
            continuation.yield(Progress(step: .checkingStack, detail: .stackError(errorMessage)))
            return .unknown(state: errorMessage)
        }
    }
}
