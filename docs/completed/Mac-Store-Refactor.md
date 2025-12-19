# Mac App Model/Service Refactor Plan

## Problem

The current "Models" in `Sources/SwiftDeploy/Models/` mix two concerns:
1. **App State** - Observable properties for UI binding (`@Observable`, Combine publishers)
2. **Business Logic** - Operations like deploy, build, start/stop services

This creates issues:
- Models are in SwiftDeploy but are really MacApp concerns
- CLI depends on Models when it should use stateless Services
- CLI commands make multiple service calls (code smell - missing high-level service)

## Goal

- **Models** → Move to MacApp, hold only observable state, delegate to services
- **Services** → Stay in SwiftDeploy, stateless, single high-level method per operation
- **CLI** → Call one service method, print result

---

## 1. DependencyStatusServiceModel ✅ COMPLETED

**Current Location:** `Sources/MacApp/Models/DependencyStatusModel.swift` (slimmed down)
**Service Location:** `Sources/SwiftDeploy/Services/DependencyCheckerService.swift`

**Analysis:**
- State: `homebrewStatus`, `nodejsStatus`, `dockerStatus`, `awsCLIStatus`, `cdkStatus`, `githubCLIStatus`
- Logic: `checkCommand()` - runs CLI to check if dependency is installed

**Refactor Plan:**

### [x] 1.1 Create DependencyCheckerService
- Location: `Sources/SwiftDeploy/Services/DependencyCheckerService.swift`
- Stateless service with method: `func checkDependency(_ name: String) async -> DependencyInstallStatus`
- Returns result, doesn't store it

### [x] 1.2 Slim down DependencyStatusServiceModel → DependencyStatusModel
- Renamed to `DependencyStatusModel` (dropped "Service")
- Moved to `Sources/MacApp/Models/DependencyStatusModel.swift`
- Keeps `@Observable` state properties
- Injects `DependencyCheckerService`
- `checkAll()` calls service, stores results in state

### [x] 1.3 Update MacApp references
- Updated `AppModel` to use new location
- Updated `SetupViews.swift` parameter type

### [x] 1.4 Verify build

---

## 2. RemoteServiceModel ✅ COMPLETED

**Current Location:** `Sources/MacApp/Models/RemoteModel.swift` (slimmed down)
**Service Location:** `Sources/SwiftDeploy/Services/RemoteDeploymentService.swift`

**Analysis:**
- State: `cachedEndpoint`, `statusSubject`, `isLoadingStatusSubject`, `githubService?`, `cdkInfrastructureService?`, `lambdaBuildService?`
- Logic: `deploy()`, `deployInit()`, `tearDown()`, `updateLambdaCode()`, `pollDeploymentStatus()`, `getStackOutputs()`, `testLambda()`, etc.

**Existing Services Used:**
- `CDKService` - CDK operations
- `AWSCLIService` - AWS CLI wrapper
- `GitHubService` - GitHub Actions
- `CDKInfrastructureService` - Infrastructure status
- `LambdaBuildService` - Local build & upload

**Refactor Plan:**

### [x] 2.1 Create RemoteDeploymentService (high-level facade)
- Location: `Sources/SwiftDeploy/Services/RemoteDeploymentService.swift`
- Stateless facade that orchestrates sub-services
- Methods:
  - `func deploy(options: DeploymentOptions) async throws -> DeploymentResult`
  - `func deployInit(options: DeploymentOptions, withPostgres: Bool, skipPush: Bool) async throws`
  - `func tearDown(cdkDirectory: String) async throws`
  - `func updateLambdaCode(skipPush: Bool) async throws`
  - `func getStatus() async throws -> RemoteStatus`
  - `func testEndpoints(apiUrl: String) async throws`

### [x] 2.2 Update CLI commands to use RemoteDeploymentService
- `DeployCommand` → `remoteDeploymentService.deploy()`
- `DeployInitCommand` → `remoteDeploymentService.deployInit()`
- `TearDownCommand` → `remoteDeploymentService.tearDown()`
- `UpdateLambdaCommand` → `remoteDeploymentService.updateLambdaCode()`
- `StatusCommand` → `remoteDeploymentService.getStatus()`
- Each CLI command: create service, call one method, print result

### [x] 2.3 Slim down RemoteServiceModel → RemoteModel
- Renamed to `RemoteModel` (dropped "Service")
- Moved to `Sources/MacApp/Models/RemoteModel.swift`
- Keeps only:
  - Observable state (`cachedEndpoint`, publishers, sub-service references for UI)
  - `refreshStatus()` - updates state by calling service
  - Computed properties for UI (`endpoint`, `isConfigured`, etc.)
  - LambdaService protocol conformance for testing

### [x] 2.4 Update MacApp references
- Updated `AppModel`
- Updated `RemoteServiceView`
- Updated `LambdaUpdateView`

### [x] 2.5 Verify build

---

## 3. XcodeLocalServiceModel ✅ COMPLETED

**Current Location:** `Sources/MacApp/Models/XcodeLocalModel.swift` (slimmed down)
**Service Location:** `Sources/SwiftDeploy/Services/XcodeLocalDevelopmentService.swift`

**Analysis:**
- State: `statusSubject`, `isLoadingStatusSubject`, `isTransitioning`, `buildState`, `lambdaState`
- Logic: `startAllServices()`, `stopAllServices()`, `build()`, `startLambda()`, `stopLambda()`, `startWithServices()`, `stopWithServices()`, `testLambda()`, etc.

**Existing Services Used:**
- `DockerService` - Docker operations
- `PostgreSQLService` - PostgreSQL container
- `MinIOService` - S3-compatible storage
- `DynamoDBLocalService` - DynamoDB Local

**Refactor Plan:**

### [x] 3.1 Create XcodeLocalDevelopmentService (high-level facade)
- Location: `Sources/SwiftDeploy/Services/XcodeLocalDevelopmentService.swift`
- Stateless facade for Xcode local development
- Methods:
  - `func build(clean: Bool) async throws`
  - `func startLambda() async throws`
  - `func stopLambda() async throws`
  - `func startWithServices() async throws`
  - `func stopWithServices() async throws`
  - `func startAllServices() async throws`
  - `func stopAllServices() async throws`
  - `func status() async throws -> DeploymentStatus`
  - `func testLambda() async throws`

### [x] 3.2 Update CLI LocalMacCommand to use XcodeLocalDevelopmentService
- Each subcommand: create service, call one method, print result
- Remove direct Model instantiation

### [x] 3.3 Slim down XcodeLocalServiceModel → XcodeLocalModel
- Renamed to `XcodeLocalModel` (dropped "Service")
- Moved to `Sources/MacApp/Models/XcodeLocalModel.swift`
- Keeps only:
  - Observable state (`buildState`, `lambdaState`, publishers)
  - `refreshStatus()` - updates state
  - State transition flags (`isTransitioning`)
- Delegates operations to `XcodeLocalDevelopmentService`

### [x] 3.4 Update MacApp references
- Updated `AppModel`
- Updated `ConnectionMode` enum

### [x] 3.5 Verify build

---

## 4. LinuxLocalServiceModel ✅ COMPLETED

**Current Location:** `Sources/MacApp/Models/LinuxLocalModel.swift` (slimmed down)
**Service Location:** `Sources/SwiftDeploy/Services/LinuxLocalDevelopmentService.swift`

**Analysis:**
- Nearly identical structure to XcodeLocalServiceModel
- Different build process (Docker-based vs native)
- Different Lambda execution (container vs process)

**Refactor Plan:**

### [x] 4.1 Create LinuxLocalDevelopmentService (high-level facade)
- Location: `Sources/SwiftDeploy/Services/LinuxLocalDevelopmentService.swift`
- Same interface as XcodeLocalDevelopmentService
- Additional methods:
  - `func setupDockerNetwork() async throws`
  - `func runInteractive() async throws`

### [x] 4.2 Update CLI LocalLinuxCommand to use LinuxLocalDevelopmentService
- Each subcommand: create service, call one method, print result

### [x] 4.3 Slim down LinuxLocalServiceModel → LinuxLocalModel
- Renamed to `LinuxLocalModel` (dropped "Service")
- Moved to `Sources/MacApp/Models/LinuxLocalModel.swift`
- Same pattern as XcodeLocalModel

### [x] 4.4 Update MacApp references
- Updated `AppModel`
- Updated `ConnectionMode` enum

### [x] 4.5 Verify build

---

## 5. Final Cleanup ✅ COMPLETED

### [x] 5.1 Remove empty Models folder from SwiftDeploy
- Removed empty `Sources/SwiftDeploy/Models/` directory

### [x] 5.2 Update LambdaService protocol
- Protocol stays in SwiftDeploy (provides shared types used by services)
- Fixed outdated comment: `LinuxLocalServiceModel` → `LinuxLocalModel`

### [x] 5.3 Update LocalService protocol
- Protocol stays in SwiftDeploy (provides shared interface)
- Fixed outdated comment: `LinuxLocalServiceModel` → `LinuxLocalModel`

### [x] 5.4 Final build verification
- `swift build` passes successfully

### [x] 5.5 Update architecture documentation
- Updated `docs/architecture/MacAppArchitecture.md` with:
  - Project structure diagram
  - Model/Service separation explanation
  - Data flow for MacApp and CLI
  - Protocol documentation

---

## 6. CDKInfrastructureService ✅ COMPLETED

**Current Location:** `Sources/MacApp/Models/CDKInfrastructureModel.swift` (slimmed down)
**Service Location:** `Sources/SwiftDeploy/Services/CDKInfrastructureQueryService.swift`

**Analysis:**
- `@MainActor @Observable` class mixing state and logic
- State: `infrastructureStatus` (CDKInfrastructureStatus)
- Logic: `refreshStatus()`, `deploy()`, `destroy()`, `queryConfiguration()`, `monitorExistingOperation()`

**Existing Services Used:**
- `CDKService` - CDK CLI operations
- `AWSCLIService` - AWS CLI wrapper (stack status, outputs)

**Refactor Plan:**

### [x] 6.1 Create CDKInfrastructureQueryService (stateless)
- Location: `Sources/SwiftDeploy/Services/CDKInfrastructureQueryService.swift`
- Stateless actor for querying CDK/CloudFormation state
- Methods:
  - `func getStackStatus(stackName:) async throws -> String`
  - `func getStackOutputs(stackName:) async throws -> [String: String]`
  - `func queryConfiguration(stackName:) async throws -> CDKInfrastructureConfiguration`
  - `func getStackEvents(stackName:limit:) async throws -> [CloudFormationStackEvent]`
  - `func build(output:) async throws`
  - `func deploy(withPostgres:withNATGateway:output:) async throws`
  - `func destroy(output:) async throws`

### [x] 6.2 Create CDKInfrastructureModel (observable state)
- Location: `Sources/MacApp/Models/CDKInfrastructureModel.swift`
- `@Observable` class holding UI state
- Keeps: `infrastructureStatus`, progress polling, monitoring
- Delegates operations to `CDKInfrastructureQueryService`

### [x] 6.3 Update MacApp references
- Updated `RemoteModel` to use `CDKInfrastructureModel`
- Updated `CDKInfrastructureSectionView` parameter from `service:` to `model:`
- Updated `RemoteServiceView` to pass `cdkInfrastructureModel`

### [x] 6.4 Verify build

---

## 7. GitHubService ✅ COMPLETED

**Current Location:** `Sources/MacApp/Models/GitHubCIModel.swift` (slimmed down)
**Service Location:** `Sources/SwiftDeploy/Services/GitHubActionsService.swift`

**Analysis:**
- `@MainActor @Observable` class mixing state and logic
- State: `ciStatus` (GitHubCIStatus), `config` (GitHubConfiguration)
- Logic: `refreshStatus()`, `pushAndDeploy()`, `triggerWorkflow()`, `monitorWorkflowRun()`

**Existing Services Used:**
- `GitHubCLIService` - GitHub CLI wrapper
- `GitService` - Git operations

**Refactor Plan:**

### [x] 7.1 Create GitHubActionsService (stateless)
- Location: `Sources/SwiftDeploy/Services/GitHubActionsService.swift`
- Stateless actor for GitHub Actions operations
- Methods:
  - `func getLatestWorkflowRun() async throws -> WorkflowRun?`
  - `func getGitStatus() async throws -> GitStatus`
  - `func pushAndTriggerWorkflow() async throws -> String` (returns run ID)
  - `func triggerWorkflow() async throws -> String`
  - `func monitorWorkflowRun(runId: String) -> AsyncStream<WorkflowProgress>`
  - `func getRunDetail(runId: String) async throws -> GitHubRunDetail`

### [x] 7.2 Create GitHubCIModel (observable state)
- Location: `Sources/MacApp/Models/GitHubCIModel.swift`
- `@Observable` class holding UI state
- Keeps: `ciStatus`, `config`
- Delegates operations to `GitHubActionsService`

### [x] 7.3 Update MacApp references
- Updated `RemoteModel` to use `GitHubCIModel` instead of `GitHubService`
- Updated `LambdaUpdateView` to use `githubCIModel`
- Updated `GitHubCISectionView` parameter from `service:` to `model:`
- Updated `RemoteDeploymentService` to use `GitHubActionsService`

### [x] 7.4 Verify build
- Deleted old `GitHubService.swift` (all functionality moved)
- `swift build` passes successfully

---

## Summary: Before vs After

### Before
```
SwiftDeploy/Models/
├── RemoteServiceModel.swift      (state + logic mixed)
├── XcodeLocalServiceModel.swift  (state + logic mixed)
├── LinuxLocalServiceModel.swift  (state + logic mixed)
└── DependencyStatusServiceModel.swift

CLI → Model → sub-services
```

### After (Refactor Complete ✅)
```
SwiftDeploy/Services/
├── RemoteDeploymentService.swift          (stateless facade)
├── XcodeLocalDevelopmentService.swift     (stateless facade)
├── LinuxLocalDevelopmentService.swift     (stateless facade)
├── DependencyCheckerService.swift         (stateless)
├── CDKInfrastructureQueryService.swift    (stateless)
├── GitHubActionsService.swift             (stateless)
└── ... (existing services)

SwiftDeploy/LambdaServices/
├── LambdaService.swift                    (protocol + DeploymentStatus)
└── LocalService.swift                     (protocol for local services)

MacApp/Models/
├── RemoteModel.swift              (@Observable state only)
├── XcodeLocalModel.swift          (@Observable state only)
├── LinuxLocalModel.swift          (@Observable state only)
├── DependencyStatusModel.swift    (@Observable state only)
├── CDKInfrastructureModel.swift   (@Observable state only)
└── GitHubCIModel.swift            (@Observable state only)

CLI → Service (single call)
MacApp View → Model → Service
```

---

## 8. Move Business Logic from CDKInfrastructureModel to Service ✅ COMPLETED

**Status:** Completed

**Problem (solved):**

`CDKInfrastructureModel` previously contained significant business/domain logic that now lives in the service layer:

- **Progress polling** - Moved to `CDKInfrastructureQueryService` via `AsyncThrowingStream`
- **Operation monitoring** - Now via `monitorOperation()` stream
- **Deployment orchestration** - Now via `deployWithProgress()` and `destroyWithProgress()` streams
- **Credential error detection** - Moved to `CDKInfrastructureError.isCredentialError()`

**Key Constraint:** Services remain stateless. They **return** state via `AsyncThrowingStream`, not **hold** state.

**Data Flow (implemented):**
```
View → Model.deploy() → Service.deployWithProgress() → AsyncThrowingStream<Progress>
                      ↓
                Model updates state from stream
```

**Implemented Changes:**

### [x] 8.1 Service returns progress via AsyncThrowingStream (stateless)
- Added `CDKDeploymentProgress` type to service (immutable snapshot)
- Added `ResourceProgressSnapshot` and `ResourceStatusSnapshot` types
- Added `func deployWithProgress(...) -> AsyncThrowingStream<CDKDeploymentProgress, Error>`
- Added `func destroyWithProgress(...) -> AsyncThrowingStream<CDKDeploymentProgress, Error>`
- Added `func monitorOperation(...) -> AsyncThrowingStream<CDKDeploymentProgress, Error>`
- Service creates a fresh stream per call (no stored state)
- Stream internally polls CloudFormation and yields progress snapshots
- Each yield is a complete state snapshot (not a delta)
- Methods are `nonisolated` for clean MainActor integration

### [x] 8.2 Simplified CDKInfrastructureModel
- Removed polling logic entirely (`pollProgressUntilCancelled`, `updateProgressOnce`, `runDeployWithProgressPolling`)
- Model subscribes to service's `AsyncThrowingStream`
- Model maps stream values directly to `@Observable` state
- Model is now a thin state container (from ~300 lines to ~200 lines)
- `deploy()`, `updateInfrastructure()`, `destroy()` now use `for try await` loops
- `refreshStatus()` now uses `getFullStatus()` for complete snapshot

### [x] 8.3 Service returns typed errors (stateless)
- Added `CDKInfrastructureError` enum with cases:
  - `.credentialExpired(message:)` - AWS credential issues
  - `.stackNotFound(stackName:)` - Stack doesn't exist
  - `.deploymentFailed(reason:)` - Deployment errors
  - `.buildFailed(reason:)` - CDK build errors
  - `.operationInProgress(operation:)` - Operation already running
  - `.unknown(message:)` - Other errors
- Moved `isCredentialError()` to service as static method on error type
- Added `getFullStatus()` method returning `CDKInfrastructureStatus` directly
- Model catches typed errors and maps to UI states

### [x] 8.4 Updated Views
- Updated `CDKInfrastructureSectionView` to use `ResourceProgressSnapshot` and `ResourceStatusSnapshot`
- Added `SwiftDeploy` import to view file

### [x] 8.5 Moved CDKInfrastructureStatus to service
- `CDKInfrastructureStatus` struct moved from Model to Service
- Reuses `CDKInfrastructureConfiguration` and `CDKStackOutputs` (no duplicate types)
- `getFullStatus()` returns `CDKInfrastructureStatus` directly (removed intermediate `CDKInfrastructureStatusSnapshot`)
- Model now directly assigns: `infrastructureStatus = try await queryService.getFullStatus(stackName:)`
- `refreshStatus()` reduced from ~40 lines to ~20 lines

**Benefits Achieved:**
- Services remain stateless and fully testable
- Models are trivially simple (state assignment + subscriptions)
- Clear data flow: Service returns state → Model stores state → View observes state
- Consistent pattern across all Model/Service pairs
- Reduced code in Model (~200 lines removed total)
- Single source of truth for CDK types in service layer
- No intermediate snapshot type needed

---

## 9. Simplify GitHubCIModel Business Logic ✅ COMPLETED

**Status:** Completed

**Problem (solved):**

`GitHubCIModel` previously contained business/domain logic that now lives in the service layer:

- **Status transformation** - Moved to `GitHubActionsService.getFullStatus()`
- **Date parsing** - Moved to `GitHubActionsService.parseGitHubDate()`
- **Auto-monitoring detection** - Now via `GitHubCISnapshot.inProgressRunId`

**Data Flow (implemented):**
```
View → Model.refreshStatus() → Service.getFullStatus() → GitHubCISnapshot
                             ↓
                Model assigns snapshot to state
                             ↓
                If snapshot.inProgressRunId != nil → subscribe to monitor stream
```

**Implemented Changes:**

### [x] 9.1 Service returns complete status snapshot
- Added `GitHubCISnapshot` type to service (complete, ready-to-display snapshot)
- Added `func getFullStatus() async throws -> GitHubCISnapshot`
- Service handles all queries and transformations
- Date parsing consolidated in service via `parseGitHubDate()`

### [x] 9.2 Simplified GitHubCIModel.refreshStatus()
- Removed transformation logic
- Removed `parseGitHubDate()` helper (now in service)
- Model now just assigns snapshot values to state
- ~25 lines removed from `refreshStatus()`

### [x] 9.3 Moved WorkflowRunInfo to SwiftDeploy
- Moved from `GitHubCIStatus.WorkflowRunInfo` to `SwiftDeploy.WorkflowRunInfo`
- Updated `GitHubCISectionView` to use `WorkflowRunInfo` directly
- UI types now in service layer for reuse

**Benefits Achieved:**
- Model has zero transformation logic
- Date parsing consolidated in service
- Service returns ready-to-display data
- Consistent with CDKInfrastructureModel refactor pattern
- GitHubCIModel reduced from ~120 lines to ~95 lines

---

## 10. Convert BuildState and LambdaState to Structs ✅ COMPLETED

**Status:** Completed

**Problem (solved):**

`BuildState` and `LambdaState` were `@MainActor @Observable` classes that held mutable state. This was unnecessary complexity - they're just data containers that should be owned and mutated by the models.

**Before:**
```swift
// @Observable class with methods
@MainActor
@Observable
public class BuildState {
    public private(set) var outputLines: [String] = []
    public private(set) var status: BuildStatus = .notBuilt

    public func startBuild() { ... }
    public func markSuccess() { ... }
}
```

**After:**
```swift
// Simple struct with mutating methods
public struct BuildState: Equatable, Sendable {
    public var outputLines: [String] = []
    public var status: BuildStatus = .notBuilt

    public mutating func startBuild() { ... }
    public mutating func markSuccess() { ... }
}
```

**Implemented Changes:**

### [x] 10.1 Convert BuildState to struct
- Changed from `@MainActor @Observable class` to `struct`
- All methods now `mutating`
- Added `Equatable, Sendable` conformance
- Removed `private(set)` - fields are now directly mutable

### [x] 10.2 Convert LambdaState to struct
- Same changes as BuildState
- Methods like `startLambda()`, `markRunning()`, `clear()` now `mutating`

### [x] 10.3 Update models to use `var` instead of `let`
- `XcodeLocalModel`: `public var buildState`, `public var lambdaState`
- `LinuxLocalModel`: same changes
- `LambdaBuildService`: `public var buildState`

### [x] 10.4 Update LocalService protocol
- Changed `var buildState: BuildState { get }` to `{ get set }`
- Changed `var lambdaState: LambdaState { get }` to `{ get set }`
- Added `AnyObject` constraint (class-only protocol) for mutation in extensions

### [x] 10.5 Update LocalServicesModel wrapper
- Changed computed properties to get/set that delegate to underlying service

**Benefits Achieved:**
- Simpler data model (structs vs classes)
- Models own their state directly
- No `@Observable` overhead for simple data containers
- `Sendable` conformance for actor isolation
- Clearer ownership semantics
