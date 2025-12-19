# DeployXcodeModel State Management Refactor

**Date:** 2025-12-19
**Status:** PROPOSED
**Related:** DeployLinuxModel state refactor, DeployRemoteModel state pattern

## Objective

Refactor `DeployXcodeModel` to use a unified state machine pattern consistent with `DeployRemoteModel` and `DeployLinuxModel`, replacing scattered state properties and manual "mark" methods with workflow-driven state updates.

## Background / Motivation

`DeployXcodeModel` currently uses a fragmented state management approach identical to what `DeployLinuxModel` had before its refactor:

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
       // Workflow progress is consumed; UI updates via buildState
   }
   buildState.markSuccess()
   ```

3. **Complex synchronization logic** in `refresh()` to keep state properties in sync:
   ```swift
   if newStatus.lambdaState == .running && lambdaState.status == .stopped {
       lambdaState.setRunning()
   } else if newStatus.lambdaState == .stopped && lambdaState.status == .running {
       lambdaState.clear()
   }
   ```

4. **Workflows still use nested State types** instead of unified `XcodeWorkflowState`:
   ```swift
   // XcodeStatusWorkflow.State
   public struct State: Sendable {
       public let step: Step
       public let detail: Detail?
       // ...
   }
   ```

In contrast, `DeployRemoteModel` and now `DeployLinuxModel` use a single `ModelState` enum that:
- Makes invalid states unrepresentable
- Derives all state from workflows (no manual marking)
- Has a single source of truth
- Preserves prior state during operations

**Key difference from Linux refactor:** The service-layer infrastructure (`XcodeWorkflowState`, `XcodeSnapshot`) does NOT yet exist and must be created first.

## Technical Approach

### Pattern to Follow: DeployLinuxModel.ModelState

```swift
// From DeployLinuxModel after refactor
public enum ModelState: Equatable {
    case uninitialized
    case loading(prior: LinuxSnapshot?)
    case ready(LinuxSnapshot)
    case operating(LinuxWorkflowState, prior: LinuxSnapshot?)

    public init(from workflowState: LinuxWorkflowState, prior: LinuxSnapshot?) {
        if let snapshot = workflowState.completedSnapshot {
            self = .ready(snapshot)
        } else {
            self = .operating(workflowState, prior: prior)
        }
    }
}
```

### Current Pattern to Replace: DeployXcodeModel

```swift
// Current (problematic) - DeployXcodeModel.swift:155-168
public func build(clean: Bool = false, output: CLIOutputStream? = nil) async throws {
    buildState.startBuild()  // Manual state mutation

    do {
        let components = XcodeBuildWorkflow.create(workingDirectory: workingDirectory)
        let options = XcodeBuildWorkflow.Options(clean: clean)
        for try await _ in components.workflow.stream(options: options) {
            // Workflow progress is consumed; UI updates via buildState
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
    guard canBuild else { return }
    let prior = snapshot

    let components = XcodeBuildWorkflow.create(workingDirectory: workingDirectory)
    let options = XcodeBuildWorkflow.Options(clean: clean)

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

### Phase 1: Create XcodeDeploymentState Types

[x] **Create `XcodeSnapshot` and `XcodeWorkflowState`** *(Completed 2025-12-19)*

Created `Sources/features/DeployXcodeFeature/services/Models/XcodeDeploymentState.swift` following the pattern from `LinuxDeploymentState.swift`.

**Tasks:**
- [x] 1.1: Create `DeployXcodeFeature/services/Models/` directory structure
- [x] 1.2: Define `XcodeSnapshot` struct (parallel to `LinuxSnapshot`)
- [x] 1.3: Define `XcodeWorkflowState` enum (parallel to `LinuxWorkflowState`)
- [x] 1.4: Define progress types (`BuildProgress`, `ServicesProgress`, `LambdaProgress`, `StatusProgress`, `TestProgress`)
- [x] 1.5: Build verification

**Technical Notes:**
- Unlike `LinuxWorkflowState`, `XcodeWorkflowState` does not need `NetworkProgress` since Xcode uses native macOS processes rather than Docker containers with networking setup.
- `LambdaProgress.Step` includes `.checkingBuild` and `.building` steps since `XcodeStartLambdaWorkflow` can trigger a build if needed.
- `ServicesProgress.Step` includes `.creatingBucket` for MinIO bucket creation during service start.

**XcodeSnapshot structure:**
```swift
public struct XcodeSnapshot: Sendable, Equatable {
    public let serviceStatus: DeploymentStatus
    public let buildStatus: BuildStatus

    // Convenience accessors
    public var lambdaState: ServiceState
    public var s3State: ServiceState
    public var postgresState: ServiceState
    public var dynamodbState: ServiceState
    public var canStart: Bool
    public var canStop: Bool
    public var canBuild: Bool

    public enum BuildStatus: Sendable, Equatable {
        case notBuilt
        case building
        case available
        case failed(reason: String)
    }
}
```

**XcodeWorkflowState structure:**
```swift
public enum XcodeWorkflowState: Sendable, Equatable {
    case building(BuildProgress)
    case startingServices(ServicesProgress)
    case stoppingServices(ServicesProgress)
    case startingLambda(LambdaProgress)
    case stoppingLambda(LambdaProgress)
    case checkingStatus(StatusProgress)
    case testing(TestProgress)
    case completed(XcodeSnapshot)

    public var completedSnapshot: XcodeSnapshot?
    public var startTime: Date?
    public var isBuilding: Bool
    public var isStarting: Bool
    public var isStopping: Bool
}
```

---

### Phase 2: Update XcodeStatusWorkflow to Yield XcodeWorkflowState

[ ] **Migrate XcodeStatusWorkflow**

**Tasks:**
- [ ] 2.1: Update `XcodeStatusWorkflow.State` to be `XcodeWorkflowState`
- [ ] 2.2: Update `stream()` to yield `XcodeWorkflowState.checkingStatus(...)` during progress
- [ ] 2.3: Update `stream()` to yield `XcodeWorkflowState.completed(XcodeSnapshot)` on completion
- [ ] 2.4: Update CLI progress printer if needed
- [ ] 2.5: Update `DeployXcodeModel.status()` to handle new state type
- [ ] 2.6: Build verification

---

### Phase 3: Update XcodeBuildWorkflow to Yield XcodeWorkflowState

[ ] **Migrate XcodeBuildWorkflow**

**Tasks:**
- [ ] 3.1: Update `XcodeBuildWorkflow.State` to be `XcodeWorkflowState`
- [ ] 3.2: Update `stream()` to yield `XcodeWorkflowState.building(...)` during progress
- [ ] 3.3: Update `stream()` to yield `XcodeWorkflowState.completed(XcodeSnapshot)` on completion
- [ ] 3.4: Update CLI progress printer if needed
- [ ] 3.5: Build verification

---

### Phase 4: Update XcodeStartAllWorkflow to Yield XcodeWorkflowState

[ ] **Migrate XcodeStartAllWorkflow**

**Tasks:**
- [ ] 4.1: Update `XcodeStartAllWorkflow.State` to be `XcodeWorkflowState`
- [ ] 4.2: Update `stream()` to yield appropriate states during progress
- [ ] 4.3: Update CLI progress printer if needed
- [ ] 4.4: Build verification

---

### Phase 5: Update XcodeStopAllWorkflow to Yield XcodeWorkflowState

[ ] **Migrate XcodeStopAllWorkflow**

**Tasks:**
- [ ] 5.1: Update `XcodeStopAllWorkflow.State` to be `XcodeWorkflowState`
- [ ] 5.2: Update `stream()` to yield appropriate states
- [ ] 5.3: Update CLI progress printer if needed
- [ ] 5.4: Build verification

---

### Phase 6: Update Remaining Workflows

[ ] **Migrate remaining Xcode workflows**

**Tasks:**
- [ ] 6.1: Update `XcodeStartLambdaWorkflow` to yield `XcodeWorkflowState`
- [ ] 6.2: Update `XcodeStopLambdaWorkflow` to yield `XcodeWorkflowState`
- [ ] 6.3: Update `XcodeStartServicesWorkflow` to yield `XcodeWorkflowState`
- [ ] 6.4: Update `XcodeStopServicesWorkflow` to yield `XcodeWorkflowState`
- [ ] 6.5: Update `XcodeTestWorkflow` to yield `XcodeWorkflowState`
- [ ] 6.6: Update all related CLI commands/progress printers
- [ ] 6.7: Build verification

---

### Phase 7: Add XcodeModelState Enum

[ ] **Add `ModelState` enum to `DeployXcodeModel`**

Add as an extension at the end of the file, mirroring `DeployLinuxModel.ModelState`.

**Tasks:**
- [ ] 7.1: Add `extension DeployXcodeModel { enum ModelState }` with all cases
- [ ] 7.2: Add convenience initializers: `init(from:prior:)` and `init(error:preserving:)`
- [ ] 7.3: Add accessors: `snapshot`, `workflowState`, `isIdle`, `canStart`, `canStop`, `canBuild`, `operationStartTime`
- [ ] 7.4: Build verification

```swift
public enum ModelState: Equatable {
    case uninitialized
    case loading(prior: XcodeSnapshot?)
    case ready(XcodeSnapshot)
    case operating(XcodeWorkflowState, prior: XcodeSnapshot?)

    public init(from workflowState: XcodeWorkflowState, prior: XcodeSnapshot?) {
        if let snapshot = workflowState.completedSnapshot {
            self = .ready(snapshot)
        } else {
            self = .operating(workflowState, prior: prior)
        }
    }

    public init(error: Error, preserving prior: XcodeSnapshot?) {
        self = .ready(.failed(reason: error.localizedDescription, preserving: prior))
    }
}
```

---

### Phase 8: Replace Scattered State Properties

[ ] **Replace scattered state properties with unified `state: ModelState`**

**Tasks:**
- [ ] 8.1: Add `public private(set) var state: ModelState = .uninitialized` as single source of truth
- [ ] 8.2: Add computed `currentStatus` property for `LambdaService` protocol compatibility
- [ ] 8.3: Add computed `isLoadingStatus` property derived from state
- [ ] 8.4: Add private computed `isTransitioning` property (temporary, for migration)
- [ ] 8.5: Remove `refreshBuildStatus()` call from `init`
- [ ] 8.6: Build verification

**Changes:**
```swift
// Remove stored properties:
// - currentStatus: DeploymentStatus
// - isLoadingStatus: Bool
// - isTransitioning: Bool

// Add unified state:
public private(set) var state: ModelState = .uninitialized

// Add derived properties for compatibility:
public var currentStatus: DeploymentStatus {
    state.snapshot?.serviceStatus ?? .stopped
}

public var isLoadingStatus: Bool {
    if case .loading = state { return true }
    return false
}
```

---

### Phase 9: Add Derived Properties

[ ] **Add computed convenience properties on `DeployXcodeModel`**

**Tasks:**
- [ ] 9.1: Add `isIdle`, `canStart`, `canStop`, `canBuild` delegating to `state`
- [ ] 9.2: Add `snapshot`, `workflowState`, `operationStartTime` delegating to `state`
- [ ] 9.3: Build verification

```swift
// MARK: - Derived Properties (Convenience Accessors)

public var isIdle: Bool { state.isIdle }
public var canStart: Bool { state.canStart }
public var canStop: Bool { state.canStop }
public var canBuild: Bool { state.canBuild }
public var snapshot: XcodeSnapshot? { state.snapshot }
public var workflowState: XcodeWorkflowState? { state.workflowState }
public var operationStartTime: Date? { state.operationStartTime }
```

---

### Phase 10: Refactor Build Operation

[ ] **Refactor `build()` to use workflow-driven state**

**Tasks:**
- [ ] 10.1: Replace `buildState.startBuild()`, `markSuccess()`, `markFailed()` with `ModelState` updates
- [ ] 10.2: Add `guard canBuild else { return }` guard
- [ ] 10.3: Capture `prior = snapshot` before workflow
- [ ] 10.4: Iterate workflow yields and update state
- [ ] 10.5: On error: update state and rethrow
- [ ] 10.6: Build verification

```swift
public func build(clean: Bool = false, output: CLIOutputStream? = nil) async throws {
    guard canBuild else { return }
    let prior = snapshot

    let components = XcodeBuildWorkflow.create(workingDirectory: workingDirectory)
    let options = XcodeBuildWorkflow.Options(clean: clean)

    do {
        for try await workflowState in components.workflow.stream(options: options) {
            state = ModelState(from: workflowState, prior: prior)
        }
    } catch {
        state = ModelState(error: error, preserving: prior)
        throw error
    }
}
```

---

### Phase 11: Refactor Lambda Lifecycle Operations

[ ] **Refactor `startLambda()` and `stopLambda()`**

**Tasks:**
- [ ] 11.1: Replace manual `lambdaState` marking with `ModelState` updates
- [ ] 11.2: Add `guard isIdle else { return }` guards
- [ ] 11.3: Capture `prior = snapshot` before workflow
- [ ] 11.4: Iterate workflow yields and update state
- [ ] 11.5: Build verification

---

### Phase 12: Refactor Start/Stop With Services

[ ] **Refactor `startWithServices()` and `stopWithServices()`**

**Tasks:**
- [ ] 12.1: Replace manual state marking with `ModelState` updates
- [ ] 12.2: Add `guard canStart/canStop else { return }` guards
- [ ] 12.3: Remove `isTransitioning` flag usage
- [ ] 12.4: Remove `await refresh()` call at end (state already updated by workflow)
- [ ] 12.5: Build verification

---

### Phase 13: Refactor Service-Specific Operations

[ ] **Refactor all service-specific operations**

**Tasks:**
- [ ] 13.1: Add `guard isIdle else { return }` to all service operations
- [ ] 13.2: Capture `prior = snapshot` before workflow
- [ ] 13.3: Iterate workflow yields and update state
- [ ] 13.4: Methods to refactor:
  - `startAllServices()`
  - `stopAllServices()`
  - `startS3()` / `stopS3()`
  - `startDatabase()` / `stopDatabase()`
  - `startDynamoDB()` / `stopDynamoDB()`
- [ ] 13.5: Build verification

---

### Phase 14: Simplify refresh()

[ ] **Remove obsolete synchronization logic from `refresh()`**

**Tasks:**
- [ ] 14.1: Remove manual `lambdaState.setRunning()` and `lambdaState.clear()` calls
- [ ] 14.2: Use workflow-driven state updates only
- [ ] 14.3: Use `guard isIdle else { return nil }` pattern
- [ ] 14.4: Build verification

```swift
@discardableResult
public func refresh() async -> DeploymentStatus? {
    guard isIdle else { return nil }

    let prior = snapshot
    state = .loading(prior: prior)

    let components = XcodeStatusWorkflow.create()

    do {
        for try await workflowState in components.workflow.stream() {
            state = ModelState(from: workflowState, prior: prior)
        }
        return state.snapshot?.serviceStatus
    } catch {
        state = ModelState(error: error, preserving: prior)
        return nil
    }
}
```

---

### Phase 15: Simplify startIfNecessary()

[ ] **Simplify `startIfNecessary()` to use workflow-driven state**

**Tasks:**
- [ ] 15.1: Remove debug print statements
- [ ] 15.2: Simplify guard to use `isIdle` and `snapshot.canStart`
- [ ] 15.3: Remove manual `isTransitioning` flag management
- [ ] 15.4: Build verification

```swift
public func startIfNecessary() async {
    guard isIdle else { return }

    await refresh()

    guard let snapshot = snapshot, snapshot.canStart else { return }

    try? await startWithServices()
}
```

---

### Phase 16: Make buildState/lambdaState Derived

[ ] **Make `buildState` and `lambdaState` computed properties**

**Tasks:**
- [ ] 16.1: Change `buildState` to computed property deriving from `state`
- [ ] 16.2: Change `lambdaState` to computed property deriving from `state`
- [ ] 16.3: Add no-op setters for protocol conformance
- [ ] 16.4: Update `deleteBuild()` to reset state via state machine
- [ ] 16.5: Remove obsolete `isTransitioning` property
- [ ] 16.6: Build verification

```swift
public var buildState: BuildState {
    get {
        if let workflowState = state.workflowState, workflowState.isBuilding {
            return BuildState(status: .building)
        }
        if let snapshot = state.snapshot {
            switch snapshot.buildStatus {
            case .notBuilt: return BuildState(status: .notBuilt)
            case .building: return BuildState(status: .building)
            case .available: return BuildState(status: .available)
            case .failed: return BuildState(status: .failed(1))
            }
        }
        return BuildState(status: .notBuilt)
    }
    set { /* Protocol requirement - mutations ignored */ }
}
```

---

### Phase 17: Final Cleanup

[ ] **Clean up and verify**

**Tasks:**
- [ ] 17.1: Remove any unused imports
- [ ] 17.2: Verify all UI consumers work (LocalServiceView, LocalServicesModel)
- [ ] 17.3: Run all tests
- [ ] 17.4: Update this document status to COMPLETED
- [ ] 17.5: Move document to `docs/completed/`

---

## Files Modified

**New files:**
- [x] `Sources/features/DeployXcodeFeature/services/Models/XcodeDeploymentState.swift`

**Modified files:**
- [ ] `Sources/features/DeployXcodeFeature/workflows/XcodeStatusWorkflow.swift`
- [ ] `Sources/features/DeployXcodeFeature/workflows/XcodeBuildWorkflow.swift`
- [ ] `Sources/features/DeployXcodeFeature/workflows/XcodeStartAllWorkflow.swift`
- [ ] `Sources/features/DeployXcodeFeature/workflows/XcodeStopAllWorkflow.swift`
- [ ] `Sources/features/DeployXcodeFeature/workflows/XcodeStartLambdaWorkflow.swift`
- [ ] `Sources/features/DeployXcodeFeature/workflows/XcodeStopLambdaWorkflow.swift`
- [ ] `Sources/features/DeployXcodeFeature/workflows/XcodeStartServicesWorkflow.swift`
- [ ] `Sources/features/DeployXcodeFeature/workflows/XcodeStopServicesWorkflow.swift`
- [ ] `Sources/features/DeployXcodeFeature/workflows/XcodeTestWorkflow.swift`
- [ ] `Sources/apps/MacApp/Models/DeployXcodeModel.swift`
- [ ] `Sources/apps/CLIApp/Commands/DeployXcode/DeployXcodeProgressPrinters.swift` (if exists)

**No changes needed:**
- Views (`LocalServiceView`, `DockerServicesView`) - already updated for `DeployLinuxModel` refactor
- `LocalServicesModel` - delegates to underlying service
- `LambdaService` protocol - already updated (no Combine)

---

## Dependencies

- `DeploymentStatus` from `DeployCoreService` (existing)
- `ServiceState` from `DeployCoreService` (existing)
- `LocalServiceType` from `DeployLocalService` (existing)
- `BuildState` and `LambdaState` remain for protocol compatibility

---

## Testing Considerations

**Unit Tests:**
- [ ] Test `XcodeSnapshot` convenience accessors
- [ ] Test `XcodeWorkflowState` completion detection
- [ ] Test `ModelState` enum state transitions
- [ ] Test derived properties (`isIdle`, `canStart`, `canStop`, `canBuild`)

**Integration Tests:**
- [ ] Verify build workflow updates state correctly
- [ ] Verify start/stop workflows update state correctly
- [ ] Verify refresh correctly loads status

**Manual Testing:**
- [ ] Mac app Xcode workflow displays correct status during operations
- [ ] Progress indicators show during builds
- [ ] Error states displayed correctly
- [ ] Start/stop buttons enable/disable appropriately

---

## Success Criteria

- [ ] Single `state` property replaces all scattered state properties
- [ ] All operations consume workflow yields (no discarded progress)
- [ ] No manual "mark" method calls in DeployXcodeModel
- [ ] No complex sync logic in refresh()
- [ ] Consistent pattern with DeployRemoteModel and DeployLinuxModel
- [ ] All existing UI functionality preserved (via derived `buildState`/`lambdaState` properties)
- [ ] Invalid states are unrepresentable (ModelState enum design)
- [ ] All workflows yield `XcodeWorkflowState`

---

## Rollback Plan

If issues arise:
1. The old pattern is preserved in git history
2. Can revert to scattered properties if needed
3. Workflows continue to work regardless of model pattern

---

## References

- `Sources/apps/MacApp/Models/DeployRemoteModel.swift` - Reference implementation
- `Sources/apps/MacApp/Models/DeployLinuxModel.swift` - Recently refactored (same pattern)
- `Sources/features/DeployLinuxFeature/services/Models/LinuxDeploymentState.swift` - LinuxWorkflowState pattern to follow
- `docs/completed/deploy-linux-model-state-refactor.md` - Phase-by-phase reference
- `docs/completed/deploy-linux-model-observable-refactor.md` - Workflow migration reference
