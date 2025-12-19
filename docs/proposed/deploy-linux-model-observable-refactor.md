# DeployLinuxModel Observable Refactor

**Status:** Proposed
**Created:** 2025-12-18
**Related:** [layered-architecture.md](../architecture/layered-architecture.md), [linux-service-to-workflow-migration.md](linux-service-to-workflow-migration.md)

## Problem Statement

`DeployLinuxModel` uses outdated patterns that don't align with project best practices established in `DeployRemoteModel`:

### Current Issues

1. **Combine subjects instead of @Observable**: Uses `CurrentValueSubject<DeploymentStatus, Never>` and `CurrentValueSubject<Bool, Never>` instead of the modern `@Observable` macro
2. **Multiple disconnected state properties**: Separate `statusSubject`, `isLoadingStatusSubject`, `buildState`, `lambdaState` instead of a unified state enum
3. **Manual transition flags**: Uses `isTransitioning` boolean to coordinate state
4. **Workflow state not consumed properly**: Workflows are consumed but their state isn't mapped to model state - the model manually calls `lambdaState.markRunning()` instead of letting workflow state drive the model
5. **Protocol constraints**: `LambdaService` protocol requires Combine publishers (`statusPublisher`, `isLoadingStatusPublisher`)

### Reference: DeployRemoteModel Pattern

`DeployRemoteModel` demonstrates the correct pattern:

```swift
@MainActor @Observable
public class DeployRemoteModel {
    public private(set) var state: ModelState = .uninitialized

    public func refresh() async {
        let prior = state.snapshot
        state = .loading(prior: prior)

        let workflow = RefreshWorkflow(...)
        do {
            for try await workflowState in workflow.stream(options: ()) {
                state = ModelState(from: workflowState, prior: prior)
            }
        } catch {
            state = ModelState(error: error, preserving: prior)
        }
    }

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
}
```

Key patterns:
- Single `state: ModelState` enum as source of truth
- `ModelState.init(from:prior:)` for direct assignment from workflow state
- Clean consumption: `state = ModelState(from: workflowState, prior: prior)`
- No Combine, no manual flags

---

## Goals

1. **Replace Combine with @Observable**: Remove `CurrentValueSubject` and publishers
2. **Unified state enum**: Single `state: ModelState` instead of multiple properties
3. **Workflow-driven state**: Consume workflow streams and map state directly
4. **Update protocols**: Remove Combine requirements from `LambdaService`
5. **Consistency**: Align `DeployXcodeModel` with same patterns (they're nearly identical)

---

## Scope

### In Scope
- `DeployLinuxModel` refactor to `@Observable` with unified state
- `DeployXcodeModel` refactor (same patterns)
- `LambdaService` protocol update (remove Combine requirements)
- `LocalService` protocol update if needed
- Views consuming `statusPublisher`/`isLoadingStatusPublisher`

### Out of Scope
- Workflow changes (already migrated in linux-service-to-workflow-migration.md)
- CLI command changes
- New functionality

---

## Technical Approach

### 1. Create LinuxWorkflowState and LinuxSnapshot Types

Following `DeployRemoteFeature/services/Models/DeploymentState.swift` pattern:

```swift
// In DeployLinuxFeature/services/Models/LinuxDeploymentState.swift

/// Stable state when not operating (similar to DeploymentSnapshot)
public struct LinuxSnapshot: Sendable, Equatable {
    public let serviceStatus: DeploymentStatus
    public let buildStatus: BuildStatus
    public let lambdaStatus: LambdaStatus

    // Convenience accessors
    public var isAllRunning: Bool { ... }
    public var canStart: Bool { ... }
    public var canStop: Bool { ... }
}

/// State yielded by Linux workflows (similar to WorkflowState)
public enum LinuxWorkflowState: Sendable, Equatable {
    case building(BuildProgress)
    case startingServices(ServicesProgress)
    case stoppingServices(ServicesProgress)
    case startingLambda(LambdaProgress)
    case stoppingLambda(LambdaProgress)
    case checkingStatus(StatusProgress)
    case completed(LinuxSnapshot)

    public var completedSnapshot: LinuxSnapshot? {
        if case .completed(let snapshot) = self { return snapshot }
        return nil
    }

    public var startTime: Date? { ... }
}
```

### 2. Update LambdaService Protocol

Remove Combine requirements:

```swift
// Current (problematic)
@MainActor
public protocol LambdaService {
    var statusPublisher: AnyPublisher<DeploymentStatus, Never> { get }
    var isLoadingStatusPublisher: AnyPublisher<Bool, Never> { get }
    func refreshStatus()
}

// Target (no Combine)
@MainActor
public protocol LambdaService {
    /// Get current status asynchronously
    func status() async throws -> DeploymentStatus

    /// Refresh and return updated status
    @discardableResult
    func refresh() async -> DeploymentStatus?
}
```

### 3. Refactor DeployLinuxModel

```swift
@MainActor @Observable
public class DeployLinuxModel: LocalService {
    // Single source of truth
    public private(set) var state: ModelState = .uninitialized

    // Configuration (immutable)
    public let cliClient: CLIClient
    private let workingDirectory: String
    // ... other SDK clients

    public init(workingDirectory: String) {
        self.workingDirectory = workingDirectory
        self.cliClient = CLIClient(defaultWorkingDirectory: workingDirectory)
        // ... initialize clients
    }

    // MARK: - Refresh

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

    // MARK: - Build

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

    // MARK: - Start/Stop

    public func startWithServices() async {
        guard state.canStart else { return }

        let prior = state.snapshot
        let components = LinuxStartAllWorkflow.create(workingDirectory: workingDirectory)

        do {
            for try await workflowState in components.workflow.stream() {
                state = ModelState(from: workflowState, prior: prior)
            }
        } catch {
            state = ModelState(error: error, preserving: prior)
        }
    }

    // ... similar for stopWithServices, startLambda, stopLambda, etc.

    // MARK: - Nested Types

    public enum ModelState {
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

        public init(error: Error, preserving prior: LinuxSnapshot?) {
            self = .ready(LinuxSnapshot.failed(reason: error.localizedDescription, preserving: prior))
        }

        // Convenience accessors
        public var snapshot: LinuxSnapshot? { ... }
        public var isIdle: Bool { ... }
        public var canBuild: Bool { ... }
        public var canStart: Bool { ... }
        public var canStop: Bool { ... }
    }
}
```

### 4. Update Workflows to Yield LinuxWorkflowState

Each workflow needs to yield `LinuxWorkflowState` instead of its own `State` type. Example for `LinuxStartAllWorkflow`:

```swift
public struct LinuxStartAllWorkflow: StreamingWorkflow {
    public typealias State = LinuxWorkflowState
    public typealias Result = State

    public func stream(options: Void) -> AsyncThrowingStream<State, Error> {
        AsyncThrowingStream { continuation in
            Task {
                let startTime = Date()

                // Start services
                continuation.yield(.startingServices(ServicesProgress(step: .starting, startTime: startTime)))
                // ... service start logic

                // Start Lambda
                continuation.yield(.startingLambda(LambdaProgress(step: .starting, startTime: startTime)))
                // ... lambda start logic

                // Complete with snapshot
                let snapshot = LinuxSnapshot(
                    serviceStatus: currentStatus,
                    buildStatus: .available,
                    lambdaStatus: .running
                )
                continuation.yield(.completed(snapshot))
                continuation.finish()
            }
        }
    }
}
```

---

## Migration Phases

### Phase 1: Create LinuxDeploymentState Types ✅ COMPLETED

**Tasks:**
- [x] 1.1: Create `DeployLinuxFeature/services/Models/LinuxDeploymentState.swift`
- [x] 1.2: Define `LinuxSnapshot` struct (parallel to `DeploymentSnapshot`)
- [x] 1.3: Define `LinuxWorkflowState` enum (parallel to `WorkflowState`)
- [x] 1.4: Define progress types (`BuildProgress`, `ServicesProgress`, `LambdaProgress`, `StatusProgress`, `TestProgress`)
- [x] 1.5: Build verification

**Files created:**
- `Sources/features/DeployLinuxFeature/services/Models/LinuxDeploymentState.swift`

**Technical Notes:**
- Added `Equatable` conformance to `DeploymentStatus` in `DeployCoreService/LambdaService.swift` to enable `LinuxSnapshot` Equatable synthesis
- `LinuxSnapshot.BuildStatus` is a nested enum (not using external `BuildState` from `LambdaBuildService`) to keep the state self-contained
- Added `TestProgress` for the test workflow in addition to the spec'd progress types
- `LinuxSnapshot` uses `DeploymentStatus` from `DeployCoreService` for service states (reusing existing type rather than duplicating)

---

### Phase 2: Update LinuxStatusWorkflow to Yield LinuxWorkflowState ✅ COMPLETED

**Tasks:**
- [x] 2.1: Update `LinuxStatusWorkflow.State` to be `LinuxWorkflowState`
- [x] 2.2: Update `stream()` to yield `LinuxWorkflowState.checkingStatus(...)` during progress
- [x] 2.3: Update `stream()` to yield `LinuxWorkflowState.completed(LinuxSnapshot)` on completion
- [x] 2.4: Update CLI command to handle new state type
- [x] 2.5: Build verification

**Files modified:**
- `Sources/features/DeployLinuxFeature/workflows/LinuxStatusWorkflow.swift`
- `Sources/apps/CLIApp/Commands/DeployLinux/DeployLinuxProgressPrinters.swift`
- `Sources/apps/MacApp/Models/DeployLinuxModel.swift`

**Technical Notes:**
- Removed the nested `State` struct and `Detail` enum from `LinuxStatusWorkflow`, now uses `LinuxWorkflowState` directly
- Workflow yields `LinuxWorkflowState.checkingStatus(StatusProgress)` during each check step
- Workflow yields `LinuxWorkflowState.completed(LinuxSnapshot)` on completion with the full snapshot
- CLI progress printer updated to switch on `LinuxWorkflowState` enum cases instead of old step/detail pattern
- `DeployLinuxModel.status()` updated to extract `serviceStatus` from completed snapshot instead of using old detail pattern

---

### Phase 3: Update LinuxBuildWorkflow to Yield LinuxWorkflowState ✅ COMPLETED

**Tasks:**
- [x] 3.1: Update `LinuxBuildWorkflow.State` to be `LinuxWorkflowState`
- [x] 3.2: Update `stream()` to yield `LinuxWorkflowState.building(...)` during progress
- [x] 3.3: Update `stream()` to yield `LinuxWorkflowState.completed(LinuxSnapshot)` on completion
- [x] 3.4: Update CLI command to handle new state type
- [x] 3.5: Build verification

**Files modified:**
- `Sources/features/DeployLinuxFeature/workflows/LinuxBuildWorkflow.swift`
- `Sources/apps/CLIApp/Commands/DeployLinux/DeployLinuxProgressPrinters.swift`
- `Sources/features/DeployLinuxFeature/workflows/LinuxStartLambdaWorkflow.swift` (downstream fix)

**Technical Notes:**
- Changed `LinuxBuildWorkflow.State` from a nested struct with `Step`/`Detail` enums to `typealias State = LinuxWorkflowState`
- Workflow now yields `.building(BuildProgress)` states with `startTime` and optional `output` for build output
- On completion, yields `.completed(LinuxSnapshot)` with `serviceStatus: .stopped` and `buildStatus: .available`
- CLI progress printer now switches on `LinuxWorkflowState` enum cases
- Fixed downstream consumer `LinuxStartLambdaWorkflow.buildLambda()` to extract output from `LinuxWorkflowState.building` case

---

### Phase 4: Update LinuxStartAllWorkflow to Yield LinuxWorkflowState ✅ COMPLETED

**Tasks:**
- [x] 4.1: Update `LinuxStartAllWorkflow.State` to be `LinuxWorkflowState`
- [x] 4.2: Update `stream()` to yield appropriate states during progress
- [x] 4.3: Update CLI progress printer
- [x] 4.4: Build verification

**Files modified:**
- `Sources/features/DeployLinuxFeature/services/Models/LinuxDeploymentState.swift`
- `Sources/features/DeployLinuxFeature/workflows/LinuxStartAllWorkflow.swift`
- `Sources/apps/CLIApp/Commands/DeployLinux/DeployLinuxProgressPrinters.swift`

**Technical Notes:**
- Added `settingUpNetwork(NetworkProgress)` case to `LinuxWorkflowState` for the Docker network setup phase
- Added `NetworkProgress` struct with `creatingNetwork` and `connectingContainers` steps plus optional `message`
- Changed `LinuxStartAllWorkflow.State` from nested struct to `typealias State = LinuxWorkflowState`
- Workflow now yields:
  - `.startingServices(ServicesProgress)` - with `currentService` indicating which service is starting
  - `.settingUpNetwork(NetworkProgress)` - with optional message for network setup details
  - `.startingLambda(LambdaProgress)` - with step indicating starting/waitingForReady
  - `.completed(LinuxSnapshot)` - with all services marked as running
- Added mapping helper methods to convert sub-workflow states to `LinuxWorkflowState` progress types
- CLI progress printer updated to switch on `LinuxWorkflowState` enum cases
- Sub-workflows (`LinuxStartServicesWorkflow`, `LinuxSetupNetworkWorkflow`, `LinuxStartLambdaWorkflow`) still use their own internal `State` types - consumed and mapped in `LinuxStartAllWorkflow`

---

### Phase 5: Update LinuxStopAllWorkflow to Yield LinuxWorkflowState ✅ COMPLETED

**Tasks:**
- [x] 5.1: Update `LinuxStopAllWorkflow.State` to be `LinuxWorkflowState`
- [x] 5.2: Update `stream()` to yield appropriate states
- [x] 5.3: Update CLI progress printer
- [x] 5.4: Build verification

**Files modified:**
- `Sources/features/DeployLinuxFeature/workflows/LinuxStopAllWorkflow.swift`
- `Sources/apps/CLIApp/Commands/DeployLinux/DeployLinuxProgressPrinters.swift`

**Technical Notes:**
- Changed `LinuxStopAllWorkflow.State` from nested struct to `typealias State = LinuxWorkflowState`
- Added imports for `DeployCoreService` and `DeployLocalService` to access `DeploymentStatus` and `LocalServiceType`
- Workflow now yields:
  - `.stoppingLambda(LambdaProgress)` - with step `.stopping`
  - `.stoppingServices(ServicesProgress)` - with `currentService` indicating which service is stopping
  - `.completed(LinuxSnapshot)` - with all services marked as stopped
- Added mapping helper methods to convert sub-workflow states to `LinuxWorkflowState` progress types
- CLI progress printer updated to switch on `LinuxWorkflowState` enum cases
- Sub-workflows (`LinuxStopLambdaWorkflow`, `LinuxStopServicesWorkflow`) still use their own internal `State` types - consumed and mapped in `LinuxStopAllWorkflow`

---

### Phase 6: Update Remaining Workflows (LinuxStartLambda, LinuxStopLambda, etc.) ✅ COMPLETED

**Tasks:**
- [x] 6.1: Update `LinuxStartLambdaWorkflow` to yield `LinuxWorkflowState`
- [x] 6.2: Update `LinuxStopLambdaWorkflow` to yield `LinuxWorkflowState`
- [x] 6.3: Update `LinuxStartServicesWorkflow` to yield `LinuxWorkflowState`
- [x] 6.4: Update `LinuxStopServicesWorkflow` to yield `LinuxWorkflowState`
- [x] 6.5: Update `LinuxTestWorkflow` to yield `LinuxWorkflowState`
- [x] 6.6: Update all related CLI commands
- [x] 6.7: Build verification

**Files modified:**
- `Sources/features/DeployLinuxFeature/workflows/LinuxStartLambdaWorkflow.swift`
- `Sources/features/DeployLinuxFeature/workflows/LinuxStopLambdaWorkflow.swift`
- `Sources/features/DeployLinuxFeature/workflows/LinuxStartServicesWorkflow.swift`
- `Sources/features/DeployLinuxFeature/workflows/LinuxStopServicesWorkflow.swift`
- `Sources/features/DeployLinuxFeature/workflows/LinuxTestWorkflow.swift`
- `Sources/features/DeployLinuxFeature/workflows/LinuxStartAllWorkflow.swift` (updated to handle new sub-workflow state types)
- `Sources/features/DeployLinuxFeature/workflows/LinuxStopAllWorkflow.swift` (updated to handle new sub-workflow state types)
- `Sources/features/DeployLinuxFeature/services/Models/LinuxDeploymentState.swift` (enhanced `TestProgress` with detailed step enum)
- `Sources/apps/CLIApp/Commands/DeployLinux/DeployLinuxProgressPrinters.swift`

**Technical Notes:**
- All five remaining workflows now yield `LinuxWorkflowState` directly via `typealias State = LinuxWorkflowState`
- Removed nested `State` struct with `Step`/`Detail` enums from each workflow
- Each workflow yields appropriate `LinuxWorkflowState` cases:
  - `LinuxStartLambdaWorkflow`: `.building(...)`, `.startingLambda(...)`, `.completed(...)`
  - `LinuxStopLambdaWorkflow`: `.stoppingLambda(...)`, `.completed(...)`
  - `LinuxStartServicesWorkflow`: `.startingServices(...)`, `.completed(...)`
  - `LinuxStopServicesWorkflow`: `.stoppingServices(...)`, `.completed(...)`
  - `LinuxTestWorkflow`: `.testing(...)`, `.completed(...)`
- Enhanced `TestProgress` struct with detailed step enum (`checkingLambda`, `testingFileUpload`, `testingFileList`, `testingFileDownload`, `testingDatabaseInit`) and result enum (`passed`, `failed`, `message`)
- Updated `LinuxStartAllWorkflow` and `LinuxStopAllWorkflow` to consume sub-workflow states via pattern matching instead of `.step` accessors
- CLI progress printers updated to switch on `LinuxWorkflowState` enum cases
- Used `.stopped` as default for unknown service states (since `ServiceState` has no `.unknown` case)

---

### Phase 7: Update LambdaService Protocol ✅ COMPLETED

**Tasks:**
- [x] 7.1: Remove Combine imports from `LambdaService`
- [x] 7.2: Remove `statusPublisher` and `isLoadingStatusPublisher` requirements
- [x] 7.3: Add `func refresh() async` requirement
- [x] 7.4: Update `LocalService` protocol if needed
- [x] 7.5: Build verification

**Files modified:**
- `Sources/services/DeployCoreService/LambdaService.swift`
- `Sources/services/DeployLocalService/LocalService.swift`
- `Sources/apps/MacApp/Models/DeployLinuxModel.swift`
- `Sources/apps/MacApp/Models/DeployXcodeModel.swift`
- `Sources/apps/MacApp/Models/AppModel.swift`
- `Sources/apps/MacApp/UI/LocalService/LocalServicesModel.swift`
- `Sources/apps/MacApp/UI/LocalService/LocalServiceView.swift`
- `Sources/apps/MacApp/UI/LocalService/DockerServicesView.swift`

**Technical Notes:**
- Removed `Combine` import from `LambdaService.swift` - protocol no longer depends on Combine framework
- Replaced `statusPublisher`, `isLoadingStatusPublisher`, and `refreshStatus()` with:
  - `currentStatus: DeploymentStatus` - synchronous property for UI observation
  - `isLoadingStatus: Bool` - synchronous property for loading state
  - `refresh() async -> DeploymentStatus?` - async method to trigger status refresh
- Updated `DeployLinuxModel` and `DeployXcodeModel`:
  - Removed Combine imports and `CurrentValueSubject` properties
  - Added `currentStatus` and `isLoadingStatus` stored properties
  - Replaced `refreshStatus()` with `refresh() async`
  - Updated `startWithServices()`, `stopWithServices()`, and `startIfNecessary()` to use new async pattern
- Updated `LocalServicesModel`:
  - Removed Combine subscriptions and publishers
  - Changed to computed properties that delegate to underlying service's `currentStatus` and `isLoadingStatus`
  - Added `refresh() async` that delegates to underlying service
- Updated `LocalService.startIfNecessary()` default implementation to call `await refresh()` instead of `refreshStatus()`
- Updated `DockerServicesView` callback from `() -> Void` to `() async -> Void` for async refresh
- Updated `LocalServiceView` to use `.task` modifier and async button actions
- `AppModel.refreshStatus()` now spawns a `Task` internally to call async `refresh()` on services
- **Scope expansion**: The spec originally planned for models to be updated in Phase 8/9, but this was combined into Phase 7 to maintain a buildable state after each phase

---

### Phase 8: Refactor DeployLinuxModel (MERGED INTO PHASE 7)

**Note:** The core changes (removing Combine, adding async refresh) were completed as part of Phase 7 to maintain a buildable state. The remaining `@Observable` macro and unified `ModelState` enum work is deferred as it requires additional architectural decisions.

**Completed in Phase 7:**
- [x] 8.7: Remove Combine import
- [x] 8.8: Build verification

**Deferred (requires further design work):**
- [ ] 8.1: Add `@Observable` macro
- [ ] 8.2: Replace current state properties with unified `state: ModelState`
- [ ] 8.3: Remove `buildState` and `lambdaState` properties (integrated into `ModelState`)
- [ ] 8.4: Remove `isTransitioning` flag
- [ ] 8.5: Define `ModelState` enum with `init(from:prior:)`
- [ ] 8.6: Update all methods to consume workflows and set state directly

**Files to modify:**
- `Sources/apps/MacApp/Models/DeployLinuxModel.swift`

---

### Phase 9: Refactor DeployXcodeModel (MERGED INTO PHASE 7)

**Note:** Same as Phase 8 - core Combine removal completed in Phase 7. The `@Observable` and `ModelState` work is deferred.

**Completed in Phase 7:**
- [x] 9.6: Remove Combine import
- [x] 9.7: Build verification

**Deferred (requires further design work):**
- [ ] 9.1: Add `@Observable` macro
- [ ] 9.2: Replace Combine subjects with `state: ModelState`
- [ ] 9.3: Remove separate state properties
- [ ] 9.4: Define `ModelState` enum
- [ ] 9.5: Update all methods

**Files to modify:**
- `Sources/apps/MacApp/Models/DeployXcodeModel.swift`

---

### Phase 10: Update Views (MERGED INTO PHASE 7)

**Note:** View updates were completed as part of Phase 7 since they were required to maintain a buildable state after removing Combine from the protocol.

**Completed in Phase 7:**
- [x] 10.1: Find all views consuming `statusPublisher` or `isLoadingStatusPublisher`
- [x] 10.2: Update views to use `model.currentStatus` and `model.isLoadingStatus` directly
- [x] 10.3: Remove Combine subscriptions from `LocalServicesModel`
- [x] 10.4: Build and test UI

**Files modified:**
- `Sources/apps/MacApp/UI/LocalService/LocalServicesModel.swift` - removed Combine subscriptions
- `Sources/apps/MacApp/UI/LocalService/LocalServiceView.swift` - updated to use async `refresh()`
- `Sources/apps/MacApp/UI/LocalService/DockerServicesView.swift` - updated callback to async

---

### Phase 11: Final Cleanup

**Tasks:**
- [ ] 11.1: Remove any unused Combine imports
- [ ] 11.2: Remove `BuildState` and `LambdaState` if no longer used elsewhere
- [ ] 11.3: Run all tests
- [ ] 11.4: Update this document to "Complete"

---

## Risk Assessment

| Risk | Mitigation |
|------|------------|
| View bindings break | Test each view after updating model |
| Protocol conformance errors | Update models in same phase as protocol |
| Workflow state mismatch | Verify each workflow yields correct state type |
| Regression in functionality | Run tests after each phase |

---

## Success Criteria

1. Both `DeployLinuxModel` and `DeployXcodeModel` use `@Observable` macro
2. Both models have single `state: ModelState` property
3. `LambdaService` protocol has no Combine requirements
4. No Combine imports in model files
5. All workflows yield `LinuxWorkflowState` (or equivalent for Xcode)
6. All views work correctly with new observable models
7. All tests pass
8. No functionality regressions

---

## References

- `DeployRemoteModel.swift` - Reference implementation for model pattern
- `DeploymentState.swift` - Reference for `WorkflowState` and `DeploymentSnapshot`
- `RefreshWorkflow.swift` - Reference for workflow consumption pattern
- [layered-architecture.md](../architecture/layered-architecture.md) - MV pattern and state ownership
