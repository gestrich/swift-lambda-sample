# Linux Service to Workflow Migration

**Status:** Complete (Phase 14 Complete)
**Created:** 2025-12-18
**Related:** [workflow-role-exploration.md](workflow-role-exploration.md), [workflow-protocol.md](workflow-protocol.md)

## Problem Statement

`LinuxLocalDevelopmentService` (687 lines) has become a massive service that contains all the logic, while the associated workflows are thin pass-through layers that just add `AsyncThrowingStream` boilerplate. This is the opposite of the intended architecture where workflows contain the coordination logic.

### Current Architecture (Problematic)

```
LinuxBuildWorkflow (thin) → LinuxLocalDevelopmentService.build() (has the logic)
LinuxStartLambdaWorkflow (thin) → LinuxLocalDevelopmentService.startLambda() (has the logic)
LinuxTestWorkflow (thin) → LinuxLocalDevelopmentService.testLambda() (has the logic)
... etc
```

### Target Architecture (Like DestroyWorkflow)

```
LinuxBuildWorkflow (has the logic) → DockerClient, CLIClient (SDKs)
LinuxStartLambdaWorkflow (has the logic) → DockerClient, PostgreSQLClient, MinIOClient (SDKs)
LinuxTestWorkflow (has the logic) → APIClient (SDK)
```

### Reference: DestroyWorkflow Pattern

`DestroyWorkflow` demonstrates the correct pattern:
- Directly uses SDK clients (`CDKClient`, `CloudFormationClient`)
- Contains the orchestration logic within `runWorkflow()`
- No intermediate service layer
- Has a `Components` struct and `create()` factory for dependency setup

---

## Goals

1. **Move logic from LinuxLocalDevelopmentService into workflows**
2. **Workflows should directly use SDK clients** (DockerClient, PostgreSQLClient, MinIOClient, etc.)
3. **Eliminate LinuxLocalDevelopmentService entirely** or reduce to just shared types/configuration
4. **Preserve all existing functionality** and streaming behavior
5. **Follow the DestroyWorkflow pattern** with `Components` and `create()` factories

---

## Inventory: LinuxLocalDevelopmentService Methods

| Method | Lines | Target Workflow | SDK Dependencies |
|--------|-------|-----------------|------------------|
| `startAllServices()` | ~20 | LinuxStartServicesWorkflow | PostgreSQLClient, MinIOClient, DynamoDBClient |
| `stopAllServices()` | ~5 | LinuxStopServicesWorkflow | PostgreSQLClient, MinIOClient, DynamoDBClient |
| `startS3()` | ~3 | LinuxStartServicesWorkflow | MinIOClient |
| `createBucket()` | ~3 | LinuxStartServicesWorkflow | MinIOClient |
| `stopS3()` | ~3 | LinuxStopServicesWorkflow | MinIOClient |
| `startDatabase()` | ~3 | LinuxStartServicesWorkflow | PostgreSQLClient |
| `stopDatabase()` | ~3 | LinuxStopServicesWorkflow | PostgreSQLClient |
| `startDynamoDB()` | ~3 | LinuxStartServicesWorkflow | DynamoDBClient |
| `stopDynamoDB()` | ~3 | LinuxStopServicesWorkflow | DynamoDBClient |
| `build()` | ~45 | LinuxBuildWorkflow | CLIClient, DockerClient |
| `isLambdaBuilt()` | ~5 | LinuxBuildWorkflow | FileManager |
| `deleteBuild()` | ~8 | LinuxBuildWorkflow | CLIClient |
| `startLambda()` | ~15 | LinuxStartLambdaWorkflow | DockerClient |
| `stopLambda()` | ~15 | LinuxStopLambdaWorkflow | DockerClient |
| `startWithServices()` | ~30 | LinuxStartAllWorkflow | (composite) |
| `stopWithServices()` | ~15 | LinuxStopAllWorkflow | (composite) |
| `waitForReady()` | ~40 | LinuxStartLambdaWorkflow | DockerClient, CLIClient |
| `testLambda()` | ~15 | LinuxTestWorkflow | APIClient |
| `status()` | ~15 | LinuxStatusWorkflow | DockerClient, MinIOClient, PostgreSQLClient, DynamoDBClient |
| `isRunning()` | ~3 | (shared utility) | DockerClient |
| `setupDockerNetwork()` | ~15 | LinuxSetupNetworkWorkflow | DockerClient |
| `printRunCommand()` | ~25 | LinuxRunInteractiveWorkflow | - |
| `runInteractive()` | ~25 | LinuxRunInteractiveWorkflow | DockerClient |
| `copyConfig()` | ~25 | LinuxCopyConfigWorkflow | FileManager, LocalStorageService |
| `ensureDockerRunning()` | ~5 | (shared utility) | DockerClient |
| `startDockerDesktop()` | ~25 | (shared utility) | CLIClient |
| `startDetached()` | ~30 | LinuxStartLambdaWorkflow | DockerClient |
| `getEnvironmentVariables()` | ~10 | (shared utility) | - |
| `connectContainerToNetwork()` | ~25 | LinuxSetupNetworkWorkflow | DockerClient |
| `performLocalLambdaTests()` | ~55 | LinuxTestWorkflow | APIClient |

---

## What Remains in Service Layer

After migration, the following should remain in `DeployLocalService` (or a new models module):

### Shared Types (Keep)
- `LocalServiceType` enum
- `LambdaExecutionContext` enum
- `createEnvironmentVariables()` function
- Storage keys (PostgreSQLLinuxStorageKey, MinIOLinuxStorageKey, etc.)
- `DeploymentStatus` struct
- `LinuxContainerConfig` struct

### Shared Utilities (Consider: Keep in service or extract)
- `ensureDockerRunning()` - could become a DockerClient extension or stay shared
- `getEnvironmentVariables()` - uses `createEnvironmentVariables()` from shared types

---

## Migration Phases

### [x] Phase 1: Prepare Shared Types Module

Extract types that workflows will need to share.

**Status:** Completed 2025-12-18

**Tasks:**
- [x] 1.1: Create `Sources/features/DeployLocalLinuxFeature/models/` directory
- [x] 1.2: Move `LinuxContainerConfig` to models
- [x] 1.3: Ensure `DeployLocalService` exports remain available (`LocalServiceType`, `LambdaExecutionContext`, etc.)

**Files created/modified:**
- Created: `DeployLocalLinuxFeature/models/LinuxContainerConfig.swift`
- Modified: `DeployLocalLinuxFeature/services/LinuxLocalDevelopmentService.swift` (removed duplicate struct)

**Technical Notes:**
- `LinuxContainerConfig` is now a public struct with public initializer
- All files in the same target (`DeployLocalLinuxFeature`) can access it without import
- Shared types from `DeployLocalService` (`LocalServiceType`, `LambdaExecutionContext`, storage keys) remain accessible via existing target dependency

---

### [x] Phase 2: Migrate LinuxBuildWorkflow

Move build logic directly into the workflow.

**Status:** Completed 2025-12-18

**Tasks:**
- [x] 2.1: Add SDK dependencies to LinuxBuildWorkflow (`CLIClient`, `DockerClient`)
- [x] 2.2: Create `Components` struct and `create()` factory
- [x] 2.3: Move `build()` logic into workflow's `runWorkflow()`
- [x] 2.4: Move `isLambdaBuilt()` logic (simple FileManager check)
- [x] 2.5: Move `deleteBuild()` logic
- [x] 2.6: Update CLI command to use `LinuxBuildWorkflow.create()`
- [x] 2.7: Update MacApp model to use `LinuxBuildWorkflow.create()`
- [x] 2.8: Service methods kept for now (other workflows still depend on them)

**Files modified:**
- `DeployLocalLinuxFeature/workflows/LinuxBuildWorkflow.swift` - Complete rewrite with SDK clients
- `CLIApp/Commands/LocalCommand.swift` - Updated to use `LinuxBuildWorkflow.create()`
- `MacApp/Models/LinuxLocalModel.swift` - Updated to use `LinuxBuildWorkflow.create()`

**Technical Notes:**
- Workflow now owns all build logic including Docker startup, clean, and build streaming
- `Components` struct pattern matches `DestroyWorkflow` for consistency
- `isLambdaBuilt()` and `deleteBuild()` moved to workflow as instance methods
- Service methods (`build()`, `isLambdaBuilt()`, `deleteBuild()`) kept in `LinuxLocalDevelopmentService` because `LinuxStartLambdaWorkflow` and `LinuxRunInteractiveWorkflow` still depend on them - will be removed in Phases 6 and 13
- Removed `DeployLocalService` import (no longer needed by LinuxBuildWorkflow)
- Added `DockerCLISDK`, `LambdaBuildService`, `DeployCoreService` imports for SDK access

---

### [x] Phase 3: Migrate LinuxStartServicesWorkflow

Move service start logic directly into the workflow.

**Status:** Completed 2025-12-18

**Current:** Workflow calls `service.startDatabase()`, `service.startS3()`, etc.
**Target:** Workflow directly uses `PostgreSQLClient`, `MinIOClient`, `DynamoDBClient`

**Tasks:**
- [x] 3.1: Add SDK dependencies (`PostgreSQLClient`, `MinIOClient`, `DynamoDBClient`, `DockerClient`, `LocalStorageService`)
- [x] 3.2: Create `Components` struct and `create()` factory
- [x] 3.3: Move `ensureDockerRunning()` / `startDockerDesktop()` logic
- [x] 3.4: Move service start logic into workflow
- [x] 3.5: Move `createBucket()` logic
- [x] 3.6: Update CLI command to use workflow factory
- [x] 3.7: Service methods kept for now (LinuxStartAllWorkflow still depends on them)

**Files modified:**
- `DeployLocalLinuxFeature/workflows/LinuxStartServicesWorkflow.swift` - Complete rewrite with SDK clients
- `CLIApp/Commands/LocalCommand.swift` - Updated `StartDatabaseCommand`, `StartDynamoDBCommand`, `StartS3Command` to use factory

**Technical Notes:**
- Workflow now owns all service start logic including Docker startup and bucket creation
- `Components` struct pattern matches `LinuxBuildWorkflow` and `DestroyWorkflow` for consistency
- Added deprecated `init(service:)` for backward compatibility with `LinuxStartAllWorkflow` - will be removed in Phase 8
- The deprecated initializer ignores the service parameter and creates its own clients
- Service methods (`startDatabase()`, `startS3()`, `startDynamoDB()`, `createBucket()`) kept in `LinuxLocalDevelopmentService` for other workflows - will be removed when all dependent workflows are migrated
- Build produces expected deprecation warning for `LinuxStartAllWorkflow` usage

---

### [x] Phase 4: Migrate LinuxStopServicesWorkflow

Move service stop logic directly into the workflow.

**Status:** Completed 2025-12-18

**Tasks:**
- [x] 4.1: Add SDK dependencies (`PostgreSQLClient`, `MinIOClient`, `DynamoDBClient`)
- [x] 4.2: Create `Components` struct and `create()` factory
- [x] 4.3: Move stop logic into workflow
- [x] 4.4: Update CLI commands (`StopDatabaseCommand`, `StopDynamoDBCommand`, `StopS3Command`)
- [x] 4.5: Service methods kept for now (LinuxStopAllWorkflow still depends on them)

**Files modified:**
- `DeployLocalLinuxFeature/workflows/LinuxStopServicesWorkflow.swift` - Complete rewrite with SDK clients
- `CLIApp/Commands/LocalCommand.swift` - Updated stop commands to use factory

**Technical Notes:**
- Workflow now owns all service stop logic using SDK clients directly
- `Components` struct pattern matches `LinuxStartServicesWorkflow` and `DestroyWorkflow` for consistency
- Added deprecated `init(service:)` for backward compatibility with `LinuxStopAllWorkflow` - will be removed in Phase 9
- The deprecated initializer ignores the service parameter and creates its own clients
- Service methods (`stopDatabase()`, `stopS3()`, `stopDynamoDB()`) kept in `LinuxLocalDevelopmentService` for other workflows - will be removed when all dependent workflows are migrated
- Build produces expected deprecation warning for `LinuxStopAllWorkflow` usage

---

### [x] Phase 5: Migrate LinuxSetupNetworkWorkflow

Move Docker network setup logic into the workflow.

**Status:** Completed 2025-12-18

**Tasks:**
- [x] 5.1: Add `DockerClient` dependency
- [x] 5.2: Create `Components` struct and `create()` factory
- [x] 5.3: Move `setupDockerNetwork()` logic
- [x] 5.4: Move `connectContainerToNetwork()` logic
- [x] 5.5: Update CLI command to use `LinuxSetupNetworkWorkflow.create()`
- [x] 5.6: Service methods kept for now (LinuxStartAllWorkflow still depends on them)

**Files modified:**
- `DeployLocalLinuxFeature/workflows/LinuxSetupNetworkWorkflow.swift` - Complete rewrite with SDK clients
- `CLIApp/Commands/LocalCommand.swift` - Updated `SetupNetworkCommand` to use factory and improved progress printing

**Technical Notes:**
- Workflow now owns all network setup logic using `DockerClient` directly
- `Components` struct pattern matches other migrated workflows for consistency
- Added deprecated `init(service:)` for backward compatibility with `LinuxStartAllWorkflow` - will be removed in Phase 8
- Container names obtained from SDK config enums: `PostgreSQLConfig.linux.containerName`, `MinIOConfig.linux.containerName`, `DynamoDBLocalConfig.linux.containerName`
- Added `containerSkipped` detail case to report when containers are not running during network setup
- Service methods (`setupDockerNetwork()`, `connectContainerToNetwork()`) kept in `LinuxLocalDevelopmentService` - will be removed when all dependent workflows are migrated
- Build produces expected deprecation warning for `LinuxStartAllWorkflow` and `MacApp` usage

---

### [x] Phase 6: Migrate LinuxStartLambdaWorkflow

Move Lambda container start logic into the workflow.

**Status:** Completed 2025-12-18

**Tasks:**
- [x] 6.1: Add SDK dependencies (`DockerClient`, `CLIClient`, `PostgreSQLClient`, `MinIOClient`, `DynamoDBClient`)
- [x] 6.2: Create `Components` struct and `create()` factory
- [x] 6.3: Move `startLambda()` / `startDetached()` logic
- [x] 6.4: Move `waitForReady()` logic
- [x] 6.5: Move `getEnvironmentVariables()` logic (uses shared `createEnvironmentVariables` from DeployLocalService)
- [x] 6.6: Update CLI command to use `LinuxStartLambdaWorkflow.create()`
- [x] 6.7: Update MacApp model to use `LinuxStartLambdaWorkflow.create()`
- [x] 6.8: Service methods kept for now (LinuxStartAllWorkflow still depends on them via deprecated initializer)

**Files modified:**
- `DeployLocalLinuxFeature/workflows/LinuxStartLambdaWorkflow.swift` - Complete rewrite with SDK clients
- `CLIApp/Commands/LocalCommand.swift` - Updated `StartCommand` to use factory
- `MacApp/Models/LinuxLocalModel.swift` - Updated `startLambda()` to use factory

**Technical Notes:**
- Workflow now owns all Lambda start logic including Docker startup, build check, container start, and readiness wait
- `Components` struct includes `port` for consumers that need the configured port number
- Added deprecated `init(service:)` for backward compatibility with `LinuxStartAllWorkflow` - will be removed in Phase 8
- The deprecated initializer ignores the service parameter and creates its own clients
- Uses `createEnvironmentVariables()` from `DeployLocalService` for environment variable generation
- When Lambda is not built, delegates to `LinuxBuildWorkflow` to build first
- Service methods (`startLambda()`, `startDetached()`, `waitForReady()`, `getEnvironmentVariables()`) kept in `LinuxLocalDevelopmentService` for other workflows - will be removed when all dependent workflows are migrated
- Build produces expected deprecation warnings for `LinuxStartAllWorkflow` and `MacApp` usage of other workflows

---

### [x] Phase 7: Migrate LinuxStopLambdaWorkflow

Move Lambda container stop logic into the workflow.

**Status:** Completed 2025-12-18

**Tasks:**
- [x] 7.1: Add `DockerClient` dependency
- [x] 7.2: Create `Components` struct and `create()` factory
- [x] 7.3: Move `stopLambda()` and `isRunning()` logic
- [x] 7.4: Update CLI command to use `LinuxStopLambdaWorkflow.create()`
- [x] 7.5: Update MacApp model to use `LinuxStopLambdaWorkflow.create()`
- [x] 7.6: Service methods kept for now (LinuxStopAllWorkflow still depends on them via deprecated initializer)

**Files modified:**
- `DeployLocalLinuxFeature/workflows/LinuxStopLambdaWorkflow.swift` - Complete rewrite with SDK clients
- `CLIApp/Commands/LocalCommand.swift` - Updated `StopCommand` to use factory
- `MacApp/Models/LinuxLocalModel.swift` - Updated `stopLambda()` to use factory

**Technical Notes:**
- Workflow now owns all Lambda stop logic using `DockerClient` directly
- `Components` struct pattern matches other migrated workflows for consistency
- Added deprecated `init(service:)` for backward compatibility with `LinuxStopAllWorkflow` - will be removed in Phase 9
- The deprecated initializer ignores the service parameter and creates its own clients
- Removed `DeployLocalService` import (no longer needed by LinuxStopLambdaWorkflow)
- Service methods (`stopLambda()`, `isRunning()`) kept in `LinuxLocalDevelopmentService` for other workflows - will be removed when all dependent workflows are migrated
- Build produces expected deprecation warning for `LinuxStopAllWorkflow` usage

---

### [x] Phase 8: Migrate LinuxStartAllWorkflow

This workflow orchestrates other workflows. Removed direct service dependency.

**Status:** Completed 2025-12-18

**Tasks:**
- [x] 8.1: Remove `service` dependency (now only uses other workflows)
- [x] 8.2: Create `Components` struct and `create()` factory method
- [x] 8.3: Update to use workflow factories for sub-workflows
- [x] 8.4: Update CLI command (`StartAllCommand`) to use factory
- [x] 8.5: Update MacApp model (`startWithServices()`) to use factory
- [x] 8.6: Remove `waitingForReady` step from State (now handled by `LinuxStartLambdaWorkflow`)

**Files modified:**
- `DeployLocalLinuxFeature/workflows/LinuxStartAllWorkflow.swift` - Complete rewrite using workflow factories
- `CLIApp/Commands/LocalCommand.swift` - Updated `StartAllCommand` to use factory, removed `waitingForReady` case from print function
- `MacApp/Models/LinuxLocalModel.swift` - Updated `startWithServices()` to use factory

**Technical Notes:**
- Workflow no longer has a `service` dependency - only orchestrates other workflows
- Uses `LinuxStartServicesWorkflow.create()`, `LinuxSetupNetworkWorkflow.create()`, and `LinuxStartLambdaWorkflow.create()` factories
- Removed `waitingForReady` step since `LinuxStartLambdaWorkflow` already handles readiness check internally
- `Components` struct exposes `port` from `LinuxContainerConfig` for consumers that need it
- Deprecated initializers can now be removed from `LinuxStartServicesWorkflow`, `LinuxSetupNetworkWorkflow`, and `LinuxStartLambdaWorkflow` (was kept for this workflow)
- MacApp still uses deprecated `LinuxSetupNetworkWorkflow(service:)` in `setupDockerNetwork()` - will be addressed when that method is migrated

---

### [x] Phase 9: Migrate LinuxStopAllWorkflow

This workflow orchestrates other workflows. Removed direct service dependency.

**Status:** Completed 2025-12-18

**Tasks:**
- [x] 9.1: Remove `service` dependency (now only uses other workflows)
- [x] 9.2: Create `Components` struct and `create()` factory method
- [x] 9.3: Update to use workflow factories for sub-workflows
- [x] 9.4: Update CLI command (`StopAllCommand`) to use factory
- [x] 9.5: Update MacApp model (`stopWithServices()`) to use factory
- [x] 9.6: Remove deprecated initializers from `LinuxStopLambdaWorkflow` and `LinuxStopServicesWorkflow`

**Files modified:**
- `DeployLocalLinuxFeature/workflows/LinuxStopAllWorkflow.swift` - Complete rewrite using workflow factories
- `DeployLocalLinuxFeature/workflows/LinuxStopLambdaWorkflow.swift` - Removed deprecated `init(service:)`
- `DeployLocalLinuxFeature/workflows/LinuxStopServicesWorkflow.swift` - Removed deprecated `init(service:)`
- `CLIApp/Commands/LocalCommand.swift` - Updated `StopAllCommand` to use factory
- `MacApp/Models/LinuxLocalModel.swift` - Updated `stopWithServices()` to use factory

**Technical Notes:**
- Workflow no longer has a `service` dependency - only orchestrates other workflows
- Uses `LinuxStopLambdaWorkflow.create()` and `LinuxStopServicesWorkflow.create()` factories
- `Components` struct pattern matches `LinuxStartAllWorkflow` for consistency
- Removed `DeployLocalService` import from `LinuxStopAllWorkflow` (no longer needed)
- Deprecated initializers removed from `LinuxStopLambdaWorkflow` and `LinuxStopServicesWorkflow` (no longer needed)
- MacApp still uses deprecated `LinuxSetupNetworkWorkflow(service:)` in `setupDockerNetwork()` - will be addressed when that method is migrated

---

### [x] Phase 10: Migrate LinuxTestWorkflow

Move test logic directly into the workflow.

**Status:** Completed 2025-12-18

**Tasks:**
- [x] 10.1: Add `DockerClient` dependency for `isRunning()` check
- [x] 10.2: Create `Components` struct and `create()` factory
- [x] 10.3: Move `performLocalLambdaTests()` logic using `APIClient` from ClientService
- [x] 10.4: Move `isRunning()` check logic using `DockerClient`
- [x] 10.5: Update CLI command (`TestCommand`) to use factory
- [x] 10.6: Service methods kept for now (LinuxStatusWorkflow still depends on `isRunning()` and `testLambda()`)

**Files modified:**
- `DeployLocalLinuxFeature/workflows/LinuxTestWorkflow.swift` - Complete rewrite with SDK clients
- `CLIApp/Commands/LocalCommand.swift` - Updated `TestCommand` to use factory

**Technical Notes:**
- Workflow now owns all test logic using `DockerClient` (for container status) and `APIClient` (for endpoint testing)
- `Components` struct exposes `port` from `LinuxContainerConfig` for consumers that need it
- When Lambda is not running, delegates to `LinuxStartLambdaWorkflow.create()` to start it first
- `APIClient` is created on MainActor due to its `@MainActor` annotation
- Removed `DeployLocalService` import (no longer needed by LinuxTestWorkflow)
- Service methods (`testLambda()`, `performLocalLambdaTests()`, `isRunning()`) kept in `LinuxLocalDevelopmentService` for other workflows - will be removed when all dependent workflows are migrated
- MacApp still uses deprecated `LinuxSetupNetworkWorkflow(service:)` in `setupDockerNetwork()` - will be addressed when that method is migrated

---

### [x] Phase 11: Migrate LinuxStatusWorkflow

Move status checking logic into the workflow.

**Status:** Completed 2025-12-18

**Tasks:**
- [x] 11.1: Add SDK dependencies (`DockerClient`, `PostgreSQLClient`, `MinIOClient`, `DynamoDBClient`)
- [x] 11.2: Create `Components` struct and `create()` factory
- [x] 11.3: Move `status()` logic (checking Lambda, S3, PostgreSQL, DynamoDB status)
- [x] 11.4: Update CLI command (`StatusCommand`) to use factory
- [x] 11.5: Update MacApp model (`status()`) to use factory
- [x] 11.6: Service methods kept for now (other workflows may still depend on them)

**Files modified:**
- `DeployLocalLinuxFeature/workflows/LinuxStatusWorkflow.swift` - Complete rewrite with SDK clients
- `CLIApp/Commands/LocalCommand.swift` - Updated `StatusCommand` to use factory
- `MacApp/Models/LinuxLocalModel.swift` - Updated `status()` to use factory

**Technical Notes:**
- Workflow now owns all status checking logic using SDK clients directly (`DockerClient`, `PostgreSQLClient`, `MinIOClient`, `DynamoDBClient`)
- `Components` struct pattern matches other migrated workflows for consistency
- Status checks are performed sequentially with progress updates for each service
- The workflow yields intermediate status details (`.lambdaStatus`, `.serviceStatus`) in addition to the final `.status` result
- Removed `DeployLocalService` import for service dependency (now uses SDK clients directly)
- Service method (`status()`) in `LinuxLocalDevelopmentService` can now be removed since no workflows depend on it
- MacApp still uses deprecated `LinuxSetupNetworkWorkflow(service:)` in `setupDockerNetwork()` - will be addressed when that method is migrated

---

### [x] Phase 12: Migrate LinuxCopyConfigWorkflow

Move config copy logic into the workflow.

**Status:** Completed 2025-12-18

**Tasks:**
- [x] 12.1: Add `LocalStorageService` dependency
- [x] 12.2: Create `Components` struct and `create()` factory
- [x] 12.3: Move `copyConfig()` logic
- [x] 12.4: Update CLI command (`CopyConfigCommand`) to use factory
- [x] 12.5: Service method kept for now (LinuxRunInteractiveWorkflow may still depend on it)

**Files modified:**
- `DeployLocalLinuxFeature/workflows/LinuxCopyConfigWorkflow.swift` - Complete rewrite with LocalStorageService
- `CLIApp/Commands/LocalCommand.swift` - Updated `CopyConfigCommand` to use factory

**Technical Notes:**
- Workflow now owns all config copy logic using `LocalStorageService` directly
- `Components` struct pattern matches other migrated workflows for consistency
- Uses `FileManager.default` inside the async method rather than storing it as a property (to maintain Sendable conformance)
- Source path defaults to `{workingDirectory}/{AppConfigFileKey.filename}` when not provided
- Removed `DeployLocalService` import for service dependency (now uses `LocalStorageService` and `AppConfigFileKey` from DeployLocalService)
- Service method (`copyConfig()`) in `LinuxLocalDevelopmentService` can be removed once all dependent workflows are migrated
- MacApp's deprecated initializer usage was fixed in Phase 13

---

### [x] Phase 13: Migrate LinuxRunInteractiveWorkflow

Move interactive container logic into the workflow.

**Status:** Completed 2025-12-18

**Tasks:**
- [x] 13.1: Add SDK dependencies (`DockerClient`, `PostgreSQLClient`, `MinIOClient`, `DynamoDBClient`)
- [x] 13.2: Create `Components` struct and `create()` factory
- [x] 13.3: Move `runInteractive()` logic
- [x] 13.4: Move `printRunCommand()` logic (now returns `String` instead of printing)
- [x] 13.5: Update CLI command (`RunInteractiveCommand`) to use factory
- [x] 13.6: Update MacApp model (`runInteractive()`) to use factory
- [x] 13.7: Remove deprecated initializers from `LinuxSetupNetworkWorkflow`, `LinuxStartServicesWorkflow`, and `LinuxStartLambdaWorkflow`
- [x] 13.8: Update MacApp `setupDockerNetwork()` to use factory

**Files modified:**
- `DeployLocalLinuxFeature/workflows/LinuxRunInteractiveWorkflow.swift` - Complete rewrite with SDK clients
- `DeployLocalLinuxFeature/workflows/LinuxSetupNetworkWorkflow.swift` - Removed deprecated `init(service:)`
- `DeployLocalLinuxFeature/workflows/LinuxStartServicesWorkflow.swift` - Removed deprecated `init(service:)`
- `DeployLocalLinuxFeature/workflows/LinuxStartLambdaWorkflow.swift` - Removed deprecated `init(service:)`
- `CLIApp/Commands/LocalCommand.swift` - Updated `RunInteractiveCommand` to use factory
- `MacApp/Models/LinuxLocalModel.swift` - Updated `runInteractive()` and `setupDockerNetwork()` to use factories

**Technical Notes:**
- Workflow now owns all interactive container logic using SDK clients directly
- `Components` struct pattern matches other migrated workflows for consistency
- Requires `PostgreSQLClient`, `MinIOClient`, and `DynamoDBClient` to generate environment variables via `createEnvironmentVariables()` from `DeployLocalService`
- `printRunCommand()` changed from `void` (printing) to returning `String` for better composability
- When Lambda is not built, delegates to `LinuxBuildWorkflow.create()` to build first
- Removed all deprecated `init(service:)` initializers since MacApp now uses factories
- Service methods (`runInteractive()`, `printRunCommand()`) remain in `LinuxLocalDevelopmentService` but are no longer used by any workflow

---

### [x] Phase 14: Delete LinuxLocalDevelopmentService

After all logic has been migrated.

**Status:** Completed 2025-12-18

**Tasks:**
- [x] 14.1: Verify no remaining references to `LinuxLocalDevelopmentService`
- [x] 14.2: Delete `LinuxLocalDevelopmentService.swift`
- [x] 14.3: Update Package.swift if needed (not needed - file was just removed)
- [x] 14.4: Ensure shared types in `DeployLocalService` are still accessible

**Files modified:**
- `MacApp/Models/LinuxLocalModel.swift` - Updated to use SDK clients directly and workflow factories
- `Tests/DeployRemoteFeatureTests/LinuxDeployTests.swift` - Updated to use workflow factories
- Deleted: `DeployLocalLinuxFeature/services/LinuxLocalDevelopmentService.swift`

**Technical Notes:**
- `LinuxLocalModel` now creates SDK clients directly (`DockerClient`, `PostgreSQLClient`, `MinIOClient`, `DynamoDBClient`)
- Service management methods now use `LinuxStartServicesWorkflow` and `LinuxStopServicesWorkflow` factories with options
- `createBucket()` uses `MinIOClient` directly since it's already available
- `waitForReady()` now implemented directly using `DockerClient` and `CLIClient`
- `testLambda()` now uses `LinuxTestWorkflow` factory
- `deleteBuild()` uses `LinuxBuildWorkflow` factory's `deleteBuild()` method
- Tests updated to use workflow factories instead of service methods
- Port configuration now comes from `LinuxContainerConfig` instead of hardcoded value
- Build verified to succeed with no compilation errors

---

### [ ] Phase 15: Final Cleanup

**Tasks:**
- [ ] 15.1: Remove `DeployLocalService` import from workflows that no longer need it
- [ ] 15.2: Verify all CLI commands work correctly
- [ ] 15.3: Run all tests
- [ ] 15.4: Update documentation

---

## Example: Migrated LinuxBuildWorkflow

```swift
import Foundation
import CLISDK
import DockerCLISDK
import LambdaBuildService
import Uniflow

public struct LinuxBuildWorkflow: StreamingWorkflow {
    private let cliClient: CLIClient
    private let dockerClient: DockerClient
    private let workingDirectory: String

    // Build artifact paths
    private var lambdaDir: String { "\(workingDirectory)/lambda" }
    private var lambdaZipPath: String { "\(workingDirectory)/lambda.zip" }
    private var bootstrapPath: String { "\(lambdaDir)/bootstrap" }
    private var awsSamBuildDir: String { ".aws-sam/build-SwiftLambda" }
    private var buildArtifactPaths: [String] { ["lambda", "lambda.zip", awsSamBuildDir] }

    public struct Components: Sendable {
        public let workflow: LinuxBuildWorkflow
    }

    public static func create(workingDirectory: String) -> Components {
        let cliClient = CLIClient(defaultWorkingDirectory: workingDirectory)
        let dockerClient = DockerClient(cliClient: cliClient)

        let workflow = LinuxBuildWorkflow(
            cliClient: cliClient,
            dockerClient: dockerClient,
            workingDirectory: workingDirectory
        )

        return Components(workflow: workflow)
    }

    // ... State, Options as before ...

    private func runWorkflow(
        options: Options,
        continuation: AsyncThrowingStream<State, Error>.Continuation
    ) async throws {
        // Ensure Docker is running
        if !(await dockerClient.isDockerRunning()) {
            try await startDockerDesktop()
        }

        if options.clean {
            continuation.yield(State(step: .cleaning))
            let rmCmd = Rm(recursive: true, force: true, paths: buildArtifactPaths)
            _ = try await cliClient.execute(rmCmd, workingDirectory: workingDirectory, printCommand: false)
        }

        continuation.yield(State(step: .building))

        let buildCmd = BuildScript.Build.lambda(target: "LambdaApp")
        let stream = await cliClient.stream(buildCmd, workingDirectory: workingDirectory, printCommand: false)

        var exitCode: Int32 = 0
        for await output in stream {
            switch output {
            case .stdout(_, let text), .stderr(_, let text):
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    continuation.yield(State(step: .building, detail: .output(trimmed)))
                }
            case .exit(_, let code):
                exitCode = code
            default:
                break
            }
        }

        if exitCode != 0 {
            throw BuildError.failed(exitCode: exitCode)
        }

        continuation.yield(State(step: .complete, detail: .buildPath(lambdaDir)))
        continuation.finish()
    }

    private func startDockerDesktop() async throws {
        let result = try await cliClient.executeForResult(Open(application: "Docker"), printCommand: false)
        guard result.isSuccess else {
            throw DeployError.commandFailed(command: "open -a Docker", exitCode: result.exitCode, output: "Failed to start Docker Desktop")
        }

        for attempt in 1...60 {
            if await dockerClient.isDockerRunning() { return }
            try await Task.sleep(for: .seconds(1))
        }

        throw DeployError.commandFailed(command: "docker", exitCode: 1, output: "Docker daemon did not become ready")
    }
}
```

---

## Risk Assessment

| Risk | Mitigation |
|------|------------|
| Breaking existing functionality | Run all tests after each phase |
| Missing dependencies in workflows | Carefully track SDK dependencies per method |
| Duplicate code between workflows | Extract shared utilities (e.g., `ensureDockerRunning`) to a helper or SDK extension |
| CLI command changes | Update CLI commands in each phase, verify they work |

---

## Success Criteria

1. `LinuxLocalDevelopmentService.swift` is deleted
2. All 12 workflows contain their own logic (no pass-through)
3. Workflows directly use SDK clients
4. All CLI commands work as before
5. All tests pass
6. No functionality regressions
