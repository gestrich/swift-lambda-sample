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

## 4. LinuxLocalServiceModel

**Current Location:** `Sources/SwiftDeploy/Models/LinuxLocalServiceModel.swift` (~800 lines)

**Analysis:**
- Nearly identical structure to XcodeLocalServiceModel
- Different build process (Docker-based vs native)
- Different Lambda execution (container vs process)

**Refactor Plan:**

### [ ] 4.1 Create LinuxLocalDevelopmentService (high-level facade)
- Location: `Sources/SwiftDeploy/Services/LinuxLocalDevelopmentService.swift`
- Same interface as XcodeLocalDevelopmentService
- Additional methods:
  - `func setupDockerNetwork() async throws`
  - `func runInteractive() async throws`

### [ ] 4.2 Update CLI LocalLinuxCommand to use LinuxLocalDevelopmentService
- Each subcommand: create service, call one method, print result

### [ ] 4.3 Slim down LinuxLocalServiceModel → LinuxLocalModel
- Rename to `LinuxLocalModel` (drop "Service")
- Move to `Sources/MacApp/Models/LinuxLocalModel.swift`
- Same pattern as XcodeLocalModel

### [ ] 4.4 Update MacApp references

### [ ] 4.5 Verify build

---

## 5. Final Cleanup

### [ ] 5.1 Remove empty Models folder from SwiftDeploy
- After all models moved to MacApp

### [ ] 5.2 Update LambdaService protocol
- May need adjustment since Models no longer in SwiftDeploy
- Consider if protocol should move to MacApp or be split

### [ ] 5.3 Update LocalService protocol
- Same consideration as LambdaService

### [ ] 5.4 Final build verification
- `swift build --target MacApp`
- `swift build --target SwiftDeployCLI`

### [ ] 5.5 Update architecture documentation
- Update `docs/architecture/MacAppArchitecture.md` with final structure

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

### Current State (Phase 3 Complete)
```
SwiftDeploy/Services/
├── RemoteDeploymentService.swift       (stateless facade) ✅
├── XcodeLocalDevelopmentService.swift  (stateless facade) ✅
├── LinuxLocalDevelopmentService.swift  (stateless facade) - TODO
├── DependencyCheckerService.swift      (stateless) ✅
└── ... (existing services)

SwiftDeploy/Models/
└── LinuxLocalServiceModel.swift  (state + logic mixed) - TODO

MacApp/Models/
├── RemoteModel.swift           (@Observable state only) ✅
├── XcodeLocalModel.swift       (@Observable state only) ✅
├── LinuxLocalModel.swift       (@Observable state only) - TODO
└── DependencyStatusModel.swift (@Observable state only) ✅

CLI → Service (single call)
MacApp View → Model → Service
```

### After (Target)
```
SwiftDeploy/Services/
├── RemoteDeploymentService.swift       (stateless facade)
├── XcodeLocalDevelopmentService.swift  (stateless facade)
├── LinuxLocalDevelopmentService.swift  (stateless facade)
├── DependencyCheckerService.swift      (stateless)
└── ... (existing services)

MacApp/Models/
├── RemoteModel.swift           (@Observable state only)
├── XcodeLocalModel.swift       (@Observable state only)
├── LinuxLocalModel.swift       (@Observable state only)
└── DependencyStatusModel.swift (@Observable state only)

CLI → Service (single call)
MacApp View → Model → Service
```
