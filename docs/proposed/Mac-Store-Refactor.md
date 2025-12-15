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

## 8. Future: Move Business Logic from CDKInfrastructureModel to Service

**Status:** Proposed

**Problem:**

`CDKInfrastructureModel` currently contains significant business/domain logic that should ideally live in the service layer:

- **Progress polling** (`pollProgressUntilCancelled`, `updateProgressOnce`)
- **Operation monitoring** (`monitorExistingOperation`)
- **Deployment orchestration** (`runDeployWithProgressPolling`)
- **Credential error detection** (`isCredentialError`)

This violates the intended pattern where Models should:
- Hold observable state for UI binding
- Make simple API calls to services
- Transform service responses into UI state

Instead, Models should NOT:
- Contain polling loops
- Orchestrate multi-step operations
- Parse/interpret domain-specific data

**Key Constraint:** Services must remain stateless. They should **return** state, not **hold** state.

**Current Flow:**
```
View → Model.deploy() → [polling logic in Model] → Service.deploy()
                      → [progress tracking in Model]
                      → [error handling in Model]
```

**Target Flow:**
```
View → Model.deploy() → Service.deployWithProgress() → AsyncStream<Progress>
                      ↓
                Model updates state from stream
```

**Proposed Changes:**

### [ ] 8.1 Service returns progress via AsyncStream (stateless)
- Add `func deployWithProgress(...) -> AsyncStream<CDKDeploymentProgress>`
- Add `func destroyWithProgress(...) -> AsyncStream<CDKDeploymentProgress>`
- Service creates a fresh stream per call (no stored state)
- Stream internally polls CloudFormation and yields progress snapshots
- Each yield is a complete state snapshot (not a delta)

```swift
// Service - stateless, returns state via stream
public func deployWithProgress(...) -> AsyncStream<CDKDeploymentProgress> {
    AsyncStream { continuation in
        Task {
            // Start CDK deploy
            try await cdkService.deploy(...)

            // Poll and yield progress (no state stored in service)
            while !Task.isCancelled {
                let events = try await awsService.getStackEvents(...)
                let progress = CDKDeploymentProgress(from: events) // Pure transformation
                continuation.yield(progress)
                try await Task.sleep(for: .seconds(2))
            }
        }
    }
}
```

### [ ] 8.2 Simplify CDKInfrastructureModel
- Remove polling logic entirely
- Subscribe to service's AsyncStream
- Map stream values directly to `@Observable` state
- Model becomes a thin state container

```swift
// Model - holds state, subscribes to service
public func deploy(...) async throws {
    infrastructureStatus.status = .deploying(operation: "Deploying")

    for await progress in queryService.deployWithProgress(...) {
        // Just assign returned state - no business logic
        infrastructureStatus.deploymentProgress = progress
    }

    await refreshStatus()
}
```

### [ ] 8.3 Service returns typed errors (stateless)
- Service throws typed errors: `CDKError.credentialExpired`, `CDKError.stackNotFound`
- Model catches and maps to UI states
- Error classification logic lives in service, not model

```swift
// Service - classifies errors
public func getStackStatus(...) async throws -> StackStatus {
    do {
        return try await awsService.getStackStatus(...)
    } catch let error where isCredentialError(error) {
        throw CDKError.credentialExpired(underlying: error)
    }
}

// Model - maps errors to UI state
do {
    let status = try await queryService.getStackStatus(...)
} catch CDKError.credentialExpired {
    infrastructureStatus.status = .failed(reason: "credentials expired")
}
```

**Benefits:**
- Services remain stateless and fully testable
- Models are trivially simple (state assignment + subscriptions)
- Clear data flow: Service returns state → Model stores state → View observes state
- Consistent pattern across all Model/Service pairs

---

## 9. Future: Simplify GitHubCIModel Business Logic

**Status:** Proposed

**Problem:**

`GitHubCIModel` still contains some business/domain logic that could be moved to `GitHubActionsService`:

- **Status transformation** (`refreshStatus()` - determining if a run is in progress and what to display)
- **Date parsing** (`parseGitHubDate` - converting ISO8601 strings to Date)
- **Auto-monitoring detection** (checking if latest run is incomplete and starting monitor)

While GitHubCIModel is cleaner than CDKInfrastructureModel (monitoring is already via AsyncStream), there's room for further simplification.

**Current Flow:**
```
View → Model.refreshStatus() → [Service.getGitStatus() + Service.getLatestWorkflowRun()]
                             → [Model decides if run is in progress]
                             → [Model transforms WorkflowRun → WorkflowRunInfo]
                             → [Model starts monitoring if needed]
```

**Target Flow:**
```
View → Model.refreshStatus() → Service.getFullStatus() → GitHubCISnapshot
                             ↓
                Model assigns snapshot to state
                             ↓
                If snapshot.inProgressRunId != nil → subscribe to monitor stream
```

**Proposed Changes:**

### [ ] 9.1 Service returns complete status snapshot
- Add `func getFullStatus() async throws -> GitHubCISnapshot`
- Service handles all queries and transformations
- Returns a complete, ready-to-display snapshot

```swift
// Service - returns complete snapshot
public struct GitHubCISnapshot: Sendable {
    public let gitStatus: GitStatus
    public let latestRun: WorkflowRunInfo?
    public let inProgressRunId: String?  // Non-nil if monitoring needed
}

public func getFullStatus() async throws -> GitHubCISnapshot {
    let gitStatus = try await getGitStatus()
    let latestRun = try await getLatestWorkflowRun()

    let runInfo = latestRun.map { run in
        WorkflowRunInfo(
            id: run.id,
            status: run.status,
            conclusion: run.conclusion,
            title: run.displayTitle,
            createdAt: parseGitHubDate(run.createdAt)  // Date parsing in service
        )
    }

    let inProgressId = latestRun?.isCompleted == false ? latestRun?.id : nil

    return GitHubCISnapshot(
        gitStatus: gitStatus,
        latestRun: runInfo,
        inProgressRunId: inProgressId
    )
}
```

### [ ] 9.2 Simplify GitHubCIModel.refreshStatus()
- Remove transformation logic
- Remove date parsing helper
- Just assign snapshot values to state

```swift
// Model - trivially simple
public func refreshStatus() async {
    guard !ciStatus.status.isDeploying else { return }
    ciStatus.status = .loading

    do {
        let snapshot = try await actionsService.getFullStatus()

        ciStatus.hasUnpushedCommits = snapshot.gitStatus.hasUnpushedCommits
        ciStatus.hasUncommittedChanges = snapshot.gitStatus.hasUncommittedChanges
        ciStatus.currentBranch = snapshot.gitStatus.currentBranch

        if let inProgressId = snapshot.inProgressRunId {
            ciStatus.status = .deploying(runId: inProgressId)
            Task { await monitorWorkflowRun(runId: inProgressId) }
        } else {
            ciStatus.status = .idle(lastRun: snapshot.latestRun)
        }
    } catch {
        ciStatus.status = .idle(lastRun: nil)
    }
}
```

### [ ] 9.3 Move WorkflowRunInfo to SwiftDeploy
- Currently defined in MacApp's GitHubCIModel
- Move to SwiftDeploy so service can return it
- Keeps UI types in service layer for reuse

**Benefits:**
- Model has zero transformation logic
- Date parsing consolidated in service
- Service returns ready-to-display data
- Consistent with CDKInfrastructureModel refactor pattern
