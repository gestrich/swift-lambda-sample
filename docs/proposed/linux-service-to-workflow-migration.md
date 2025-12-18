# Linux Service to Workflow Migration

**Status:** In Progress (Phase 2 Complete)
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

### [ ] Phase 3: Migrate LinuxStartServicesWorkflow

Move service start logic directly into the workflow.

**Current:** Workflow calls `service.startDatabase()`, `service.startS3()`, etc.
**Target:** Workflow directly uses `PostgreSQLClient`, `MinIOClient`, `DynamoDBClient`

**Tasks:**
- [ ] 3.1: Add SDK dependencies (`PostgreSQLClient`, `MinIOClient`, `DynamoDBClient`, `DockerClient`, `LocalStorageService`)
- [ ] 3.2: Create `Components` struct and `create()` factory
- [ ] 3.3: Move `ensureDockerRunning()` / `startDockerDesktop()` logic (or make DockerClient handle this)
- [ ] 3.4: Move service start logic into workflow
- [ ] 3.5: Move `createBucket()` logic
- [ ] 3.6: Update CLI command to use workflow factory
- [ ] 3.7: Remove unused methods from service

---

### [ ] Phase 4: Migrate LinuxStopServicesWorkflow

Move service stop logic directly into the workflow.

**Tasks:**
- [ ] 4.1: Add SDK dependencies
- [ ] 4.2: Create `Components` struct and `create()` factory
- [ ] 4.3: Move stop logic into workflow
- [ ] 4.4: Update CLI command
- [ ] 4.5: Remove unused methods from service

---

### [ ] Phase 5: Migrate LinuxSetupNetworkWorkflow

Move Docker network setup logic into the workflow.

**Current:** Workflow calls `service.setupDockerNetwork()`
**Target:** Workflow directly uses `DockerClient`

**Tasks:**
- [ ] 5.1: Add `DockerClient` dependency
- [ ] 5.2: Create `Components` struct and `create()` factory
- [ ] 5.3: Move `setupDockerNetwork()` logic
- [ ] 5.4: Move `connectContainerToNetwork()` logic
- [ ] 5.5: Update CLI command
- [ ] 5.6: Remove unused methods from service

---

### [ ] Phase 6: Migrate LinuxStartLambdaWorkflow

Move Lambda container start logic into the workflow.

**Tasks:**
- [ ] 6.1: Add SDK dependencies (`DockerClient`, `CLIClient`)
- [ ] 6.2: Create `Components` struct and `create()` factory
- [ ] 6.3: Move `startLambda()` / `startDetached()` logic
- [ ] 6.4: Move `waitForReady()` logic
- [ ] 6.5: Move `getEnvironmentVariables()` logic (or use shared function)
- [ ] 6.6: Update CLI command
- [ ] 6.7: Remove unused methods from service

---

### [ ] Phase 7: Migrate LinuxStopLambdaWorkflow

Move Lambda container stop logic into the workflow.

**Tasks:**
- [ ] 7.1: Add `DockerClient` dependency
- [ ] 7.2: Create `Components` struct and `create()` factory
- [ ] 7.3: Move `stopLambda()` logic
- [ ] 7.4: Update CLI command
- [ ] 7.5: Remove unused methods from service

---

### [ ] Phase 8: Migrate LinuxStartAllWorkflow

This workflow already orchestrates other workflows. Verify it doesn't need direct service access.

**Tasks:**
- [ ] 8.1: Remove `service` dependency (should only use other workflows)
- [ ] 8.2: Update to use workflow factories for sub-workflows
- [ ] 8.3: Move any remaining direct service calls into child workflows

---

### [ ] Phase 9: Migrate LinuxStopAllWorkflow

**Tasks:**
- [ ] 9.1: Remove `service` dependency
- [ ] 9.2: Update to use workflow factories for sub-workflows

---

### [ ] Phase 10: Migrate LinuxTestWorkflow

Move test logic directly into the workflow.

**Current:** Workflow calls `service.testLambda()`
**Target:** Workflow directly uses `APIClient`

**Tasks:**
- [ ] 10.1: Add `APIClient` dependency (from ClientService)
- [ ] 10.2: Create `Components` struct and `create()` factory
- [ ] 10.3: Move `performLocalLambdaTests()` logic
- [ ] 10.4: Move `isRunning()` check logic
- [ ] 10.5: Update CLI command
- [ ] 10.6: Remove unused methods from service

---

### [ ] Phase 11: Migrate LinuxStatusWorkflow

Move status checking logic into the workflow.

**Tasks:**
- [ ] 11.1: Add SDK dependencies (`DockerClient`, `PostgreSQLClient`, `MinIOClient`, `DynamoDBClient`)
- [ ] 11.2: Create `Components` struct and `create()` factory
- [ ] 11.3: Move `status()` logic
- [ ] 11.4: Update CLI command
- [ ] 11.5: Remove unused methods from service

---

### [ ] Phase 12: Migrate LinuxCopyConfigWorkflow

Move config copy logic into the workflow.

**Tasks:**
- [ ] 12.1: Add `LocalStorageService` dependency
- [ ] 12.2: Create `Components` struct and `create()` factory
- [ ] 12.3: Move `copyConfig()` logic
- [ ] 12.4: Update CLI command
- [ ] 12.5: Remove unused methods from service

---

### [ ] Phase 13: Migrate LinuxRunInteractiveWorkflow

Move interactive container logic into the workflow.

**Tasks:**
- [ ] 13.1: Add `DockerClient` dependency
- [ ] 13.2: Create `Components` struct and `create()` factory
- [ ] 13.3: Move `runInteractive()` logic
- [ ] 13.4: Move `printRunCommand()` logic
- [ ] 13.5: Update CLI command
- [ ] 13.6: Remove unused methods from service

---

### [ ] Phase 14: Delete LinuxLocalDevelopmentService

After all logic has been migrated.

**Tasks:**
- [ ] 14.1: Verify no remaining references to `LinuxLocalDevelopmentService`
- [ ] 14.2: Delete `LinuxLocalDevelopmentService.swift`
- [ ] 14.3: Update Package.swift if needed
- [ ] 14.4: Ensure shared types in `DeployLocalService` are still accessible

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
