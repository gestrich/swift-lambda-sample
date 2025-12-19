# DeployLinuxModel State Management Refactor

**Date:** 2025-12-19
**Status:** Proposed
**Related:** DeployRemoteModel state pattern, LinuxWorkflowState, LinuxSnapshot

## Objective

Refactor `DeployLinuxModel` to use a unified state machine pattern consistent with `DeployRemoteModel`, replacing scattered state properties and manual "mark" methods with workflow-driven state updates.

## Background / Motivation

`DeployLinuxModel` currently uses a fragmented state management approach:

1. **Multiple scattered state properties:**
   - `currentStatus: DeploymentStatus`
   - `isLoadingStatus: Bool`
   - `isTransitioning: Bool`
   - `buildState: BuildState`
   - `lambdaState: LambdaState`

2. **Manual "mark" method calls** that ignore workflow yields:
   ```swift
   buildState.startBuild()
   for try await _ in components.workflow.stream(options: options) {
       // Workflow progress is discarded!
   }
   buildState.markSuccess()
   ```

3. **Complex synchronization logic** in `refresh()` to keep state properties in sync.

In contrast, `DeployRemoteModel` uses a single `ModelState` enum that:
- Makes invalid states unrepresentable
- Derives all state from workflows (no manual marking)
- Has a single source of truth
- Preserves prior state during operations

**Good news:** The service-layer infrastructure already exists:
- `LinuxSnapshot` (parallel to `DeploymentSnapshot`) - `LinuxDeploymentState.swift:10-111`
- `LinuxWorkflowState` (parallel to `WorkflowState`) - `LinuxDeploymentState.swift:118-323`
- Workflows already yield `LinuxWorkflowState` and complete with `LinuxSnapshot`

The issue is that `DeployLinuxModel` ignores these yields and manually manages state instead.

## Technical Approach

### Pattern to Follow: DeployRemoteModel.ModelState

```swift
// From DeployRemoteModel.swift:241-359
public enum ModelState {
    case uninitialized
    case loading(prior: DeploymentSnapshot?)
    case ready(DeploymentSnapshot)
    case operating(WorkflowState, prior: DeploymentSnapshot?)

    public init(from workflowState: WorkflowState, prior: DeploymentSnapshot?) {
        if let snapshot = workflowState.completedSnapshot {
            self = .ready(snapshot)
        } else {
            self = .operating(workflowState, prior: prior)
        }
    }
}
```

### Current Pattern to Replace: DeployLinuxModel

```swift
// Current (problematic)
public func build(clean: Bool = false, output: CLIOutputStream? = nil) async throws {
    buildState.startBuild()  // Manual state mutation
    do {
        for try await _ in components.workflow.stream(options: options) {
            // Progress discarded!
        }
        buildState.markSuccess()  // Manual state mutation
    } catch {
        buildState.markFailed(exitCode: 1)
        throw error
    }
}
```

### Target Pattern

```swift
// Target (workflow-driven)
public func build(clean: Bool = false) async {
    guard state.canBuild else { return }
    let prior = state.snapshot

    let components = LinuxBuildWorkflow.create(workingDirectory: workingDirectory)
    let options = LinuxBuildWorkflow.Options(clean: clean)

    do {
        for try await workflowState in components.workflow.stream(options: options) {
            state = ModelState(from: workflowState, prior: prior)
        }
    } catch {
        state = ModelState(error: error, preserving: prior)
    }
}
```

## Implementation Phases

- [x] **Phase 1: Add LinuxModelState Enum** ✅ COMPLETED

Added a `ModelState` enum to `DeployLinuxModel` as an extension that mirrors `DeployRemoteModel.ModelState`.

**Implementation notes:**
- Added as `extension DeployLinuxModel { enum ModelState }` at end of file (lines 408-515)
- Uses `LinuxWorkflowState` and `LinuxSnapshot` from service layer
- Includes convenience initializers: `init(from:prior:)` and `init(error:preserving:)`
- Includes accessors: `snapshot`, `workflowState`, `isIdle`, `canStart`, `canStop`, `canBuild`, `operationStartTime`
- Build verified successful

```swift
public enum ModelState: Equatable {
    case uninitialized
    case loading(prior: LinuxSnapshot?)
    case ready(LinuxSnapshot)
    case operating(LinuxWorkflowState, prior: LinuxSnapshot?)

    // MARK: - Convenience Initializers

    public init(from workflowState: LinuxWorkflowState, prior: LinuxSnapshot?) {
        if let snapshot = workflowState.completedSnapshot {
            self = .ready(snapshot)
        } else {
            self = .operating(workflowState, prior: prior)
        }
    }

    public init(error: Error, preserving prior: LinuxSnapshot?) {
        self = .ready(.failed(reason: error.localizedDescription, preserving: prior))
    }

    // MARK: - Convenience Accessors

    public var snapshot: LinuxSnapshot? {
        switch self {
        case .uninitialized: return nil
        case .loading(let prior): return prior
        case .ready(let snapshot): return snapshot
        case .operating(_, let prior): return prior
        }
    }

    public var workflowState: LinuxWorkflowState? {
        guard case .operating(let state, _) = self else { return nil }
        return state
    }

    public var isIdle: Bool {
        switch self {
        case .uninitialized, .ready: return true
        case .loading, .operating: return false
        }
    }

    public var canStart: Bool {
        switch self {
        case .ready(let snapshot): return snapshot.canStart
        case .uninitialized: return true
        case .loading, .operating: return false
        }
    }

    public var canStop: Bool {
        switch self {
        case .ready(let snapshot): return snapshot.canStop
        case .uninitialized, .loading, .operating: return false
        }
    }

    public var canBuild: Bool {
        switch self {
        case .ready(let snapshot): return snapshot.canBuild
        case .uninitialized: return true
        case .loading, .operating: return false
        }
    }

    public var operationStartTime: Date? {
        workflowState?.startTime
    }
}
```

- [ ] **Phase 2: Replace Scattered State Properties**

**Remove:**
```swift
public private(set) var currentStatus: DeploymentStatus = .stopped
public private(set) var isLoadingStatus: Bool = false
private var isTransitioning = false
public var buildState = BuildState()
public var lambdaState = LambdaState()
```

**Add:**
```swift
public private(set) var state: ModelState = .uninitialized
```

- [ ] **Phase 3: Add Derived Properties**

Add computed properties for backward compatibility or convenience:

```swift
public var isIdle: Bool { state.isIdle }
public var canStart: Bool { state.canStart }
public var canStop: Bool { state.canStop }
public var canBuild: Bool { state.canBuild }
public var snapshot: LinuxSnapshot? { state.snapshot }
public var workflowState: LinuxWorkflowState? { state.workflowState }
public var operationStartTime: Date? { state.operationStartTime }

// For LocalService protocol compatibility
public var currentStatus: DeploymentStatus {
    state.snapshot?.serviceStatus ?? .stopped
}
```

- [ ] **Phase 4: Refactor Build Operation**

**Before:**
```swift
public func build(clean: Bool = false, output: CLIOutputStream? = nil) async throws {
    buildState.startBuild()
    do {
        let components = LinuxBuildWorkflow.create(workingDirectory: workingDirectory)
        let options = LinuxBuildWorkflow.Options(clean: clean)
        for try await _ in components.workflow.stream(options: options) {
            // Workflow progress is consumed; UI updates via buildState
        }
        buildState.markSuccess()
    } catch {
        buildState.markFailed(exitCode: 1)
        throw error
    }
}
```

**After:**
```swift
public func build(clean: Bool = false) async {
    guard state.canBuild else { return }
    let prior = state.snapshot

    let components = LinuxBuildWorkflow.create(workingDirectory: workingDirectory)
    let options = LinuxBuildWorkflow.Options(clean: clean)

    do {
        for try await workflowState in components.workflow.stream(options: options) {
            state = ModelState(from: workflowState, prior: prior)
        }
    } catch {
        state = ModelState(error: error, preserving: prior)
    }
}
```

- [ ] **Phase 5: Refactor Lambda Lifecycle Operations**

**startLambda:**
```swift
public func startLambda() async {
    guard state.isIdle else { return }
    let prior = state.snapshot

    let components = LinuxStartLambdaWorkflow.create(workingDirectory: workingDirectory)

    do {
        for try await workflowState in components.workflow.stream() {
            state = ModelState(from: workflowState, prior: prior)
        }
    } catch {
        state = ModelState(error: error, preserving: prior)
    }
}
```

**stopLambda:**
```swift
public func stopLambda() async {
    guard state.isIdle else { return }
    let prior = state.snapshot

    let components = LinuxStopLambdaWorkflow.create(workingDirectory: workingDirectory)

    do {
        for try await workflowState in components.workflow.stream() {
            state = ModelState(from: workflowState, prior: prior)
        }
    } catch {
        state = ModelState(error: error, preserving: prior)
    }
}
```

- [ ] **Phase 6: Refactor Start/Stop With Services**

**startWithServices:**
```swift
public func startWithServices() async {
    guard state.canStart else { return }
    let prior = state.snapshot

    let components = LinuxStartAllWorkflow.create(workingDirectory: workingDirectory)

    do {
        for try await workflowState in components.workflow.stream(options: ()) {
            state = ModelState(from: workflowState, prior: prior)
        }
    } catch {
        state = ModelState(error: error, preserving: prior)
    }
}
```

**stopWithServices:**
```swift
public func stopWithServices() async {
    guard state.canStop else { return }
    let prior = state.snapshot

    let components = LinuxStopAllWorkflow.create(workingDirectory: workingDirectory)

    do {
        for try await workflowState in components.workflow.stream() {
            state = ModelState(from: workflowState, prior: prior)
        }
    } catch {
        state = ModelState(error: error, preserving: prior)
    }
}
```

- [ ] **Phase 7: Refactor Service-Specific Operations**

Apply the same pattern to:
- [ ] `startAllServices()` / `stopAllServices()`
- [ ] `startS3()` / `stopS3()`
- [ ] `startDatabase()` / `stopDatabase()`
- [ ] `startDynamoDB()` / `stopDynamoDB()`

- [ ] **Phase 8: Simplify refresh()**

**Before:**
```swift
@discardableResult
public func refresh() async -> DeploymentStatus? {
    guard !isTransitioning else { return nil }
    isLoadingStatus = true
    defer { isLoadingStatus = false }

    do {
        let newStatus = try await self.status()
        currentStatus = newStatus

        // Sync lambdaState with actual running state (for app restart scenarios)
        if newStatus.lambdaState == .running && lambdaState.status == .stopped {
            lambdaState.setRunning()
        } else if newStatus.lambdaState == .stopped && lambdaState.status == .running {
            lambdaState.clear()
        }

        return newStatus
    } catch {
        currentStatus = .stopped
        return nil
    }
}
```

**After:**
```swift
public func refresh() async {
    guard state.isIdle else { return }

    let prior = state.snapshot
    state = .loading(prior: prior)

    let components = LinuxStatusWorkflow.create(workingDirectory: workingDirectory)

    do {
        for try await workflowState in components.workflow.stream() {
            state = ModelState(from: workflowState, prior: prior)
        }
    } catch {
        state = ModelState(error: error, preserving: prior)
    }
}
```

- [ ] **Phase 9: Simplify startIfNecessary()**

**After:**
```swift
public func startIfNecessary() async {
    guard state.isIdle else { return }

    // First refresh to get current status
    await refresh()

    // Check if any service needs starting
    guard let snapshot = state.snapshot else { return }

    if snapshot.canStart {
        await startWithServices()
    }
}
```

- [ ] **Phase 10: Update UI Consumers**

Update any SwiftUI views that consume `buildState` or `lambdaState` to use the new unified `state` property:

**Before:**
```swift
if model.buildState.status.isBuilding {
    ProgressView("Building...")
}
```

**After:**
```swift
if case .operating(let workflowState, _) = model.state,
   workflowState.isBuilding {
    ProgressView("Building...")
}
```

Or with a convenience accessor:
```swift
if model.state.workflowState?.isBuilding == true {
    ProgressView("Building...")
}
```

- [ ] **Phase 11: Clean Up Obsolete Types**

After refactoring:
- [ ] Review if `BuildState` and `LambdaState` are used elsewhere
- [ ] If not, remove them or mark as deprecated
- [ ] Remove the `refreshBuildStatus()` call from `init`

## Files to Modify

- [ ] `Sources/apps/MacApp/Models/DeployLinuxModel.swift` - Main refactoring - add ModelState, refactor all operations
- [ ] `Sources/apps/MacApp/Views/Linux/*` - Update views consuming buildState/lambdaState
- [ ] `Sources/services/LambdaBuildService/Models/BuildState.swift` - Potentially deprecate/remove
- [ ] `Sources/services/DeployCoreService/LambdaState.swift` - Potentially deprecate/remove

## Dependencies

- `LinuxWorkflowState` already exists in `DeployLinuxFeature`
- `LinuxSnapshot` already exists in `DeployLinuxFeature`
- All workflows already yield `LinuxWorkflowState`

## Testing Considerations

**Unit Tests:**
- [ ] Test `ModelState` enum state transitions
- [ ] Test derived properties (`isIdle`, `canStart`, `canStop`, `canBuild`)
- [ ] Test `init(from:prior:)` conversion

**Integration Tests:**
- [ ] Verify build workflow updates state correctly
- [ ] Verify start/stop workflows update state correctly
- [ ] Verify refresh correctly loads status

**Manual Testing:**
- [ ] Mac app Linux workflow displays correct status during operations
- [ ] Progress indicators show during builds
- [ ] Error states displayed correctly

## Success Criteria

- [ ] Single `state` property replaces all scattered state properties
- [ ] All operations consume workflow yields (no discarded progress)
- [ ] No manual "mark" method calls
- [ ] No complex sync logic in refresh()
- [ ] Consistent pattern with DeployRemoteModel
- [ ] All existing UI functionality preserved
- [ ] Invalid states are unrepresentable

## Rollback Plan

If issues arise:
1. The old pattern is preserved in git history
2. Can revert to scattered properties if needed
3. Workflows continue to work regardless of model pattern

## References

- `Sources/apps/MacApp/Models/DeployRemoteModel.swift` - Reference implementation
- `Sources/features/DeployRemoteFeature/services/Models/DeploymentState.swift` - WorkflowState pattern
- `Sources/features/DeployLinuxFeature/services/Models/LinuxDeploymentState.swift` - LinuxWorkflowState (already exists)
