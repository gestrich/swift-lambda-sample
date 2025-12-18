# DeployRemoteModel: Migrate refresh() to RefreshWorkflow

**Status:** In Progress
**Date:** 2025-12-18
**Related:** [workflow-refactor.md](./workflow-refactor.md), [layered-architecture.md](../architecture/layered-architecture.md)

## Objective

Migrate `DeployRemoteModel.refresh()` from direct SDK client calls to a `RefreshWorkflow`, completing the workflow-based architecture pattern established in the workflow refactor.

## Background

The `DeployRemoteModel` was created during the workflow refactor (Phase 5) to use workflows for operations. However, `refresh()` still makes direct calls to `cfClient.queryState()`, violating the layered architecture principle that models should only consume workflows.

### Current Violation

```swift
// DeployRemoteModel.swift:151
let queriedState = try await cfClient.queryState(stackName: stackName)  // Direct SDK call
```

### Current State

| Method | Uses Workflow? | Notes |
|--------|----------------|-------|
| `deploy()` | Yes | Uses `DeployWorkflow` |
| `destroy()` | Yes | Uses `DestroyWorkflow` |
| `updateLambdaCode()` | Yes | Uses `UpdateLambdaWorkflow` |
| `resumeMonitoring()` | Yes | Uses `ResumeMonitoringWorkflow` |
| `refresh()` | **No** | Direct `cfClient.queryState()` call |

## Technical Approach

### Create RefreshWorkflow

Create a new `RefreshWorkflow` in `DeployRemoteFeature` that:

1. Queries CloudFormation state
2. If an operation is in progress, delegates to `ResumeMonitoringWorkflow`
3. Yields `WorkflowState` compatible with `ModelState.init(from:prior:)`

```swift
// Sources/features/DeployRemoteFeature/workflows/RefreshWorkflow.swift

import Foundation
import AWSSDK
import Uniflow

/// Workflow for refreshing deployment state from AWS.
/// Queries CloudFormation and monitors any in-progress operations to completion.
public struct RefreshWorkflow: StreamingWorkflow {
    public typealias Options = Void
    public typealias State = WorkflowState
    public typealias Result = State

    private let cfClient: CloudFormationClient
    private let stackName: String

    public init(cfClient: CloudFormationClient, stackName: String) {
        self.cfClient = cfClient
        self.stackName = stackName
    }

    public func stream(options: Options) -> AsyncThrowingStream<State, Error> {
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
        continuation: AsyncThrowingStream<State, Error>.Continuation
    ) async throws {
        // Query current state
        let cfState = try await cfClient.queryState(stackName: stackName)

        // If operation in progress, delegate to ResumeMonitoringWorkflow
        switch cfState {
        case .deploying, .destroying:
            let monitorWorkflow = ResumeMonitoringWorkflow(
                cfClient: cfClient,
                stackName: stackName
            )
            for try await state in monitorWorkflow.run(initialState: cfState) {
                continuation.yield(state)
            }

        default:
            // Stable state - yield completed immediately
            let snapshot = DeploymentSnapshot.from(cfState)
            continuation.yield(.completed(snapshot))
        }

        continuation.finish()
    }
}
```

### Update DeployRemoteModel

Simplify `refresh()` to consume the workflow:

```swift
// Before (current)
public func refresh() async {
    guard state.isIdle else { return }
    let prior = state.snapshot
    state = .loading(prior: prior)

    do {
        let queriedState = try await cfClient.queryState(stackName: stackName)

        switch queriedState {
        case .deploying, .destroying:
            await resumeMonitoring(initialState: queriedState, prior: prior)
        default:
            state = .ready(DeploymentSnapshot.from(queriedState))
        }
    } catch let error as DeploymentError {
        // ... complex error handling
    } catch {
        // ... more error handling
    }
}

// After (simplified)
public func refresh() async {
    guard state.isIdle else { return }
    let prior = state.snapshot
    state = .loading(prior: prior)

    let workflow = RefreshWorkflow(cfClient: cfClient, stackName: stackName)

    do {
        for try await workflowState in workflow.stream(options: ()) {
            state = ModelState(from: workflowState, prior: prior)
        }
    } catch {
        lastOperationError = error
        state = .ready(.failed(reason: error.localizedDescription, preserving: prior))
    }
}
```

### Remove resumeMonitoring() from Model

The `resumeMonitoring()` private method becomes unnecessary since `RefreshWorkflow` handles this internally:

```swift
// DELETE this method - absorbed into RefreshWorkflow
private func resumeMonitoring(initialState: CloudFormationState, prior: DeploymentSnapshot?) async {
    // ...
}
```

### Remove Unused SDK Clients from Model

Remove `gitClient` from the model - it's stored but never used:

```swift
// DELETE - unused
private let gitClient: GitClient
```

Also remove from initializer and any related setup code.

## Implementation Steps

| Step | Description | Files | Status |
|------|-------------|-------|--------|
| 1 | Create `RefreshWorkflow` | `Sources/features/DeployRemoteFeature/workflows/RefreshWorkflow.swift` | ✅ Complete |
| 2 | Update `refresh()` in model | `Sources/apps/MacApp/Models/DeployRemoteModel.swift` | Pending |
| 3 | Remove `resumeMonitoring()` | `Sources/apps/MacApp/Models/DeployRemoteModel.swift` | Pending |
| 4 | Remove `gitClient` from model | `Sources/apps/MacApp/Models/DeployRemoteModel.swift` | Pending |
| 5 | Run tests and verify | `swift build`, manual testing | Pending |

## Technical Notes

### Phase 1: RefreshWorkflow Created

Created `RefreshWorkflow` at `Sources/features/DeployRemoteFeature/workflows/RefreshWorkflow.swift`:

- Conforms to `StreamingWorkflow` protocol from `Uniflow`
- Takes `CloudFormationClient` and `stackName` as dependencies
- Uses `Void` for `Options` since refresh needs no parameters
- Queries CloudFormation state via `cfClient.queryState()`
- For stable states (deployed, notDeployed, failed, credentialExpired): yields `.completed(snapshot)` immediately
- For in-progress operations (deploying, destroying): delegates to `ResumeMonitoringWorkflow`
- Build verified: `swift build` succeeds with no new warnings

## Dependencies

- `CloudFormationClient.queryState()` - Already exists
- `ResumeMonitoringWorkflow` - Already exists, will be composed
- `WorkflowState` enum - Already exists with `.deploying`, `.destroying`, `.completed` cases
- `DeploymentSnapshot.from(CloudFormationState)` - Already exists

## Testing Considerations

1. **Unit test RefreshWorkflow** with mock CloudFormationClient:
   - Test immediate completion for stable states (deployed, notDeployed, failed)
   - Test delegation to ResumeMonitoringWorkflow for in-progress operations
   - Test error handling (credential expired, network errors)

2. **Integration test** with real AWS:
   - Refresh when stack is deployed
   - Refresh when no stack exists
   - Refresh while deploy/destroy is in progress

3. **UI test** in MacApp:
   - Verify refresh button still works
   - Verify progress display during monitoring

## Success Criteria

1. `DeployRemoteModel.refresh()` no longer calls `cfClient` directly
2. All SDK client usage in model is via workflow consumption
3. Error handling moved to workflow layer
4. `resumeMonitoring()` method removed from model
5. `gitClient` removed from model
6. Existing functionality preserved (refresh works, monitoring works)
7. Build succeeds with no new warnings

## Architecture Alignment

After this change, `DeployRemoteModel` will fully align with the layered architecture:

```
DeployRemoteModel (App Layer)
├── deploy()           → DeployWorkflow
├── destroy()          → DestroyWorkflow
├── updateLambdaCode() → UpdateLambdaWorkflow
└── refresh()          → RefreshWorkflow  ← NEW (composes ResumeMonitoringWorkflow)

All operations use workflows. No direct SDK calls.
```
