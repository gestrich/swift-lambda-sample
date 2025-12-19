# Extract service-deploy-local Target

**Status:** Complete
**Date:** 2025-12-17

## Objective

Extract local development functionality from `service-deploy-remote` into a new `service-deploy-local` target, creating a clear separation between remote AWS deployment services and local Docker-based development services.

## Background / Motivation

Currently, `service-deploy-remote` contains both:

1. **Remote deployment code** - AWS CDK deployment, GitHub CI workflows, CloudWatch logs, Lambda updates
2. **Local development code** - Docker container services (PostgreSQL, MinIO, DynamoDB), Xcode/Linux Lambda runners

This mixing violates the single-responsibility principle and creates confusing coupling. The `remote` suffix suggests AWS-only concerns, yet the target contains significant local development infrastructure.

### Current Structure in service-deploy-remote

```
Sources/service-deploy-remote/
├── Auth/                        # AWS auth - REMOTE
├── AWSService/                  # AWS service - REMOTE
├── Core/Errors/
│   └── DeployError.swift        # SHARED (used by both)
├── GitHubService/               # GitHub config - REMOTE
├── LambdaService/
│   ├── Models/                  # SHARED (LambdaState, LambdaStatus)
│   ├── Protocols/               # SHARED (LambdaService, LocalService protocols)
│   └── LambdaBuildService.swift # Builds + uploads to AWS - REMOTE
├── LocalDevelopmentService/     # ALL LOCAL
│   ├── Containers/
│   │   ├── DynamoDBLocalService.swift
│   │   ├── MinIOService.swift
│   │   └── PostgreSQLLocalService.swift
│   ├── Protocols/
│   │   └── LocalService.swift
│   ├── EnvironmentVariables.swift
│   ├── LinuxLocalDevelopmentService.swift
│   └── XcodeLocalDevelopmentService.swift
├── Models/                      # CDK/deployment models - REMOTE
├── ToolsService/                # REMOTE
└── Workflows/                   # All remote workflows - REMOTE
```

## Technical Approach

### New Targets

Create two new service-layer targets:

1. **`service-deploy-core`** - Shared types used by both local and remote
2. **`service-deploy-local`** - Local Docker-based development functionality

This ensures `service-deploy-local` and `service-deploy-remote` remain independent siblings that share common types through a core target.

### Files to Move

**Move to `service-deploy-core` (shared types):**

| Current Location | New Location |
|-----------------|--------------|
| `Core/Errors/DeployError.swift` | `service-deploy-core/DeployError.swift` |
| `LambdaService/Models/LambdaState.swift` | `service-deploy-core/LambdaState.swift` |
| `LambdaService/Models/LambdaStatus.swift` | `service-deploy-core/LambdaStatus.swift` |
| `LambdaService/Protocols/LambdaService.swift` | `service-deploy-core/LambdaService.swift` |

**Move to `service-deploy-local`:**

| Current Location | New Location |
|-----------------|--------------|
| `LocalDevelopmentService/Containers/DynamoDBLocalService.swift` | `service-deploy-local/Containers/DynamoDBLocalService.swift` |
| `LocalDevelopmentService/Containers/MinIOService.swift` | `service-deploy-local/Containers/MinIOService.swift` |
| `LocalDevelopmentService/Containers/PostgreSQLLocalService.swift` | `service-deploy-local/Containers/PostgreSQLLocalService.swift` |
| `LocalDevelopmentService/LinuxLocalDevelopmentService.swift` | `service-deploy-local/LinuxLocalDevelopmentService.swift` |
| `LocalDevelopmentService/XcodeLocalDevelopmentService.swift` | `service-deploy-local/XcodeLocalDevelopmentService.swift` |
| `LocalDevelopmentService/EnvironmentVariables.swift` | `service-deploy-local/EnvironmentVariables.swift` |
| `LocalDevelopmentService/Protocols/LocalService.swift` | `service-deploy-local/LocalService.swift` |

### New Directory Structures

```
Sources/service-deploy-core/
├── DeployError.swift
├── LambdaState.swift
├── LambdaStatus.swift
└── LambdaService.swift          # Protocol + DeploymentStatus, ServiceState

Sources/service-deploy-local/
├── Containers/
│   ├── DynamoDBLocalService.swift
│   ├── MinIOService.swift
│   └── PostgreSQLLocalService.swift
├── LinuxLocalDevelopmentService.swift
├── XcodeLocalDevelopmentService.swift
├── EnvironmentVariables.swift
└── LocalService.swift           # Protocol extending LambdaService
```

### Package.swift Changes

```swift
.target(
    name: "service-deploy-core",
    dependencies: [
        .target(name: "sdk-cli"),
        .target(name: "sdk-client"),
    ]
),
.target(
    name: "service-deploy-local",
    dependencies: [
        .target(name: "sdk-cli"),
        .target(name: "sdk-cli-docker"),
        .target(name: "sdk-client"),
        .target(name: "service-storage"),
        .target(name: "service-lambda-build"),
        .target(name: "service-deploy-core"),
    ]
),
.target(
    name: "service-deploy-remote",
    dependencies: [
        .target(name: "sdk-client"),
        .target(name: "service-storage"),
        .target(name: "service-lambda-build"),
        .target(name: "sdk-cli"),
        .target(name: "sdk-cli-docker"),
        .target(name: "sdk-aws"),
        .target(name: "sdk-github"),
        .target(name: "service-deploy-core"),  // Add dependency on core
    ]
),
```

### Consumer Updates

**app-cli** (Sources/app-cli/Commands/LocalCommand.swift):
- Add import: `import service_deploy_local`
- Add import: `import service_deploy_core` (if using shared types directly)
- Change: `XcodeLocalDevelopmentService` and `LinuxLocalDevelopmentService` now come from `service_deploy_local`

**app-mac** (Sources/app-mac/Models/):
- `XcodeLocalModel.swift`: Add `import service_deploy_local`, `import service_deploy_core`
- `LinuxLocalModel.swift`: Add `import service_deploy_local`, `import service_deploy_core`

## Implementation Steps

### Phase 1: Create service-deploy-core ✅ COMPLETED

- [x] Create `Sources/service-deploy-core/` directory
- [x] Add `service-deploy-core` target to `Package.swift`
- [x] Move `Core/Errors/DeployError.swift` → `service-deploy-core/DeployError.swift`
- [x] Move `LambdaService/Models/LambdaState.swift` → `service-deploy-core/LambdaState.swift`
- [x] Move `LambdaService/Models/LambdaStatus.swift` → `service-deploy-core/LambdaStatus.swift`
- [x] Move `LambdaService/Protocols/LambdaService.swift` → `service-deploy-core/LambdaService.swift`
- [x] Update `service-deploy-remote` to depend on `service-deploy-core`
- [x] Update imports in `service-deploy-remote` to use `import service_deploy_core`
- [x] Build and verify

**Technical Notes (Phase 1):**
- Consumers (`app-cli`, `app-mac`) also needed `service-deploy-core` added as a dependency since Swift modules don't auto-re-export types
- Empty directories removed from `service-deploy-remote`: `Core/Errors/`, `Core/`, `LambdaService/Models/`, `LambdaService/Protocols/`
- Files requiring `import service_deploy_core`:
  - service-deploy-remote: `XcodeLocalDevelopmentService.swift`, `LinuxLocalDevelopmentService.swift`, `LocalService.swift`, `UpdateLambdaWorkflow.swift`, `GitHubCIWorkflow.swift`, `DeployInitWorkflow.swift`
  - app-cli: `LocalCommand.swift`, `TearDownCommand.swift`, `AWSAuthConfiguration+ArgumentParser.swift`
  - app-mac: `LocalServicesModel.swift`, `XcodeLocalModel.swift`, `LinuxLocalModel.swift`, `DockerServicesView.swift`, `AppModel.swift`, `DeploymentModel.swift`

### Phase 2: Create service-deploy-local ✅ COMPLETED

- [x] Create `Sources/service-deploy-local/` directory
- [x] Add `service-deploy-local` target to `Package.swift`
- [x] Verify build succeeds (empty target)

**Technical Notes (Phase 2):**
- Created placeholder file `ServiceDeployLocal.swift` to satisfy Swift package manager requirements
- Target dependencies match the proposal: `sdk-cli`, `sdk-cli-docker`, `sdk-client`, `service-storage`, `service-lambda-build`, `service-deploy-core`

### Phase 3: Move Local Development Services ✅ COMPLETED

- [x] Move `LocalDevelopmentService/Containers/` → `service-deploy-local/Containers/`
- [x] Move `LocalDevelopmentService/LinuxLocalDevelopmentService.swift` → `service-deploy-local/`
- [x] Move `LocalDevelopmentService/XcodeLocalDevelopmentService.swift` → `service-deploy-local/`
- [x] Move `LocalDevelopmentService/EnvironmentVariables.swift` → `service-deploy-local/`
- [x] Move `LocalDevelopmentService/Protocols/LocalService.swift` → `service-deploy-local/LocalService.swift`
- [x] Update imports in moved files
- [x] Build and verify

**Technical Notes (Phase 3):**
- Moved 7 files total: 3 container services (MinIO, PostgreSQL, DynamoDB), 2 development services (Xcode, Linux), 1 protocol (LocalService), 1 helper (EnvironmentVariables)
- Removed placeholder `ServiceDeployLocal.swift` after moving real files
- Deleted empty `LocalDevelopmentService/` directory tree from `service-deploy-remote`

### Phase 4: Update Consumers ✅ COMPLETED

- [x] Update `app-cli/Commands/LocalCommand.swift`:
  - Changed `import service_deploy_remote` → `import service_deploy_local`
- [x] Update `app-mac/Models/XcodeLocalModel.swift`:
  - Changed `import service_deploy_remote` → `import service_deploy_local`
- [x] Update `app-mac/Models/LinuxLocalModel.swift`:
  - Changed `import service_deploy_remote` → `import service_deploy_local`
- [x] Update `app-mac/UI/LocalService/LocalServicesModel.swift`:
  - Changed `import service_deploy_remote` → `import service_deploy_local`
- [x] Update `app-mac/UI/LocalService/DockerServicesView.swift`:
  - Changed `import service_deploy_remote` → `import service_deploy_local`
- [x] Add `service-deploy-local` dependency to `app-cli` in Package.swift
- [x] Add `service-deploy-local` dependency to `app-mac` in Package.swift
- [x] Build and verify all targets compile

**Technical Notes (Phase 4):**
- Additional file `DockerServicesView.swift` also needed import update (not originally listed)
- Replaced `service_deploy_remote` import with `service_deploy_local` (not added alongside)

### Phase 5: Clean Up service-deploy-remote ✅ COMPLETED

- [x] Delete empty `LocalDevelopmentService/` directory from `service-deploy-remote`
- [x] `Core/Errors/` already removed in Phase 1
- [x] `LambdaService/Models/` and `LambdaService/Protocols/` already removed in Phase 1
- [x] Verify `service-deploy-remote` no longer references local-only types
- [x] Run full build to ensure no broken references

**Technical Notes (Phase 5):**
- `LocalDevelopmentService/` directory tree (including `Containers/` and `Protocols/` subdirectories) was removed as part of Phase 3
- Full build passes successfully

## Dependency Diagram

After refactoring:

```
┌─────────────────────────────────────────────────────────────┐
│                          APP                                 │
│              app-mac  ·  app-cli  ·  app-lambda              │
└────────────────────────┬──────────────────────────────────────┘
                         │
          ┌──────────────┼──────────────┐
          ▼              ▼              ▼
┌──────────────────┐           ┌──────────────────┐
│ service-deploy-  │           │ service-deploy-  │
│ local            │           │ remote           │
│                  │           │                  │
│ - Xcode/Linux    │           │ - CDK workflows  │
│   dev services   │           │ - GitHub CI      │
│ - Docker         │           │ - CloudWatch     │
│   containers     │           │ - Lambda upload  │
│ - Local Lambda   │           │ - AWS auth       │
└────────┬─────────┘           └────────┬─────────┘
         │                              │
         └──────────┬───────────────────┘
                    ▼
         ┌──────────────────┐
         │ service-deploy-  │
         │ core             │
         │                  │
         │ - DeployError    │
         │ - LambdaState    │
         │ - LambdaStatus   │
         │ - LambdaService  │
         │ - ServiceState   │
         │ - DeployStatus   │
         └────────┬─────────┘
                  │
                  ▼
┌─────────────────────────────────────────────────────────────┐
│                         SDK                                  │
│  sdk-cli · sdk-cli-docker · sdk-aws · sdk-github · sdk-client│
└─────────────────────────────────────────────────────────────┘
```

**Key:** `service-deploy-local` and `service-deploy-remote` are sibling targets with no dependency on each other. Both depend on `service-deploy-core` for shared types.

## Testing Considerations

### Build Verification

```bash
# After each phase, verify:
swift build --target service-deploy-local
swift build --target service-deploy-remote
swift build --target app-cli
swift build --target app-mac
swift build  # Full build
```

### Functional Testing

After refactoring, verify these CLI commands still work:

```bash
# Local Mac commands
swift run SwiftDeploy local-mac start-all
swift run SwiftDeploy local-mac test
swift run SwiftDeploy local-mac stop-all

# Local Linux commands
swift run SwiftDeploy local-linux build
swift run SwiftDeploy local-linux start-all
swift run SwiftDeploy local-linux test
swift run SwiftDeploy local-linux stop-all
```

## Success Criteria

1. **Clean separation**: `service-deploy-remote` contains only AWS/remote code
2. **Clean separation**: `service-deploy-local` contains only local development code
3. **Clean separation**: `service-deploy-core` contains only shared types/protocols
4. **No cross-dependency**: `service-deploy-local` and `service-deploy-remote` do not depend on each other
5. **All builds pass**: `swift build` succeeds
6. **CLI works**: All `local-mac` and `local-linux` subcommands function correctly
7. **Mac app works**: Local service views in app-mac work correctly
8. **No behavior changes**: This is purely a code organization refactor

## Future Considerations

### Workflow Migration

The current scope explicitly excludes creating workflows for local operations. If workflows are desired for local services (e.g., `LocalStartWorkflow`, `LocalBuildWorkflow`), that would be a separate future task.

## Related Documentation

- [Layered Architecture](../architecture/layered-architecture.md)
- [Code Style](../architecture/code-style.md)
