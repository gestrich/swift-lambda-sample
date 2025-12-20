# Use Case to Model Composition Migration

This document outlines the migration from use case composition (use cases calling use cases) to model composition (models calling models).

## Problem

Currently, several use cases call other use cases directly. This bypasses the models that should own state for those domains, causing potential state staleness. When `LinuxStopAllUseCase` calls `StopServicesUseCase` directly, `LocalServicesModel` never knows services stopped.

## Solution

Migrate to model composition where:
1. Use cases are leaf operations that only call SDKs
2. Models call other models for composite operations
3. Each model owns and updates its own state

## Current Use Case Compositions

| Parent Use Case | Child Use Cases | Feature |
|-----------------|-----------------|---------|
| `DeployInitUseCase` | `DeployUseCase`, `UpdateLambdaUseCase` | DeployRemoteFeature |
| `RefreshUseCase` | `ResumeMonitoringUseCase` | DeployRemoteFeature |
| `XcodeStartAllUseCase` | `StartServicesUseCase`, `XcodeStartLambdaUseCase` | DeployXcodeFeature |
| `XcodeStopAllUseCase` | `XcodeStopLambdaUseCase`, `StopServicesUseCase` | DeployXcodeFeature |
| `LinuxStartAllUseCase` | `StartServicesUseCase`, `LinuxSetupNetworkUseCase`, `LinuxStartLambdaUseCase` | DeployLinuxFeature |
| `LinuxStopAllUseCase` | `LinuxStopLambdaUseCase`, `StopServicesUseCase` | DeployLinuxFeature |

---

## Phase 1: Local Services Model Foundation ✅

Establish `LocalServicesModel` as the single source of truth for services state. This model is shared across Xcode and Linux workflows.

### Tasks

- [x] **1.1** Create or update `LocalServicesModel` in MacApp with proper state enum
- [x] **1.2** Ensure `LocalServicesModel` owns `StartServicesUseCase` and `StopServicesUseCase`
- [x] **1.3** Add `startAll()` and `stopAll()` methods that update model state
- [x] **1.4** Remove services state duplication from parent models (XcodeModel, LinuxModel)

### Technical Notes

- `LocalServicesModel` is located at `Sources/apps/MacApp/Models/LocalServicesModel.swift`
- Uses unified `ModelState` enum with `uninitialized`, `loading`, `ready`, and `operating` states
- Parent models (`DeployXcodeModel`, `DeployLinuxModel`) hold `servicesModel: LocalServicesModel` as child model
- Service methods delegate directly to `LocalServicesModel` (e.g., `startAllServices()`, `stopAllServices()`)

### Files to Modify

- `Sources/apps/MacApp/Models/LocalServicesModel.swift`
- `Sources/apps/MacApp/Models/LocalModel.swift` (ensure it holds `LocalServicesModel`)

### Target Pattern

```swift
@MainActor @Observable
final class LocalServicesModel {
    private(set) var state: State = .unknown

    func startAll(configuration: ServiceConfiguration) async throws {
        let useCase = StartServicesUseCase.create(configuration: configuration)
        for try await progress in useCase.useCase.stream(options: .all) {
            state = .starting(progress)
        }
        state = .running
    }

    func stopAll(configuration: ServiceConfiguration) async throws {
        let useCase = StopServicesUseCase.create(configuration: configuration)
        for try await progress in useCase.useCase.stream(options: .all) {
            state = .stopping(progress)
        }
        state = .stopped
    }
}
```

---

## Phase 2: Xcode Model Migration ✅

Migrate `XcodeStartAllUseCase` and `XcodeStopAllUseCase` composition to `XcodeModel` calling `LocalServicesModel`.

### Tasks

- [x] **2.1** Update `XcodeModel` to hold reference to `LocalServicesModel`
- [x] **2.2** Create `XcodeModel.startAll()` that:
  - Calls `servicesModel.startAll(configuration: .xcode)`
  - Then runs `XcodeStartLambdaUseCase` for Lambda-specific work
- [x] **2.3** Create `XcodeModel.stopAll()` that:
  - Runs `XcodeStopLambdaUseCase` first
  - Then calls `servicesModel.stopAll(configuration: .xcode)`
- [x] **2.4** Simplify `XcodeStartAllUseCase` to only handle Lambda (or remove if model handles it)
- [x] **2.5** Simplify `XcodeStopAllUseCase` to only handle Lambda (or remove if model handles it)
- [x] **2.6** Update views to access services state via `xcodeModel.servicesModel.state`

### Technical Notes

- `DeployXcodeModel.startWithServices()` now uses model composition:
  1. Sets state to `.operating(.startingServices(...))`
  2. Calls `servicesModel.startAllServices()` (model composition)
  3. Sets state to `.operating(.startingLambda(...))`
  4. Iterates over `XcodeStartLambdaUseCase.stream()` for Lambda operations
- `DeployXcodeModel.stopWithServices()` uses same pattern but reversed order (Lambda first, then services)
- `XcodeStartAllUseCase` and `XcodeStopAllUseCase` remain available for CLI use where models aren't needed
- Views already access services state via `xcodeModel.servicesModel` (no changes needed)

### Files to Modify

- `Sources/apps/MacApp/Models/XcodeModel.swift`
- `Sources/features/DeployXcodeFeature/usecases/XcodeStartAllUseCase.swift`
- `Sources/features/DeployXcodeFeature/usecases/XcodeStopAllUseCase.swift`
- Xcode-related views in MacApp

### Target Pattern

```swift
@MainActor @Observable
final class XcodeModel {
    private(set) var state: State = .idle
    let servicesModel: LocalServicesModel

    func startAll() async throws {
        state = .startingServices
        try await servicesModel.startAll(configuration: .xcode)

        state = .startingLambda
        for try await progress in startLambdaUseCase.stream() {
            state = .startingLambda(progress)
        }

        state = .running
    }
}
```

---

## Phase 3: Linux Model Migration ✅

Migrate `LinuxStartAllUseCase` and `LinuxStopAllUseCase` composition to `LinuxModel` calling `LocalServicesModel`.

### Tasks

- [x] **3.1** Update `LinuxModel` to hold reference to `LocalServicesModel`
- [x] **3.2** Create `LinuxModel.startAll()` that:
  - Calls `servicesModel.startAll(configuration: .linux)`
  - Runs `LinuxSetupNetworkUseCase` (Linux-specific)
  - Runs `LinuxStartLambdaUseCase`
- [x] **3.3** Create `LinuxModel.stopAll()` that:
  - Runs `LinuxStopLambdaUseCase` first
  - Then calls `servicesModel.stopAll(configuration: .linux)`
- [x] **3.4** Simplify `LinuxStartAllUseCase` to only handle Lambda + network (or remove)
- [x] **3.5** Simplify `LinuxStopAllUseCase` to only handle Lambda (or remove)
- [x] **3.6** Update views to access services state via `linuxModel.servicesModel.state`

### Technical Notes

- `DeployLinuxModel.startWithServices()` now uses model composition:
  1. Sets state to `.operating(.startingServices(...))`
  2. Calls `servicesModel.startAllServices()` (model composition)
  3. Sets state to `.operating(.settingUpNetwork(...))`
  4. Iterates over `LinuxSetupNetworkUseCase.stream()` for Docker network setup
  5. Sets state to `.operating(.startingLambda(...))`
  6. Iterates over `LinuxStartLambdaUseCase.stream()` for Lambda container operations
- `DeployLinuxModel.stopWithServices()` uses same pattern but reversed order (Lambda first, then services)
- `LinuxStartAllUseCase` and `LinuxStopAllUseCase` remain available for CLI use where models aren't needed
- Views already access services state via `linuxModel.servicesModel` (no changes needed)
- Added `mapNetworkStep` and `mapNetworkDetail` helper methods for network state mapping

### Files Modified

- `Sources/apps/MacApp/Models/DeployLinuxModel.swift`

### Target Pattern

```swift
@MainActor @Observable
final class LinuxModel {
    private(set) var state: State = .idle
    let servicesModel: LocalServicesModel

    func startAll() async throws {
        state = .startingServices
        try await servicesModel.startAll(configuration: .linux)

        state = .settingUpNetwork
        for try await progress in setupNetworkUseCase.stream() {
            state = .settingUpNetwork(progress)
        }

        state = .startingLambda
        for try await progress in startLambdaUseCase.stream() {
            state = .startingLambda(progress)
        }

        state = .running
    }
}
```

---

## Phase 4: Remote Deploy Model Migration ✅

Migrate `DeployInitUseCase` composition to `RemoteDeployModel` calling child models/use cases appropriately.

### Tasks

- [x] **4.1** Analyze `DeployInitUseCase` orchestration (deploy + update-lambda + verify)
- [x] **4.2** Determine if `DeployUseCase` and `UpdateLambdaUseCase` need separate models or can remain as use cases owned by `RemoteDeployModel`
- [x] **4.3** If separate models needed, create `InfrastructureModel` and `LambdaCodeModel`
- [x] **4.4** Update `RemoteDeployModel.deployInit()` to call child models
- [x] **4.5** Simplify `DeployInitUseCase` to be a leaf operation or remove
- [x] **4.6** Update views accordingly

### Technical Notes

- **Decision**: `DeployUseCase` and `UpdateLambdaUseCase` remain as leaf use cases owned by `DeployRemoteModel`. No separate models needed since they're already well-encapsulated.
- `DeployRemoteModel.deployInit()` now uses **model composition**:
  1. Performs safety check (prevent accidental database deletion) - inline in model
  2. Calls `deploy(options:)` (model's own method for infrastructure)
  3. Calls `updateLambdaCode()` (model's own method for Lambda)
  4. Initializes database if Postgres is included (new inline operation)
  5. Verifies deployment with health check (new inline operation)
- Added new `UseCaseState` cases for deploy-init specific phases:
  - `.initializingDatabase(InitDatabaseProgress)` - for database initialization step
  - `.verifyingDeployment(VerifyProgress)` - for health check verification step
- `DeployInitUseCase` remains available for CLI use (same pattern as `XcodeStartAllUseCase`)
- Views updated to handle new use case states with appropriate status text

### Files Modified

- `Sources/apps/MacApp/Models/DeployRemoteModel.swift` - Added `deployInit()` method with model composition
- `Sources/features/DeployRemoteFeature/services/Models/DeploymentState.swift` - Added new `UseCaseState` cases
- `Sources/apps/MacApp/UI/RemoteService/CDKInfrastructureSectionView.swift` - Added UI for new states
- `Sources/apps/CLIApp/Commands/DeployRemote/*.swift` - Updated switch statements for exhaustiveness

### Considerations

`DeployInitUseCase` has complex safety checks (database deletion prevention) that may need to stay in the use case or move to a service. Evaluate whether the orchestration logic belongs in:
- The model (if it's about coordinating UI state)
- A service (if it's reusable business logic)
- The use case (if it's a single atomic operation from the user's perspective)

---

## Phase 5: Refresh Use Case Migration ✅

Migrate `RefreshUseCase` → `ResumeMonitoringUseCase` conditional delegation.

### Tasks

- [x] **5.1** Analyze `RefreshUseCase` conditional logic (only delegates for in-progress states)
- [x] **5.2** Determine if `ResumeMonitoringUseCase` needs its own model
- [x] **5.3** If monitoring is a sub-concern, create `MonitoringModel` or handle in `RemoteDeployModel`
- [x] **5.4** Update refresh logic to route through appropriate model
- [x] **5.5** Simplify or remove `RefreshUseCase` composition

### Technical Notes

- **Decision**: `ResumeMonitoringUseCase` does NOT need its own model. It's a leaf use case that monitors CloudFormation state.
- The conditional logic (deciding whether to resume monitoring) moved from `RefreshUseCase` to `DeployRemoteModel.refresh()`.
- `DeployRemoteModel.refresh()` now uses **model composition**:
  1. Queries CloudFormation state directly via `cfClient.queryState()`
  2. For stable states (deployed, notDeployed, failed): creates `DeploymentSnapshot` and sets `.ready()` state
  3. For in-progress states (deploying, destroying): delegates to `ResumeMonitoringUseCase` to monitor completion
- `RefreshUseCase` remains available for CLI use where models aren't needed, but is no longer called by the model.
- `ResumeMonitoringUseCase` remains unchanged as a leaf use case.

### Files Modified

- `Sources/apps/MacApp/Models/DeployRemoteModel.swift` - Updated `refresh()` to use model composition

---

## Phase 6: CLI App Alignment

Ensure CLI commands work with the new model-based composition (or use use cases directly since CLI doesn't need observable state).

### Tasks

- [ ] **6.1** Review CLI commands that use composite use cases
- [ ] **6.2** Decide: CLI uses models, or CLI uses use cases directly (both valid)
- [ ] **6.3** If CLI uses use cases directly, ensure leaf use cases provide complete functionality
- [ ] **6.4** Update CLI commands as needed
- [ ] **6.5** Test CLI workflows after migration

### Files to Modify

- `Sources/apps/CLIApp/Commands/Local/` (Xcode and Linux commands)
- `Sources/apps/CLIApp/Commands/AWS/` (deploy commands)

### Consideration

CLI doesn't need `@Observable` state tracking. Options:
1. CLI creates models but ignores observation (wasteful)
2. CLI uses use cases directly (simpler, but use cases must be leaf operations)
3. CLI uses a thin coordination layer that mirrors model logic

Recommendation: CLI uses use cases directly. Composite operations in CLI can call multiple use cases sequentially without needing model state management.

---

## Phase 7: Cleanup and Documentation

Remove dead code and update documentation.

### Tasks

- [ ] **7.1** Remove unused composite use cases (if fully replaced by model methods)
- [ ] **7.2** Update `layered-architecture.md` if patterns changed
- [ ] **7.3** Add examples of model composition to documentation
- [ ] **7.4** Review and remove state mapping code that's no longer needed
- [ ] **7.5** Run all tests and fix any breakages

---

## Migration Order Recommendation

1. **Phase 1** first — establishes the foundation
2. **Phase 2 and 3** can be done in parallel (Xcode and Linux are independent)
3. **Phase 4 and 5** after local models are stable
4. **Phase 6** after Mac app migration complete
5. **Phase 7** last — cleanup

## Success Criteria

- [ ] No use case imports another use case
- [ ] Each model owns its state completely
- [ ] Views access child state through child model references
- [ ] CLI commands work correctly
- [ ] All tests pass
