# Xcode Service to Workflow Migration

**Status:** In Progress
**Created:** 2025-12-18
**Related:** [linux-service-to-workflow-migration.md](linux-service-to-workflow-migration.md), [workflow-protocol.md](workflow-protocol.md)

## Problem Statement

`XcodeLocalDevelopmentService` (~628 lines) has become a massive service that contains all the logic, while the associated workflows are thin pass-through layers that just add `AsyncThrowingStream` boilerplate. This is the opposite of the intended architecture where workflows contain the coordination logic.

This is the same problem that was solved for `DeployLocalLinuxFeature` in the Linux migration.

### Current Architecture (Problematic)

```
XcodeBuildWorkflow (thin) → XcodeLocalDevelopmentService.build() (has the logic)
XcodeStartLambdaWorkflow (thin) → XcodeLocalDevelopmentService.startLambda() (has the logic)
XcodeTestWorkflow (thin) → XcodeLocalDevelopmentService.testLambda() (has the logic)
... etc
```

### Target Architecture (Like DestroyWorkflow and Linux Workflows)

```
XcodeBuildWorkflow (has the logic) → CLIClient, SwiftCLI (SDKs)
XcodeStartLambdaWorkflow (has the logic) → CLIClient (SDK)
XcodeTestWorkflow (has the logic) → APIClient (ClientService)
```

### Reference: Migrated Linux Workflows

The Linux migration demonstrates the correct pattern:
- Directly uses SDK clients (`DockerClient`, `PostgreSQLClient`, `MinIOClient`, etc.)
- Contains the orchestration logic within `runWorkflow()`
- No intermediate service layer
- Has a `Components` struct and `create()` factory for dependency setup

---

## Goals

1. **Move logic from XcodeLocalDevelopmentService into workflows**
2. **Workflows should directly use SDK clients** (CLIClient, PostgreSQLClient, MinIOClient, DockerClient, etc.)
3. **Eliminate XcodeLocalDevelopmentService entirely** or reduce to just shared types/configuration
4. **Preserve all existing functionality** and streaming behavior
5. **Follow the DestroyWorkflow/Linux workflow pattern** with `Components` and `create()` factories

---

## Inventory: XcodeLocalDevelopmentService Methods

| Method | Lines | Target Workflow | SDK Dependencies |
|--------|-------|-----------------|------------------|
| `startAllServices()` | ~20 | XcodeStartServicesWorkflow | PostgreSQLClient, MinIOClient, DynamoDBClient, DockerClient |
| `stopAllServices()` | ~5 | XcodeStopServicesWorkflow | PostgreSQLClient, MinIOClient, DynamoDBClient |
| `startS3()` | ~3 | XcodeStartServicesWorkflow | MinIOClient, DockerClient |
| `createBucket()` | ~3 | XcodeStartServicesWorkflow | MinIOClient |
| `stopS3()` | ~3 | XcodeStopServicesWorkflow | MinIOClient |
| `startDatabase()` | ~3 | XcodeStartServicesWorkflow | PostgreSQLClient, DockerClient |
| `stopDatabase()` | ~3 | XcodeStopServicesWorkflow | PostgreSQLClient |
| `startDynamoDB()` | ~3 | XcodeStartServicesWorkflow | DynamoDBClient, DockerClient |
| `stopDynamoDB()` | ~3 | XcodeStopServicesWorkflow | DynamoDBClient |
| `build()` | ~45 | XcodeBuildWorkflow | CLIClient (SwiftCLI) |
| `getExecutablePath()` | ~15 | XcodeBuildWorkflow, XcodeStartLambdaWorkflow | CLIClient (SwiftCLI) |
| `isLambdaBuilt()` | ~15 | XcodeBuildWorkflow | FileManager |
| `deleteBuild()` | ~5 | XcodeBuildWorkflow | CLIClient (SwiftCLI) |
| `startLambda()` | ~45 | XcodeStartLambdaWorkflow | CLIClient |
| `stopLambda()` | ~40 | XcodeStopLambdaWorkflow | CLIClient (Kill, Lsof) |
| `startWithServices()` | ~10 | XcodeStartAllWorkflow | (composite) |
| `stopWithServices()` | ~10 | XcodeStopAllWorkflow | (composite) |
| `setupNetworkAndBucket()` | ~20 | XcodeStartAllWorkflow | DockerClient, MinIOClient |
| `waitForReady()` | ~25 | XcodeStartLambdaWorkflow | CLIClient (Lsof) |
| `testLambda()` | ~15 | XcodeTestWorkflow | APIClient |
| `performLocalLambdaTests()` | ~55 | XcodeTestWorkflow | APIClient |
| `status()` | ~15 | XcodeStatusWorkflow | PostgreSQLClient, MinIOClient, DynamoDBClient, CLIClient |
| `isLambdaRunning()` | ~15 | (shared utility) | CLIClient (Lsof) |
| `copyConfig()` | ~25 | XcodeCopyConfigWorkflow | FileManager, LocalStorageService |
| `ensureDockerRunning()` | ~5 | (shared utility) | DockerClient |
| `startDockerDesktop()` | ~30 | (shared utility) | CLIClient |
| `isPortInUse()` | ~5 | (private helper) | CLIClient (Lsof) |
| `getPortInfo()` | ~15 | (private helper) | CLIClient (Lsof) |
| `getProcessIDsOnPort()` | ~20 | (private helper) | CLIClient (Lsof) |
| `getLambdaEnvironmentVariables()` | ~10 | XcodeStartLambdaWorkflow | (uses createEnvironmentVariables from DeployLocalService) |

---

## Key Differences from Linux Migration

| Aspect | Linux | Xcode |
|--------|-------|-------|
| Lambda execution | Docker container | Native macOS process |
| Lambda stop | `docker stop` | `kill` + `lsof` for PID lookup |
| Lambda status check | `docker ps` | `lsof` port check |
| Build | Docker-based (`build.sh`) | Native `swift build` |
| Network setup | Docker network required | Optional (MinIO network) |
| Interactive mode | Docker run interactive | N/A |

---

## What Remains in Service Layer

After migration, the following should remain in `DeployLocalService` (or stay accessible):

### Shared Types (Keep in DeployLocalService)
- `LocalServiceType` enum
- `LambdaExecutionContext` enum (`.xcode` vs `.linux`)
- `createEnvironmentVariables()` function
- Storage keys (`PostgreSQLXcodeStorageKey`, `MinIOXcodeStorageKey`, `DynamoDBLocalXcodeStorageKey`)
- `DeploymentStatus` struct
- `ServiceState` enum
- `AppConfigFileKey`

### SDK Client Configuration (Keep in respective SDKs)
- `PostgreSQLConfig.xcode` - PostgreSQL configuration for Xcode mode
- `MinIOConfig.xcode` - MinIO configuration for Xcode mode
- `DynamoDBLocalConfig.xcode` - DynamoDB Local configuration for Xcode mode

---

## Migration Phases

### [x] Phase 1: Prepare Shared Utilities (COMPLETED)

Extract utilities that multiple workflows will need.

**Tasks:**
- [x] 1.1: Create `Sources/features/DeployLocalXcodeFeature/models/` directory (if needed) - Not needed
- [x] 1.2: Identify any Xcode-specific types to extract (currently none identified) - None needed
- [x] 1.3: Verify `DeployLocalService` exports are accessible (`LocalServiceType`, `createEnvironmentVariables`, storage keys, etc.)

**Files to create/modify:**
- Verify Package.swift dependencies are correct

**Technical Notes:**
- Unlike Linux, Xcode feature doesn't need `LinuxContainerConfig` equivalent since Lambda runs as native process
- Port configuration (8080) can be a constant in the workflow or extracted to a shared config
- All shared types verified accessible: `LocalServiceType`, `LambdaExecutionContext`, `createEnvironmentVariables()`, storage keys in `DeployLocalService`; `DeploymentStatus`, `ServiceState` in `DeployCoreService`

---

### [x] Phase 2: Migrate XcodeBuildWorkflow (COMPLETED)

Move build logic directly into the workflow.

**Current:** Workflow calls `service.build()`, `service.getExecutablePath()`
**Target:** Workflow directly uses `CLIClient` with `SwiftCLI.Build` commands

**Tasks:**
- [x] 2.1: Add SDK dependencies to XcodeBuildWorkflow (`CLIClient`)
- [x] 2.2: Create `Components` struct and `create()` factory
- [x] 2.3: Move `build()` logic into workflow's `runWorkflow()`
- [x] 2.4: Move `getExecutablePath()` logic (simple `swift build --show-bin-path`)
- [x] 2.5: Move `isLambdaBuilt()` logic (FileManager check)
- [x] 2.6: Move `deleteBuild()` logic (`swift package clean`)
- [x] 2.7: Update CLI command to use `XcodeBuildWorkflow.create()`
- [x] 2.8: Update MacApp model to use `XcodeBuildWorkflow.create()`
- [x] 2.9: Service methods kept for now (other workflows still depend on them)

**Files modified:**
- `DeployLocalXcodeFeature/workflows/XcodeBuildWorkflow.swift` - Added `Components`, `create()`, moved all build logic
- `CLIApp/Commands/LocalCommand.swift` - Updated `BuildCommand` to use factory
- `MacApp/Models/XcodeLocalModel.swift` - Updated `build()` to use factory
- `Package.swift` - Added `DeployCoreService` and `LambdaBuildService` dependencies to `DeployLocalXcodeFeature`

**Technical Notes:**
- Workflow now contains all build logic directly using `CLIClient` and `SwiftCLI.Build` commands
- Added public helper methods: `getExecutablePath()`, `isLambdaBuilt()`, `deleteBuild()`
- Service build methods still exist but are no longer called by the workflow
- Build streams output directly through continuation for real-time feedback

---

### [x] Phase 3: Migrate XcodeStartServicesWorkflow (COMPLETED)

Move service start logic directly into the workflow.

**Current:** Workflow calls `service.startDatabase()`, `service.startS3()`, etc.
**Target:** Workflow directly uses `PostgreSQLClient`, `MinIOClient`, `DynamoDBClient`

**Tasks:**
- [x] 3.1: Add SDK dependencies (`PostgreSQLClient`, `MinIOClient`, `DynamoDBClient`, `DockerClient`, `LocalStorageService`)
- [x] 3.2: Create `Components` struct and `create()` factory
- [x] 3.3: Move `ensureDockerRunning()` / `startDockerDesktop()` logic
- [x] 3.4: Move service start logic into workflow
- [x] 3.5: Update CLI command to use workflow factory
- [x] 3.6: Add deprecated `init(service:)` for backward compatibility with `XcodeStartAllWorkflow`

**Files modified:**
- `DeployLocalXcodeFeature/workflows/XcodeStartServicesWorkflow.swift` - Added `Components`, `create()`, moved all service start logic
- `CLIApp/Commands/LocalCommand.swift` - Updated `StartDatabaseCommand`, `StartDynamoDBCommand`, `StartS3Command` to use factory

**Technical Notes:**
- Workflow now contains all service start logic directly using SDK clients (`PostgreSQLClient`, `MinIOClient`, `DynamoDBClient`)
- Added `Components` struct exposing all clients for potential reuse by other workflows
- Deprecated `init(service:)` allows `XcodeStartAllWorkflow` to continue working until Phase 7 migration
- Docker Desktop auto-start logic (`startDockerDesktop()`) moved directly into workflow
- Uses `.xcode` configuration variants for all SDK clients (distinct from `.linux` variants)

---

### [x] Phase 4: Migrate XcodeStopServicesWorkflow (COMPLETED)

Move service stop logic directly into the workflow.

**Tasks:**
- [x] 4.1: Add SDK dependencies (`PostgreSQLClient`, `MinIOClient`, `DynamoDBClient`)
- [x] 4.2: Create `Components` struct and `create()` factory
- [x] 4.3: Move stop logic into workflow
- [x] 4.4: Update CLI commands
- [x] 4.5: Add deprecated `init(service:)` for backward compatibility with `XcodeStopAllWorkflow`

**Files modified:**
- `DeployLocalXcodeFeature/workflows/XcodeStopServicesWorkflow.swift` - Added `Components`, `create()`, moved all service stop logic
- `CLIApp/Commands/LocalCommand.swift` - Updated `StopDatabaseCommand`, `StopDynamoDBCommand`, `StopS3Command` to use factory

**Technical Notes:**
- Workflow now contains all service stop logic directly using SDK clients (`PostgreSQLClient`, `MinIOClient`, `DynamoDBClient`)
- Simpler than `XcodeStartServicesWorkflow` - no Docker startup checks needed for stop operations
- Deprecated `init(service:)` allows `XcodeStopAllWorkflow` to continue working until Phase 8 migration
- Uses `.xcode` configuration variants for all SDK clients (consistent with start workflow)

---

### [x] Phase 5: Migrate XcodeStartLambdaWorkflow (COMPLETED)

Move Lambda process start logic into the workflow.

**Tasks:**
- [x] 5.1: Add SDK dependencies (`CLIClient`, `PostgreSQLClient`, `MinIOClient`, `DynamoDBClient`, `DockerClient` for env vars)
- [x] 5.2: Create `Components` struct and `create()` factory
- [x] 5.3: Move `startLambda()` logic (spawn process with environment variables)
- [x] 5.4: Move `waitForReady()` logic (poll port with `lsof`)
- [x] 5.5: Move `getExecutablePath()` and `isLambdaBuilt()` logic
- [x] 5.6: Move `getLambdaEnvironmentVariables()` logic (uses `createEnvironmentVariables` from DeployLocalService)
- [x] 5.7: Update CLI command to use factory
- [x] 5.8: Update MacApp model to use factory
- [x] 5.9: Add deprecated `init(service:)` for backward compatibility with `XcodeStartAllWorkflow`

**Files modified:**
- `DeployLocalXcodeFeature/workflows/XcodeStartLambdaWorkflow.swift` - Added `Components`, `create()`, moved all Lambda start logic
- `CLIApp/Commands/LocalCommand.swift` - Updated `StartCommand` to use factory, added `.building` case to print function
- `MacApp/Models/XcodeLocalModel.swift` - Updated `startLambda()` to use factory

**Technical Notes:**
- Workflow now contains all Lambda start logic directly using `CLIClient` and SDK clients
- Added new `.building` step to State to show build progress when Lambda not already built
- Lambda is started as a background process using shell: `env VAR=value ./executable > /tmp/lambda.log 2>&1 &`
- Port checking uses `lsof -i :8080` to verify Lambda is listening
- Environment variables come from `createEnvironmentVariables()` in DeployLocalService with `.xcode` context
- `DockerClient` created internally in `create()` factory for SDK client initialization
- Deprecated `init(service:)` allows `XcodeStartAllWorkflow` to continue working until Phase 7 migration

---

### [x] Phase 6: Migrate XcodeStopLambdaWorkflow (COMPLETED)

Move Lambda process stop logic into the workflow.

**Tasks:**
- [x] 6.1: Add `CLIClient` dependency
- [x] 6.2: Create `Components` struct and `create()` factory
- [x] 6.3: Move `stopLambda()` logic (find PIDs on port, kill them)
- [x] 6.4: Move `isLambdaRunning()` logic (check port with `lsof`)
- [x] 6.5: Move `getProcessIDsOnPort()` helper logic
- [x] 6.6: Update CLI command
- [x] 6.7: Update MacApp model
- [x] 6.8: Add deprecated `init(service:)` for backward compatibility

**Files modified:**
- `DeployLocalXcodeFeature/workflows/XcodeStopLambdaWorkflow.swift` - Added `Components`, `create()`, moved all Lambda stop logic
- `CLIApp/Commands/LocalCommand.swift` - Updated `StopCommand` to use factory
- `MacApp/Models/XcodeLocalModel.swift` - Updated `stopLambda()` to use factory

**Technical Notes:**
- Workflow now contains all Lambda stop logic directly using `CLIClient`
- Simpler than `XcodeStartLambdaWorkflow` - no build or service dependencies needed
- Uses `lsof` to find process IDs and `kill` command to terminate them
- Public `isLambdaRunning()` method available for status checks
- Filters out current process PID to avoid self-termination
- Deprecated `init(service:)` allows `XcodeStopAllWorkflow` to continue working until Phase 8 migration

---

### [x] Phase 7: Migrate XcodeStartAllWorkflow (COMPLETED)

This workflow orchestrates other workflows. Remove direct service dependency.

**Tasks:**
- [x] 7.1: Remove `service` dependency (now only uses other workflows)
- [x] 7.2: Create `Components` struct and `create()` factory method
- [x] 7.3: Update to use workflow factories for sub-workflows
- [x] 7.4: `setupNetworkAndBucket()` logic not needed - bucket creation handled by `XcodeStartServicesWorkflow`, network only needed for Linux mode
- [x] 7.5: Update CLI command
- [x] 7.6: Update MacApp model
- [x] 7.7: Remove deprecated initializers from dependent workflows

**Files modified:**
- `DeployLocalXcodeFeature/workflows/XcodeStartAllWorkflow.swift` - Added `Components`, `create()`, now orchestrates sub-workflows using their factories
- `DeployLocalXcodeFeature/workflows/XcodeStartServicesWorkflow.swift` - Removed deprecated `init(service:)`
- `DeployLocalXcodeFeature/workflows/XcodeStartLambdaWorkflow.swift` - Removed deprecated `init(service:)`
- `CLIApp/Commands/LocalCommand.swift` - Updated `StartAllCommand` to use factory
- `MacApp/Models/XcodeLocalModel.swift` - Updated `startWithServices()` to use factory

**Technical Notes:**
- Workflow now orchestrates sub-workflows using their `create()` factories
- Removed `.waitingForReady` step since `XcodeStartLambdaWorkflow` already includes wait-for-ready logic
- Docker network setup (`setupNetworkAndBucket`) was only needed for Linux mode where containers communicate - Xcode mode uses native processes on localhost that can reach MinIO directly
- Bucket creation is already handled by `XcodeStartServicesWorkflow` after starting MinIO
- Simplified state machine: only `startingServices`, `startingLambda`, and `complete` steps

---

### [ ] Phase 8: Migrate XcodeStopAllWorkflow

This workflow orchestrates other workflows. Remove direct service dependency.

**Tasks:**
- [ ] 8.1: Remove `service` dependency
- [ ] 8.2: Create `Components` struct and `create()` factory method
- [ ] 8.3: Update to use workflow factories for sub-workflows
- [ ] 8.4: Update CLI command
- [ ] 8.5: Update MacApp model
- [ ] 8.6: Remove deprecated initializers from dependent workflows

**Files to modify:**
- `DeployLocalXcodeFeature/workflows/XcodeStopAllWorkflow.swift`
- `DeployLocalXcodeFeature/workflows/XcodeStopLambdaWorkflow.swift` (remove deprecated init)
- `DeployLocalXcodeFeature/workflows/XcodeStopServicesWorkflow.swift` (remove deprecated init)
- `CLIApp/Commands/LocalCommand.swift`
- `MacApp/Models/XcodeLocalModel.swift`

---

### [ ] Phase 9: Migrate XcodeTestWorkflow

Move test logic directly into the workflow.

**Tasks:**
- [ ] 9.1: Add SDK dependencies (`CLIClient` for Lambda status check)
- [ ] 9.2: Add `ClientService` dependency for `APIClient`
- [ ] 9.3: Create `Components` struct and `create()` factory
- [ ] 9.4: Move `performLocalLambdaTests()` logic
- [ ] 9.5: Move `isLambdaRunning()` check logic
- [ ] 9.6: Update CLI command

**Files to modify:**
- `DeployLocalXcodeFeature/workflows/XcodeTestWorkflow.swift`
- `CLIApp/Commands/LocalCommand.swift`

**Technical Notes:**
- `APIClient` is `@MainActor`, so creation needs to happen on MainActor
- Tests: file upload, file list, file download, database init

---

### [ ] Phase 10: Migrate XcodeStatusWorkflow

Move status checking logic into the workflow.

**Tasks:**
- [ ] 10.1: Add SDK dependencies (`CLIClient`, `PostgreSQLClient`, `MinIOClient`, `DynamoDBClient`)
- [ ] 10.2: Create `Components` struct and `create()` factory
- [ ] 10.3: Move `status()` logic
- [ ] 10.4: Move `isLambdaRunning()` logic (port check with `lsof`)
- [ ] 10.5: Update CLI command
- [ ] 10.6: Update MacApp model

**Files to modify:**
- `DeployLocalXcodeFeature/workflows/XcodeStatusWorkflow.swift`
- `CLIApp/Commands/LocalCommand.swift`
- `MacApp/Models/XcodeLocalModel.swift`

---

### [ ] Phase 11: Migrate XcodeCopyConfigWorkflow

Move config copy logic into the workflow.

**Tasks:**
- [ ] 11.1: Add `LocalStorageService` dependency
- [ ] 11.2: Create `Components` struct and `create()` factory
- [ ] 11.3: Move `copyConfig()` logic
- [ ] 11.4: Update CLI command

**Files to modify:**
- `DeployLocalXcodeFeature/workflows/XcodeCopyConfigWorkflow.swift`
- `CLIApp/Commands/LocalCommand.swift`

---

### [ ] Phase 12: Delete XcodeLocalDevelopmentService

After all logic has been migrated.

**Tasks:**
- [ ] 12.1: Verify no remaining references to `XcodeLocalDevelopmentService`
- [ ] 12.2: Delete `XcodeLocalDevelopmentService.swift`
- [ ] 12.3: Update any remaining consumers (MacApp model, tests)
- [ ] 12.4: Ensure shared types in `DeployLocalService` are still accessible

**Files to delete:**
- `DeployLocalXcodeFeature/services/XcodeLocalDevelopmentService.swift`

---

### [ ] Phase 13: Final Cleanup

**Tasks:**
- [ ] 13.1: Remove unnecessary imports from workflows
- [ ] 13.2: Verify all CLI commands work correctly
- [ ] 13.3: Run all tests
- [ ] 13.4: Update documentation

---

## Example: Migrated XcodeBuildWorkflow

```swift
import Foundation
import CLISDK
import Uniflow

public struct XcodeBuildWorkflow: StreamingWorkflow {
    private let cliClient: CLIClient
    private let workingDirectory: String
    private let lambdaProductName = "LambdaApp"

    public struct Components: Sendable {
        public let workflow: XcodeBuildWorkflow
    }

    public static func create(workingDirectory: String) -> Components {
        let cliClient = CLIClient(defaultWorkingDirectory: workingDirectory)
        let workflow = XcodeBuildWorkflow(
            cliClient: cliClient,
            workingDirectory: workingDirectory
        )
        return Components(workflow: workflow)
    }

    public struct State: Sendable {
        public let step: Step
        public let detail: Detail?

        public enum Step: Sendable, Equatable {
            case cleaning
            case building
            case complete
        }

        public enum Detail: Sendable {
            case output(String)
            case buildPath(String)
        }

        public init(step: Step, detail: Detail? = nil) {
            self.step = step
            self.detail = detail
        }
    }

    public typealias Result = State

    public struct Options: Sendable {
        public let clean: Bool
        public init(clean: Bool = false) {
            self.clean = clean
        }
    }

    public func stream(options: Options) -> AsyncThrowingStream<State, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    try await runWorkflow(options: options, continuation: continuation)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func runWorkflow(
        options: Options,
        continuation: AsyncThrowingStream<State, Error>.Continuation
    ) async throws {
        if options.clean {
            continuation.yield(State(step: .cleaning))
            _ = try await cliClient.execute(
                SwiftCLI.Package.Clean(),
                workingDirectory: workingDirectory,
                printCommand: false
            )
        }

        continuation.yield(State(step: .building))

        let buildCommand = SwiftCLI.Build(product: lambdaProductName)
        let stream = await cliClient.stream(
            buildCommand,
            workingDirectory: workingDirectory,
            printCommand: false
        )

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

        let executablePath = try await getExecutablePath()
        continuation.yield(State(step: .complete, detail: .buildPath(executablePath)))
        continuation.finish()
    }

    // Helper moved from service
    private func getExecutablePath() async throws -> String {
        let showBinPathCommand = SwiftCLI.Build(product: lambdaProductName, showBinPath: true)
        let result = try await cliClient.executeForResult(
            showBinPathCommand,
            workingDirectory: workingDirectory,
            printCommand: false
        )

        guard result.isSuccess else {
            throw DeployError.commandFailed(
                command: showBinPathCommand.commandString,
                exitCode: result.exitCode,
                output: result.output
            )
        }

        let binPath = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(binPath)/\(lambdaProductName)"
    }

    // Helper moved from service
    public func isLambdaBuilt() -> Bool {
        let debugDir = "\(workingDirectory)/.build"
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: debugDir) else {
            return false
        }

        for item in contents {
            let executablePath = "\(debugDir)/\(item)/debug/\(lambdaProductName)"
            if FileManager.default.fileExists(atPath: executablePath) {
                return true
            }
        }
        return false
    }

    // Helper moved from service
    public func deleteBuild() async throws {
        _ = try await cliClient.execute(
            SwiftCLI.Package.Clean(),
            workingDirectory: workingDirectory,
            printCommand: false
        )
    }
}
```

---

## Risk Assessment

| Risk | Mitigation |
|------|------------|
| Breaking existing functionality | Run all tests after each phase |
| Missing dependencies in workflows | Carefully track SDK dependencies per method |
| Duplicate code between workflows | Extract shared utilities (e.g., port checking with `lsof`) to a helper |
| CLI command changes | Update CLI commands in each phase, verify they work |
| MacApp model integration | Update MacApp model in each phase, test manually |

---

## Success Criteria

1. `XcodeLocalDevelopmentService.swift` is deleted
2. All 10 workflows contain their own logic (no pass-through)
3. Workflows directly use SDK clients
4. All CLI commands work as before
5. MacApp functions correctly
6. All tests pass
7. No functionality regressions
