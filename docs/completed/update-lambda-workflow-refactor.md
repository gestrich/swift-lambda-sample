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

### Phase 1: Create UpdateLambdaWorkflow ✅ COMPLETED (2025-12-16)

**File:** `Sources/service-deploy/Workflows/UpdateLambdaWorkflow.swift`

**Status:** Created workflow following the established pattern from DeployWorkflow and DestroyWorkflow.

**Implementation Notes:**
- Workflow uses `AsyncThrowingStream<Progress, Error>` pattern
- Progress types: `checkingGitStatus`, `pushing`, `triggeringWorkflow`, `waitingForWorkflow`, `complete`
- Detail enum provides context: `gitStatus(hasCommitsToPush:)`, `workflowProgress(_:)`, `skippedPush`
- Options configurable: `skipPush`, `workflowName`, `timeoutMinutes`

**Verification:** Build succeeds, workflow compiles.

---

### Phase 2: Update DeploymentModel ✅ COMPLETED (2025-12-16)

**File:** `Sources/app-mac/Models/DeploymentModel.swift`

**Status:** Replaced `updateLambdaCode` method with workflow consumption.

**Implementation Notes:**
- Removed ~35 lines of duplicated orchestration logic
- Now consumes `UpdateLambdaWorkflow` stream
- Progress is silently consumed (can be extended for UI feedback if needed)
- Maintains same public API: `updateLambdaCode(skipPush:)`

**Future Enhancement:** If the Mac app needs to display update progress, add an `ActiveWorkflow.updateLambda(UpdateLambdaWorkflow.Progress)` case.

**Verification:** Build succeeds, DeploymentModel uses workflow.

---

### Phase 3: Update DeployInitCommand ✅ COMPLETED (2025-12-16)

**File:** `Sources/app-cli/Commands/DeployInitCommand.swift`

**Status:** Replaced `updateLambdaCode` method with workflow consumption.

**Implementation Notes:**
- Removed ~45 lines of duplicated orchestration logic
- Now consumes `UpdateLambdaWorkflow` stream with progress printing
- Progress messages printed at appropriate workflow steps
- Same user-facing output as before

**Verification:** Build succeeds, CLI uses workflow.

---

### Phase 4: Update UpdateLambdaCommand ✅ COMPLETED (2025-12-16)

**File:** `Sources/app-cli/Commands/UpdateLambdaCommand.swift`

**Status:** Replaced `run()` method with workflow consumption.

**Implementation Notes:**
- Removed ~30 lines of duplicated orchestration logic
- Now consumes `UpdateLambdaWorkflow` stream
- Minimal progress printing (pushing/waiting handled silently by SDK)
- Same user-facing output as before

**Verification:** Build succeeds, all CLI commands use workflow.

---

## Files Changed

| File | Change | Status |
|------|--------|--------|
| `Sources/service-deploy/Workflows/UpdateLambdaWorkflow.swift` | CREATE - New workflow | ✅ Done |
| `Sources/app-mac/Models/DeploymentModel.swift` | MODIFY - Use workflow | ✅ Done |
| `Sources/app-cli/Commands/DeployInitCommand.swift` | MODIFY - Use workflow | ✅ Done |
| `Sources/app-cli/Commands/UpdateLambdaCommand.swift` | MODIFY - Use workflow | ✅ Done |

---

## Benefits

1. **Single source of truth** — Orchestration logic lives in one place
2. **Follows established pattern** — Matches `DeployWorkflow` and `DestroyWorkflow`
3. **Testable** — Workflow can be tested independently of UI
4. **Progress reporting** — Stream-based progress enables future UI enhancements
5. **Separation of concerns** — App layer handles I/O, service layer handles orchestration

---

## Implementation Summary

**Completed:** 2025-12-16

All four phases have been implemented:
- Phase 1: Created `UpdateLambdaWorkflow` in service-deploy layer
- Phase 2: Updated `DeploymentModel` to consume workflow
- Phase 3: Updated `DeployInitCommand` to consume workflow
- Phase 4: Updated `UpdateLambdaCommand` to consume workflow

**Lines of Code:**
- ~110 lines of duplicated code removed from app layer
- ~105 lines of new workflow code in service layer
- Net reduction in duplication: 3 copies → 1 source of truth

**Build Status:** ✅ All targets compile successfully
