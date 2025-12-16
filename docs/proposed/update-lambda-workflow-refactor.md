# UpdateLambdaWorkflow Refactor

## Problem

The `updateLambdaCode` logic is duplicated in the app layer and violates the layered architecture principles:

### Current State

**DeploymentModel.updateLambdaCode** (`app-mac`, lines 346-381):
```swift
public func updateLambdaCode(skipPush: Bool = false) async throws {
    guard let githubClient = githubClient else { throw ... }

    if !skipPush {
        let hasCommitsToPush = try await gitClient.hasCommitsToPush()
        if hasCommitsToPush {
            let beforeRunId = try await githubClient.getLatestRunId()
            try await gitClient.push()
            try await githubClient.waitForNewWorkflowCompletion(afterRunId: beforeRunId, ...)
        } else {
            print("\n✅ No commits to push")
            try await githubClient.triggerWorkflowAndWait(workflowName: "Dev Deploy", ...)
        }
    } else {
        print("\n⏭️  Skipping git push...")
        try await githubClient.triggerWorkflowAndWait(workflowName: "Dev Deploy", ...)
    }
}
```

**DeployInitCommand.updateLambdaCode** (`app-cli`, lines 194-242):
- Nearly identical logic
- Same orchestration pattern
- Same embedded print statements

**UpdateLambdaCommand.run** (`app-cli`, lines 17-66):
- Third copy of the same logic
- Standalone command with identical orchestration

### Architecture Violations

Per `docs/architecture/layered-architecture.md`:

1. **"Models should contain minimal logic"** — `DeploymentModel` has significant orchestration logic, not just stream consumption

2. **"Workflows for Orchestration"** — Multi-step operations should live in workflows returning `AsyncThrowingStream<Progress, Error>`. This is the pattern used by `DeployWorkflow` and `DestroyWorkflow`

3. **"Apps handle I/O"** — Print statements are embedded in business logic rather than being app-layer concerns

4. **Code Duplication** — Same logic exists in three app-layer locations

---

## Solution

Create `UpdateLambdaWorkflow` in `service-deploy/Workflows/` following the established pattern.

### Target Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                          APP                                 │
│  DeploymentModel         DeployInitCommand                   │
│  (consume stream,        (consume stream,                    │
│   update state)           print progress)                    │
└────────────────────────┬────────────────────────────────────┘
                         │ uses
                         ▼
┌─────────────────────────────────────────────────────────────┐
│                       SERVICE                                │
│                  UpdateLambdaWorkflow                        │
│  run() → AsyncThrowingStream<Progress, Error>                │
│  Steps: checkingGit → pushing → waitingForWorkflow → done    │
└────────────────────────┬────────────────────────────────────┘
                         │ uses
                         ▼
┌─────────────────────────────────────────────────────────────┐
│                         SDK                                  │
│         GitClient           GitHubActionsClient              │
└─────────────────────────────────────────────────────────────┘
```

---

## Implementation

### Phase 1: Create UpdateLambdaWorkflow

**File:** `Sources/service-deploy/Workflows/UpdateLambdaWorkflow.swift`

```swift
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
            // Skip git operations, go straight to triggering
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

        // Check git status
        continuation.yield(Progress(step: .checkingGitStatus))
        let hasCommitsToPush = try await gitClient.hasCommitsToPush()
        continuation.yield(Progress(step: .checkingGitStatus, detail: .gitStatus(hasCommitsToPush: hasCommitsToPush)))

        if hasCommitsToPush {
            // Push commits and wait for triggered workflow
            let beforeRunId = try await githubClient.getLatestRunId()

            continuation.yield(Progress(step: .pushing))
            try await gitClient.push()

            continuation.yield(Progress(step: .waitingForWorkflow))
            try await githubClient.waitForNewWorkflowCompletion(
                afterRunId: beforeRunId,
                timeoutMinutes: options.timeoutMinutes
            )
        } else {
            // No commits - trigger workflow manually
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
```

**Verification:** Build succeeds, workflow compiles.

---

### Phase 2: Update DeploymentModel

**File:** `Sources/app-mac/Models/DeploymentModel.swift`

Replace the `updateLambdaCode` method with workflow consumption:

```swift
// MARK: - Lambda Code Updates

/// Update Lambda code via GitHub Actions
public func updateLambdaCode(skipPush: Bool = false) async throws {
    guard let githubClient = githubClient else {
        throw DeployError.configurationMissing(
            file: "~/.swiftSampleDemo/github-config.json",
            hint: "Create with: {\"repository\": \"owner/repo\", \"branch\": \"dev\"}"
        )
    }

    let workflow = UpdateLambdaWorkflow(
        gitClient: gitClient,
        githubClient: githubClient
    )

    let options = UpdateLambdaWorkflow.Options(skipPush: skipPush)

    for try await progress in workflow.run(options: options) {
        // Model can track progress if needed for UI
        // For now, workflow handles the orchestration
        _ = progress
    }
}
```

**Note:** If the Mac app needs to display update progress, add an `ActiveWorkflow.updateLambda(UpdateLambdaWorkflow.Progress)` case and update the model accordingly.

**Verification:** Build succeeds, DeploymentModel uses workflow.

---

### Phase 3: Update DeployInitCommand

**File:** `Sources/app-cli/Commands/DeployInitCommand.swift`

Replace the `updateLambdaCode` method:

```swift
private func updateLambdaCode(projectRoot: String, cliClient: CLIClient, skipPush: Bool) async throws {
    guard let githubConfig = GitHubConfiguration.loadConfig() else {
        throw DeployError.configurationMissing(
            file: "~/.swiftSampleDemo/github-config.json",
            hint: "Create with: {\"repository\": \"owner/repo\", \"branch\": \"dev\"}"
        )
    }

    let githubClient = makeGitHubActionsClient(
        repoPath: projectRoot,
        config: githubConfig,
        cliClient: cliClient
    )
    let gitClient = GitClient(repoPath: projectRoot, cliClient: cliClient)

    let workflow = UpdateLambdaWorkflow(
        gitClient: gitClient,
        githubClient: githubClient
    )

    print("\n📦 Updating Lambda code...")

    let options = UpdateLambdaWorkflow.Options(skipPush: skipPush)

    for try await progress in workflow.run(options: options) {
        switch progress.step {
        case .checkingGitStatus:
            if case .skippedPush = progress.detail {
                print("   ⏭️  Skipping git push (--skip-push enabled)")
            }

        case .pushing:
            print("   Pushing commits...")

        case .triggeringWorkflow:
            if case .gitStatus(let hasCommits) = progress.detail, !hasCommits {
                print("   ✅ No commits to push")
            }
            print("   🔄 Triggering workflow...")

        case .waitingForWorkflow:
            print("   Waiting for GitHub Actions workflow...")

        case .complete:
            print("   ✅ Lambda code updated")
        }
    }
}
```

**Verification:** Build succeeds, CLI uses workflow.

---

### Phase 4: Update UpdateLambdaCommand

**File:** `Sources/app-cli/Commands/UpdateLambdaCommand.swift`

Replace the entire `run()` method:

```swift
mutating func run() async throws {
    print("🚀 Updating Lambda code...\n")

    let projectRoot = FileManager.default.currentDirectoryPath

    guard let githubConfig = GitHubConfiguration.loadConfig()?.toSDKConfiguration() else {
        throw DeployError.configurationMissing(
            file: GitHubConfiguration.configPath,
            hint: "Create with: {\"repository\": \"owner/repo\", \"branch\": \"dev\"}"
        )
    }

    let cliClient = CLIClient(defaultWorkingDirectory: projectRoot)
    let gitClient = GitClient(repoPath: projectRoot, cliClient: cliClient)
    let githubClient = GitHubActionsClient(
        repoPath: projectRoot,
        config: githubConfig,
        cliClient: cliClient
    )

    let workflow = UpdateLambdaWorkflow(
        gitClient: gitClient,
        githubClient: githubClient
    )

    let options = UpdateLambdaWorkflow.Options(skipPush: skipPush)

    for try await progress in workflow.run(options: options) {
        switch progress.step {
        case .checkingGitStatus:
            if case .skippedPush = progress.detail {
                print("\n⏭️  Skipping git push (--skip-push enabled)")
            }

        case .pushing:
            break // Git push happens silently

        case .triggeringWorkflow:
            if case .gitStatus(let hasCommits) = progress.detail, !hasCommits {
                print("\n✅ No commits to push")
            }
            print("🔄 Triggering workflow...\n")

        case .waitingForWorkflow:
            break // Waiting handled by SDK

        case .complete:
            break
        }
    }

    print("\n🎉 Lambda deployment completed successfully!")
}
```

**Verification:** Build succeeds, all CLI commands use workflow.

---

## Files Changed

| File | Change |
|------|--------|
| `Sources/service-deploy/Workflows/UpdateLambdaWorkflow.swift` | CREATE - New workflow |
| `Sources/app-mac/Models/DeploymentModel.swift` | MODIFY - Use workflow |
| `Sources/app-cli/Commands/DeployInitCommand.swift` | MODIFY - Use workflow |
| `Sources/app-cli/Commands/UpdateLambdaCommand.swift` | MODIFY - Use workflow |

---

## Benefits

1. **Single source of truth** — Orchestration logic lives in one place
2. **Follows established pattern** — Matches `DeployWorkflow` and `DestroyWorkflow`
3. **Testable** — Workflow can be tested independently of UI
4. **Progress reporting** — Stream-based progress enables future UI enhancements
5. **Separation of concerns** — App layer handles I/O, service layer handles orchestration
