# GitHub Actions Refactor

This document proposes refactoring the GitHub Actions feature to align with the project's layered architecture vision.

## Current Architecture

```
GitHubCISectionView (app-mac)
    → GitHubCIModel (app-mac/Models)
        → GitHubActionsClient (sdk-github) [STATEFUL]
        → GitClient (sdk-github) [stateless]

UpdateLambdaCommand (app-cli)
    → UpdateLambdaWorkflow (service-deploy)
        → GitHubActionsClient (sdk-github) [STATEFUL]
        → GitClient (sdk-github) [stateless]

StatusCommand (app-cli)
    → StatusWorkflow (service-deploy)
        → GitHubActionsClient (sdk-github) [STATEFUL]
        → GitClient (sdk-github) [stateless]
```

## Issues Identified

### 1. GitHubActionsClient is stateful (violates stateless SDK principle)

**Current implementation** (`GitHubActionsClient.swift:46-49`):

```swift
private var currentState: State = .idle
private var continuations: [UUID: AsyncStream<State>.Continuation] = [:]
```

Per `layered-architecture.md`: "SDK clients don't maintain internal state. Each method call is independent."

The client maintains:
- Internal `currentState` tracking
- Multiple `continuations` for pub/sub state broadcasting
- A `publish(_:)` method that updates state and notifies subscribers

Methods like `pushAndTriggerWorkflow()`, `triggerWorkflow()`, and `triggerWorkflowAndWait()` all call `publish()` to update internal state.

### 2. Type aliases and re-exports in service layer

**Current implementation** (`GitHubActionsService.swift:6-25`):

```swift
// Type aliases
public typealias GitHubActionsService = GitHubActionsClient
public typealias GitService = GitClient
public typealias GitHubCLIService = GitHubCLIClient

// Re-exports
@_exported import class sdk_github.GitClient
@_exported import class sdk_github.GitHubActionsClient
@_exported import struct sdk_github.GitStatus
@_exported import enum sdk_github.WorkflowProgress
// ... many more
```

Per `code-style.md`: "Type aliases and re-exports are a code smell. They obscure the actual types being used."

### 3. GitHubCIStatus has multiple independent properties (partial enum-based state)

**Current implementation** (`GitHubCIModel.swift:105-147`):

```swift
public struct GitHubCIStatus: Equatable {
    public enum RunStatus: Equatable { ... }  // Good: enum-based

    public var status: RunStatus = .unknown
    public var runDetail: GitHubRunDetail?        // Independent property
    public var hasUnpushedCommits: Bool = false   // Independent property
    public var hasUncommittedChanges: Bool = false // Independent property
    public var currentBranch: String = ""          // Independent property
}
```

Per `layered-architecture.md`: "Use enums to represent model state rather than multiple independent properties."

While `RunStatus` is an enum, the git state (`hasUnpushedCommits`, `hasUncommittedChanges`, `currentBranch`) are independent properties that could create ambiguous states.

### 4. GitHubCIModel performs async work in init

**Current implementation** (`GitHubCIModel.swift:29-32`):

```swift
public init(repoPath: String, config: GitHubConfiguration, cliClient: CLIClient) {
    // ...
    Task {
        await self.refreshStatus()  // Async work in init
    }
}
```

Async work in initializers is unpredictable and makes testing harder. The caller should explicitly trigger the initial fetch.

### 5. Redundant GitHubConfiguration wrapper

**Current implementation** (`GitHubConfiguration.swift`):

The service layer has `GitHubConfiguration` which duplicates the SDK's `GitHubActionsConfiguration` and adds file persistence. This requires a `toSDKConfiguration()` conversion method.

### 6. Default parameter values

**Current implementation** (`UpdateLambdaWorkflow.swift:59-67`):

```swift
public init(
    skipPush: Bool = false,
    workflowName: String = "Dev Deploy",
    timeoutMinutes: Int = 10
)
```

Per `code-style.md`: "Prefer requiring data explicitly rather than providing defaults."

### 7. GitHubCIModel contains business logic

The model directly calls `actionsService.pushAndTriggerWorkflow()` and `actionsService.monitorWorkflowRun()`, managing the orchestration itself rather than consuming a workflow stream.

Per `layered-architecture.md`: "Models should contain minimal logic—their role is to monitor workflow streams and update state for the UI."

## Proposed Architecture

```
GitHubCISectionView (app-mac)
    → GitHubCIModel (app-mac/Models)
        → GitHubCIWorkflow (service-deploy)
            → GitHubCLIClient (sdk-github) [stateless]
            → GitClient (sdk-github) [stateless]

UpdateLambdaCommand (app-cli)
    → UpdateLambdaWorkflow (service-deploy)
        → GitHubCLIClient (sdk-github) [stateless]
        → GitClient (sdk-github) [stateless]

StatusCommand (app-cli)
    → StatusWorkflow (service-deploy)
        → GitHubCLIClient (sdk-github) [stateless]
        → GitClient (sdk-github) [stateless]
```

### SDK Layer: Remove GitHubActionsClient, Use Stateless Clients Directly

The existing `GitHubCLIClient` and `GitClient` are already stateless. Remove `GitHubActionsClient` (the stateful orchestrator) and have workflows use the stateless clients directly.

**Keep (already stateless):**

```swift
// GitHubCLIClient - stateless wrapper around `gh` CLI
public actor GitHubCLIClient {
    public func listWorkflowRuns(branch: String, limit: Int, workflow: String?) async throws -> [GitHubWorkflowRun]
    public func getLatestWorkflowRun(branch: String, workflow: String?) async throws -> GitHubWorkflowRun?
    public func getRunDetail(runId: String) async throws -> GitHubRunDetail
    public func triggerWorkflow(workflow: String, branch: String, output: CLIOutputStream?) async throws
    // ...
}

// GitClient - stateless wrapper around git commands
public actor GitClient {
    public func hasUncommittedChanges() async throws -> Bool
    public func hasCommitsToPush() async throws -> Bool
    public func getCurrentBranch() async throws -> String
    public func push(output: CLIOutputStream?) async throws
    // ...
}
```

**Remove:** `GitHubActionsClient` (the stateful orchestrator). Move its orchestration logic to workflows.

### Service Layer: Create GitHubCIWorkflow

A new workflow that orchestrates GitHub CI operations, yielding complete state updates via stream. Following the `DeployWorkflow` pattern, the workflow yields self-contained state that the model can assign directly.

```swift
public struct GitHubCIWorkflow: Sendable {
    private let ghClient: GitHubCLIClient
    private let gitClient: GitClient
    private let repository: String
    private let branch: String
    private let workflowName: String?

    public init(
        ghClient: GitHubCLIClient,
        gitClient: GitClient,
        repository: String,
        branch: String,
        workflowName: String?
    ) {
        self.ghClient = ghClient
        self.gitClient = gitClient
        self.repository = repository
        self.branch = branch
        self.workflowName = workflowName
    }

    /// Creates a workflow from configuration file.
    public static func create(
        projectRoot: String,
        cliClient: CLIClient
    ) throws -> GitHubCIWorkflow {
        guard let config = GitHubConfiguration.loadConfig() else {
            throw DeployError.configurationMissing(
                file: GitHubConfiguration.configPath,
                hint: "Create with: {\"repository\": \"owner/repo\", \"branch\": \"dev\"}"
            )
        }

        let ghClient = GitHubCLIClient(repository: config.repository, cliClient: cliClient)
        let gitClient = GitClient(repoPath: projectRoot, cliClient: cliClient)

        return GitHubCIWorkflow(
            ghClient: ghClient,
            gitClient: gitClient,
            repository: config.repository,
            branch: config.branch,
            workflowName: config.workflowName
        )
    }

    // MARK: - Queries (one-shot)

    /// Get current git and GitHub status.
    /// Returns a StatusSnapshot for refresh operations.
    public func getStatus() async throws -> StatusSnapshot {
        let gitStatus = GitStatus(
            hasUnpushedCommits: try await gitClient.hasCommitsToPush(),
            hasUncommittedChanges: try await gitClient.hasUncommittedChanges(),
            currentBranch: try await gitClient.getCurrentBranch()
        )

        let latestRun = try await ghClient.getLatestWorkflowRun(branch: branch, workflow: workflowName)
        let runInfo = latestRun.map { WorkflowRunInfo(from: $0) }

        return StatusSnapshot(
            gitStatus: gitStatus,
            latestRun: runInfo
        )
    }

    /// Lightweight snapshot for status refresh (not a completed operation).
    /// The model converts this to GitHubCISnapshot.
    public struct StatusSnapshot: Sendable, Equatable {
        public let gitStatus: GitStatus
        public let latestRun: WorkflowRunInfo?

        /// Whether there's an in-progress run that should be monitored
        public var inProgressRunId: String? {
            guard let run = latestRun, run.isInProgress else { return nil }
            return run.id
        }
    }

    // MARK: - Operations (streaming)

    /// Push commits and deploy via GitHub Actions.
    /// Returns stream of state updates until workflow completes.
    public func pushAndDeploy(
        timeoutMinutes: Int
    ) -> AsyncThrowingStream<State, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await runPushAndDeploy(
                        timeoutMinutes: timeoutMinutes,
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

    /// Monitor an existing workflow run.
    public func monitorRun(
        runId: String,
        timeoutMinutes: Int
    ) -> AsyncThrowingStream<State, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await runMonitor(
                        runId: runId,
                        timeoutMinutes: timeoutMinutes,
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

        // Check git status (also capture for final snapshot)
        continuation.yield(.deploying(State.DeployProgress(step: .checkingGitStatus, startTime: startTime)))
        let gitStatus = GitStatus(
            hasUnpushedCommits: try await gitClient.hasCommitsToPush(),
            hasUncommittedChanges: try await gitClient.hasUncommittedChanges(),
            currentBranch: try await gitClient.getCurrentBranch()
        )

        if gitStatus.hasUnpushedCommits {
            // Push and wait for workflow
            let beforeRunId = try await ghClient.getLatestWorkflowRun(branch: branch, workflow: workflowName)?.id

            continuation.yield(.deploying(State.DeployProgress(step: .pushing, startTime: startTime)))
            try await gitClient.push()

            continuation.yield(.deploying(State.DeployProgress(step: .waitingForWorkflow, startTime: startTime)))
            let runId = try await waitForNewRun(afterRunId: beforeRunId, timeout: .seconds(60))

            try await monitorUntilComplete(
                runId: runId,
                timeoutMinutes: timeoutMinutes,
                gitStatus: gitStatus,
                continuation: continuation,
                startTime: startTime
            )
        } else {
            // Trigger workflow manually
            let workflowToTrigger = workflowName ?? "Dev Deploy"
            let beforeRunId = try await ghClient.getLatestWorkflowRun(branch: branch, workflow: workflowName)?.id

            continuation.yield(.deploying(State.DeployProgress(step: .triggering(workflow: workflowToTrigger), startTime: startTime)))
            try await ghClient.triggerWorkflow(workflow: workflowToTrigger, branch: branch)

            try await Task.sleep(for: .seconds(2))

            continuation.yield(.deploying(State.DeployProgress(step: .waitingForWorkflow, startTime: startTime)))
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

    private func runMonitor(
        runId: String,
        timeoutMinutes: Int,
        continuation: AsyncThrowingStream<State, Error>.Continuation
    ) async throws {
        let startTime = Date()

        // Fetch current git status for the final snapshot
        let gitStatus = GitStatus(
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
        gitStatus: GitStatus,
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
                // Yield completed snapshot with all data
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

            // Yield progress with run detail for UI
            continuation.yield(.deploying(State.DeployProgress(
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

    // MARK: - Types

    /// Complete snapshot of GitHub CI state (yielded on completion).
    /// Follows the DeploymentSnapshot pattern - contains all data needed for display.
    public struct GitHubCISnapshot: Sendable, Equatable {
        public let status: Status
        public let gitStatus: GitStatus
        public let runDetail: GitHubRunDetail?

        public enum Status: Sendable, Equatable {
            case idle(lastRun: WorkflowRunInfo?)
            case success(runId: String)
            case failed(runId: String, reason: String)
        }

        // MARK: - Convenience Accessors

        public var runId: String? {
            switch status {
            case .idle(let lastRun): return lastRun?.id
            case .success(let id), .failed(let id, _): return id
            }
        }

        public var canDeploy: Bool { true }

        // MARK: - Factory Methods

        public static func success(runId: String, gitStatus: GitStatus) -> GitHubCISnapshot {
            GitHubCISnapshot(status: .success(runId: runId), gitStatus: gitStatus, runDetail: nil)
        }

        public static func failed(runId: String, reason: String, gitStatus: GitStatus) -> GitHubCISnapshot {
            GitHubCISnapshot(status: .failed(runId: runId, reason: reason), gitStatus: gitStatus, runDetail: nil)
        }
    }

    public struct GitStatus: Sendable, Equatable {
        public let hasUnpushedCommits: Bool
        public let hasUncommittedChanges: Bool
        public let currentBranch: String

        public static let empty = GitStatus(
            hasUnpushedCommits: false,
            hasUncommittedChanges: false,
            currentBranch: ""
        )
    }

    /// State yielded by a running workflow.
    /// Follows the WorkflowState pattern - yields `.completed(snapshot)` when done.
    public enum State: Sendable, Equatable {
        case deploying(DeployProgress)
        case completed(GitHubCISnapshot)

        public struct DeployProgress: Sendable, Equatable {
            public let step: Step
            public let startTime: Date
            public let runDetail: GitHubRunDetail?

            public init(step: Step, startTime: Date, runDetail: GitHubRunDetail? = nil) {
                self.step = step
                self.startTime = startTime
                self.runDetail = runDetail
            }
        }

        public enum Step: Sendable, Equatable {
            case checkingGitStatus
            case pushing
            case triggering(workflow: String)
            case waitingForWorkflow
            case monitoring(runId: String)
        }

        /// Start time from any in-progress state
        public var startTime: Date? {
            if case .deploying(let p) = self { return p.startTime }
            return nil
        }

        /// Final snapshot if completed
        public var completedSnapshot: GitHubCISnapshot? {
            if case .completed(let snapshot) = self { return snapshot }
            return nil
        }
    }
}

public enum GitHubCIWorkflowError: Error, LocalizedError {
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
```

### Service Layer: Remove Type Aliases and Re-exports

Delete `GitHubActionsService.swift` (the file with all the type aliases). Consumers should import `sdk_github` directly.

### Service Layer: Consolidate Configuration

Keep `GitHubConfiguration` for file persistence but remove the redundant `toSDKConfiguration()` conversion. The workflow can use `GitHubConfiguration` properties directly since they match.

### App Layer: Minimal GitHubCIModel

The model becomes a thin state holder that consumes workflow streams, following the `DeploymentModel` pattern exactly. The key is `ModelState.init(from:prior:)` which does minimal transformation.

```swift
import sdk_github
import service_deploy
import Foundation
import Observation

/// Observable model for GitHub CI operations.
/// This is a thin model that uses GitHubCIWorkflow and maintains observable state.
///
/// Per the layered architecture:
/// - App layer (this model): @Observable state + UI coordination
/// - Service layer (workflow): Multi-step orchestration, returns AsyncThrowingStream
/// - SDK layer (clients): Stateless execute/query operations
@MainActor
@Observable
public final class GitHubCIModel {
    // MARK: - Unified State Machine

    /// Single source of truth for all model state
    public private(set) var state: ModelState = .uninitialized

    // MARK: - Configuration

    public let repository: String
    public let branch: String

    // MARK: - Private

    private let workflow: GitHubCIWorkflow

    // MARK: - Init

    public init(workflow: GitHubCIWorkflow, repository: String, branch: String) {
        self.workflow = workflow
        self.repository = repository
        self.branch = branch
    }

    // MARK: - Derived State (Convenience Accessors)

    public var isIdle: Bool { state.isIdle }
    public var canDeploy: Bool { state.canDeploy }

    // MARK: - Refresh Operations

    /// Refresh status from GitHub.
    /// If an operation is in progress, automatically starts monitoring it.
    public func refresh() async {
        guard state.isIdle else { return }

        let prior = state.snapshot
        state = .loading(prior: prior)

        do {
            let statusSnapshot = try await workflow.getStatus()

            // Check if a workflow run is in progress and resume monitoring
            if let inProgressId = statusSnapshot.inProgressRunId {
                await monitorRun(runId: inProgressId, timeoutMinutes: 20)
            } else {
                state = .ready(GitHubCISnapshot(
                    status: .idle(lastRun: statusSnapshot.latestRun),
                    gitStatus: statusSnapshot.gitStatus,
                    runDetail: nil
                ))
            }
        } catch {
            state = .ready(GitHubCISnapshot(
                status: .failed(runId: "", reason: error.localizedDescription),
                gitStatus: prior?.gitStatus ?? .empty,
                runDetail: nil
            ))
        }
    }

    // MARK: - Deploy Operations

    /// Push commits and deploy via GitHub Actions.
    public func pushAndDeploy(timeoutMinutes: Int) async {
        guard state.canDeploy else { return }

        let prior = state.snapshot

        do {
            for try await workflowState in workflow.pushAndDeploy(timeoutMinutes: timeoutMinutes) {
                state = ModelState(from: workflowState, prior: prior)
            }
        } catch {
            state = .ready(GitHubCISnapshot(
                status: .failed(runId: "", reason: error.localizedDescription),
                gitStatus: prior?.gitStatus ?? .empty,
                runDetail: nil
            ))
        }
    }

    /// Monitor an existing workflow run.
    public func monitorRun(runId: String, timeoutMinutes: Int) async {
        let prior = state.snapshot

        do {
            for try await workflowState in workflow.monitorRun(runId: runId, timeoutMinutes: timeoutMinutes) {
                state = ModelState(from: workflowState, prior: prior)
            }
        } catch {
            state = .ready(GitHubCISnapshot(
                status: .failed(runId: runId, reason: error.localizedDescription),
                gitStatus: prior?.gitStatus ?? .empty,
                runDetail: nil
            ))
        }
    }

    /// Open workflow logs in browser.
    public func viewWorkflowLogs(runId: String) {
        let url = "https://github.com/\(repository)/actions/runs/\(runId)"
        if let nsURL = URL(string: url) {
            NSWorkspace.shared.open(nsURL)
        }
    }

    // MARK: - Nested Types

    /// Unified state machine for the GitHub CI model.
    /// Uses service-layer types (GitHubCIWorkflow.State, GitHubCISnapshot) for actual state,
    /// while ModelState handles app-layer concerns (loading, prior preservation).
    public enum ModelState {
        case uninitialized
        case loading(prior: GitHubCISnapshot?)
        case ready(GitHubCISnapshot)
        case operating(GitHubCIWorkflow.State, prior: GitHubCISnapshot?)

        // MARK: - Convenience Initializer

        /// Construct ModelState from a workflow state plus app-layer prior.
        /// This is the key integration point between workflows and the model.
        public init(from workflowState: GitHubCIWorkflow.State, prior: GitHubCISnapshot?) {
            if let snapshot = workflowState.completedSnapshot {
                self = .ready(snapshot)
            } else {
                self = .operating(workflowState, prior: prior)
            }
        }

        // MARK: - Convenience Accessors

        public var snapshot: GitHubCISnapshot? {
            switch self {
            case .uninitialized: return nil
            case .loading(let prior): return prior
            case .ready(let snapshot): return snapshot
            case .operating(_, let prior): return prior
            }
        }

        public var workflowState: GitHubCIWorkflow.State? {
            if case .operating(let state, _) = self { return state }
            return nil
        }

        public var isIdle: Bool {
            switch self {
            case .uninitialized, .ready: return true
            case .loading, .operating: return false
            }
        }

        public var canDeploy: Bool {
            switch self {
            case .ready(let snapshot): return snapshot.canDeploy
            case .uninitialized: return true
            case .loading, .operating: return false
            }
        }

        /// Run detail from workflow state (for UI during monitoring)
        public var runDetail: GitHubRunDetail? {
            guard case .operating(let workflowState, _) = self,
                  case .deploying(let progress) = workflowState else {
                return nil
            }
            return progress.runDetail
        }

        /// Operation start time (for elapsed time display)
        public var operationStartTime: Date? {
            workflowState?.startTime
        }
    }
}
```

**Key simplifications from DeploymentModel pattern:**

1. **`ModelState.init(from:prior:)`** - The trivial conversion that just checks `completedSnapshot`
2. **Operations just do:** `state = ModelState(from: workflowState, prior: prior)`
3. **No switch on workflow state** - The workflow yields complete snapshots
4. **Workflow owns all business logic** - Model just observes and assigns state

## Migration Steps

- [ ] **Phase 1: Create GitHubCIWorkflow and State types** (service-deploy)
   - Create `GitHubCISnapshot` (stable state, like `DeploymentSnapshot`)
   - Create `GitHubCIWorkflow.State` enum (what workflows yield)
   - Create `GitHubCIWorkflow` struct with:
     - `getStatus()` → `StatusSnapshot` (for refresh)
     - `pushAndDeploy()` → `AsyncThrowingStream<State, Error>`
     - `monitorRun()` → `AsyncThrowingStream<State, Error>`
   - Move orchestration logic from `GitHubActionsClient`

- [ ] **Phase 2: Remove type aliases and re-exports** (service-deploy)
   - Delete `GitHubActionsService.swift`
   - Update imports in dependent files to use `sdk_github` directly

- [ ] **Phase 3: Refactor GitHubCIModel** (app-mac)
   - Create `ModelState` enum with `init(from:prior:)`
   - Remove async work from init
   - Operations use: `state = ModelState(from: workflowState, prior: prior)`
   - No switch statements on workflow state

- [ ] **Phase 4: Update UpdateLambdaWorkflow** (service-deploy)
   - Use GitHubCLIClient and GitClient directly (already stateless)
   - Remove dependency on GitHubActionsClient

- [ ] **Phase 5: Update StatusWorkflow** (service-deploy)
   - Use GitHubCLIClient and GitClient directly
   - Remove dependency on GitHubActionsClient

- [ ] **Phase 6: Remove GitHubActionsClient** (sdk-github)
   - Delete the stateful client
   - Keep GitHubCLIClient and GitClient (already stateless)
   - Keep data models (GitHubWorkflowRun, GitHubRunDetail, etc.)

- [ ] **Phase 7: Update GitHubCISectionView** (app-mac)
   - Update to use new model state enum
   - Update model initialization

- [ ] **Phase 8: Update dependent code**
   - `RemoteServiceView.swift` - Update model creation
   - Any tests that reference removed types

## Files Affected

| File | Action |
|------|--------|
| `Sources/sdk-github/GitHubActionsClient.swift` | Delete (stateful orchestrator) |
| `Sources/sdk-github/GitHubCLIClient.swift` | Keep (already stateless) |
| `Sources/sdk-github/GitClient.swift` | Keep (already stateless) |
| `Sources/service-deploy/GitHubService/GitHubActionsService.swift` | Delete |
| `Sources/service-deploy/GitHubService/GitHubConfiguration.swift` | Keep (simplify) |
| `Sources/service-deploy/Workflows/GitHubCIWorkflow.swift` | Create |
| `Sources/service-deploy/Workflows/UpdateLambdaWorkflow.swift` | Update |
| `Sources/service-deploy/Workflows/StatusWorkflow.swift` | Update |
| `Sources/app-mac/Models/GitHubCIModel.swift` | Refactor |
| `Sources/app-mac/RemoteService/GitHubCISectionView.swift` | Update |
| `Sources/app-mac/RemoteService/RemoteServiceView.swift` | Update |

## Benefits

1. **Impossible invalid states** - Enum guarantees only valid state combinations
2. **Stateless SDK** - SDK clients become pure query/execute functions
3. **Clear separation** - Workflows orchestrate, models hold state for UI
4. **Testable** - Workflows can be tested independently of UI
5. **No type confusion** - Direct imports instead of aliases/re-exports
6. **Predictable init** - No async work in constructors
7. **Consistent patterns** - Follows established CloudWatchLogsWorkflow pattern

## Design Decisions

### Why remove GitHubActionsClient instead of refactoring it?

The `GitHubActionsClient` is essentially a stateful orchestrator masquerading as an SDK client. Its responsibilities should be split:

1. **Query/Execute operations** - Already handled by the stateless `GitHubCLIClient` and `GitClient`
2. **Orchestration logic** - Belongs in a workflow (new `GitHubCIWorkflow`)
3. **State management** - Belongs in the model layer

By removing it entirely, we avoid the temptation to add state back to the SDK layer.

### Why keep GitHubConfiguration separate from SDK's GitHubActionsConfiguration?

The service-layer `GitHubConfiguration` provides file persistence (`loadConfig()`, `save()`), which is app-specific behavior. The SDK shouldn't know about file paths or persistence. However, we can simplify by using the same property names and avoiding conversion methods.

### WorkflowRunInfo reuse

The existing `WorkflowRunInfo` struct in sdk-github is already well-designed with computed properties (`isSuccess`, `isFailed`, `isInProgress`, `relativeTime`). The workflow can create these directly from `GitHubWorkflowRun` responses.

### Model Pattern Comparison

**Before (current GitHubCIModel)** - Model does switch/case transformation:
```swift
for try await workflowState in workflow.pushAndDeploy() {
    switch workflowState {
    case .operating:
        state = .operating(workflowState: workflowState, prior: prior)
    case .completed(let runId):
        state = .ready(Snapshot(
            gitStatus: prior?.gitStatus ?? .empty,
            latestRunStatus: .success(runId: runId)
        ))
    case .failed(let runId, let reason):
        state = .ready(Snapshot(
            gitStatus: prior?.gitStatus ?? .empty,
            latestRunStatus: .failed(runId: runId, reason: reason)
        ))
    }
}
```

**After (DeploymentModel pattern)** - Model just assigns:
```swift
for try await workflowState in workflow.pushAndDeploy() {
    state = ModelState(from: workflowState, prior: prior)
}
```

The key is that `ModelState.init(from:prior:)` does the trivial check:
```swift
public init(from workflowState: GitHubCIWorkflow.State, prior: GitHubCISnapshot?) {
    if let snapshot = workflowState.completedSnapshot {
        self = .ready(snapshot)
    } else {
        self = .operating(workflowState, prior: prior)
    }
}
```

This works because the workflow yields `.completed(GitHubCISnapshot)` with all required data when done.
