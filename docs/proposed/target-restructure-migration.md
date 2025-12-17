# Target Restructure Migration Plan

This document tracks the migration from the current `a-`, `b-`, `c-`, `d-` prefix naming convention to the new folder-based structure with PascalCase naming.

## New Structure Overview

```
Sources/
├── apps/
│   ├── CLIApp/
│   ├── LambdaApp/
│   └── MacApp/
├── features/
│   ├── DeployRemoteFeature/
│   │   ├── workflows/
│   │   └── services/
│   ├── DeployLocalXcodeFeature/
│   │   ├── workflows/
│   │   └── services/
│   ├── DeployLocalLinuxFeature/
│   │   ├── workflows/
│   │   └── services/
│   └── SetupFeature/
│       ├── workflows/
│       └── services/
├── services/
│   ├── StorageService/
│   ├── DeployCoreService/
│   ├── ClientService/
│   ├── LambdaBuildService/
│   └── DeployLocalService/
└── sdks/
    ├── CLISDK/
    ├── CLIMacrosSDK/
    ├── DockerCLISDK/
    ├── BrewCLISDK/
    ├── NodeCLISDK/
    ├── AWSSDK/
    ├── GitHubSDK/
    ├── MinioSDK/
    ├── PostgreSQLSDK/
    └── DynamoDBSDK/
```

## Naming Convention

- **PascalCase** for all target names
- Suffix indicates layer: `Feature`, `Service`, `SDK`
- Apps have `App` suffix

## Migration Mapping

### Apps

| Old Target | New Target | New Path |
|------------|------------|----------|
| `a-app-cli` | `CLIApp` | `apps/CLIApp/` |
| `a-app-lambda` | `LambdaApp` | `apps/LambdaApp/` |
| `a-app-mac` | `MacApp` | `apps/MacApp/` |

### Features (Workflow + Service merged)

| Old Workflow | Old Service | New Target | New Path |
|--------------|-------------|------------|----------|
| `b-workflow-deploy-remote` | `c-service-deploy-remote` | `DeployRemoteFeature` | `features/DeployRemoteFeature/` |
| `b-workflow-deploy-local-xcode` | (uses c-service-deploy-local) | `DeployLocalXcodeFeature` | `features/DeployLocalXcodeFeature/` |
| `b-workflow-deploy-local-linux` | (uses c-service-deploy-local) | `DeployLocalLinuxFeature` | `features/DeployLocalLinuxFeature/` |
| `b-workflow-setup` | `c-service-setup` | `SetupFeature` | `features/SetupFeature/` |

### Services (Standalone)

| Old Target | New Target | New Path |
|------------|------------|----------|
| `c-service-storage` | `StorageService` | `services/StorageService/` |
| `c-service-deploy-core` | `DeployCoreService` | `services/DeployCoreService/` |
| `c-service-client` | `ClientService` | `services/ClientService/` |
| `c-service-lambda-build` | `LambdaBuildService` | `services/LambdaBuildService/` |
| `c-service-deploy-local` | `DeployLocalService` | `services/DeployLocalService/` |

### SDKs

| Old Target | New Target | New Path |
|------------|------------|----------|
| `d-sdk-cli` | `CLISDK` | `sdks/CLISDK/` |
| `d-sdk-cli-macros` | `CLIMacrosSDK` | `sdks/CLIMacrosSDK/` |
| `d-sdk-cli-docker` | `DockerCLISDK` | `sdks/DockerCLISDK/` |
| `d-sdk-cli-brew` | `BrewCLISDK` | `sdks/BrewCLISDK/` |
| `d-sdk-cli-node` | `NodeCLISDK` | `sdks/NodeCLISDK/` |
| `d-sdk-aws` | `AWSSDK` | `sdks/AWSSDK/` |
| `d-sdk-github` | `GitHubSDK` | `sdks/GitHubSDK/` |
| `d-sdk-minio` | `MinioSDK` | `sdks/MinioSDK/` |
| `d-sdk-postgresql` | `PostgreSQLSDK` | `sdks/PostgreSQLSDK/` |
| `d-sdk-dynamodb` | `DynamoDBSDK` | `sdks/DynamoDBSDK/` |

### Tests

| Old Target | New Target | New Path |
|------------|------------|----------|
| `c-service-deploy-remote-tests` | `DeployRemoteFeatureTests` | `Tests/DeployRemoteFeatureTests/` |
| `d-sdk-cli-tests` | `CLISDKTests` | `Tests/CLISDKTests/` |

---

## Migration Checklist

Migration order: SDKs first (no dependencies on other project targets), then Services, then Features, then Apps.

### Phase 1: SDKs

- [x] **CLIMacrosSDK** (no internal dependencies) ✅
  - [x] Create `sdks/` folder
  - [x] Move `d-sdk-cli-macros/` to `sdks/CLIMacrosSDK/`
  - [x] Update Package.swift target name and path
  - [x] Update all imports in dependent targets (Macros.swift module references)
  - [x] Verify build succeeds

- [x] **CLISDK** (depends on CLIMacrosSDK) ✅
  - [x] Move `d-sdk-cli/` to `sdks/CLISDK/`
  - [x] Update Package.swift target name and path
  - [x] Update dependency reference to CLIMacrosSDK
  - [x] Update all imports in dependent targets
  - [x] Verify build succeeds

- [x] **DockerCLISDK** (depends on CLISDK) ✅
  - [x] Move `d-sdk-cli-docker/` to `sdks/DockerCLISDK/`
  - [x] Update Package.swift target name and path
  - [x] Update dependency reference to CLISDK
  - [x] Update all imports in dependent targets
  - [x] Verify build succeeds

- [x] **BrewCLISDK** (depends on CLISDK) ✅
  - [x] Move `d-sdk-cli-brew/` to `sdks/BrewCLISDK/`
  - [x] Update Package.swift target name and path
  - [x] Update dependency reference to CLISDK
  - [x] Update all imports in dependent targets
  - [x] Verify build succeeds

- [x] **NodeCLISDK** (depends on CLISDK) ✅
  - [x] Move `d-sdk-cli-node/` to `sdks/NodeCLISDK/`
  - [x] Update Package.swift target name and path
  - [x] Update dependency reference to CLISDK
  - [x] Update all imports in dependent targets
  - [x] Verify build succeeds

- [x] **AWSSDK** (depends on CLISDK, NodeCLISDK) ✅
  - [x] Move `d-sdk-aws/` to `sdks/AWSSDK/`
  - [x] Update Package.swift target name and path
  - [x] Update dependency references
  - [x] Update all imports in dependent targets
  - [x] Verify build succeeds

- [x] **GitHubSDK** (depends on CLISDK) ✅
  - [x] Move `d-sdk-github/` to `sdks/GitHubSDK/`
  - [x] Update Package.swift target name and path
  - [x] Update dependency reference to CLISDK
  - [x] Update all imports in dependent targets
  - [x] Verify build succeeds

- [x] **MinioSDK** (depends on DockerCLISDK) ✅
  - [x] Move `d-sdk-minio/` to `sdks/MinioSDK/`
  - [x] Update Package.swift target name and path
  - [x] Update dependency reference to DockerCLISDK
  - [x] Update all imports in dependent targets
  - [x] Verify build succeeds

- [x] **PostgreSQLSDK** (depends on DockerCLISDK) ✅
  - [x] Move `d-sdk-postgresql/` to `sdks/PostgreSQLSDK/`
  - [x] Update Package.swift target name and path
  - [x] Update dependency reference to DockerCLISDK
  - [x] Update all imports in dependent targets
  - [x] Verify build succeeds

- [x] **DynamoDBSDK** (depends on DockerCLISDK) ✅
  - [x] Move `d-sdk-dynamodb/` to `sdks/DynamoDBSDK/`
  - [x] Update Package.swift target name and path
  - [x] Update dependency reference to DockerCLISDK
  - [x] Update all imports in dependent targets
  - [x] Verify build succeeds

- [x] **CLISDKTests** ✅
  - [x] Move `Tests/d-sdk-cli-tests/` to `Tests/CLISDKTests/`
  - [x] Update Package.swift test target name and path
  - [x] Update dependency references
  - [x] Verify tests pass

### Phase 2: Services

- [x] **StorageService** (no internal dependencies) ✅
  - [x] Create `services/` folder
  - [x] Move `c-service-storage/` to `services/StorageService/`
  - [x] Update Package.swift target name and path
  - [x] Update all imports in dependent targets
  - [x] Verify build succeeds

- [x] **ClientService** (no internal dependencies) ✅
  - [x] Move `c-service-client/` to `services/ClientService/`
  - [x] Update Package.swift target name and path
  - [x] Update all imports in dependent targets
  - [x] Verify build succeeds

- [x] **LambdaBuildService** (depends on CLISDK) ✅
  - [x] Move `c-service-lambda-build/` to `services/LambdaBuildService/`
  - [x] Update Package.swift target name and path
  - [x] Update dependency references
  - [x] Update all imports in dependent targets
  - [x] Verify build succeeds

- [x] **DeployCoreService** (depends on CLISDK, ClientService) ✅
  - [x] Move `c-service-deploy-core/` to `services/DeployCoreService/`
  - [x] Update Package.swift target name and path
  - [x] Update dependency references
  - [x] Update all imports in dependent targets
  - [x] Verify build succeeds

- [x] **DeployLocalService** (depends on multiple SDKs and services) ✅
  - [x] Move `c-service-deploy-local/` to `services/DeployLocalService/`
  - [x] Update Package.swift target name and path
  - [x] Update dependency references
  - [x] Update all imports in dependent targets
  - [x] Verify build succeeds

### Phase 3: Features

- [x] **SetupFeature** ✅
  - [x] Create `features/` folder
  - [x] Create `features/SetupFeature/` with `workflows/` and `services/` subfolders
  - [x] Move workflow code from `b-workflow-setup/` to `features/SetupFeature/workflows/`
  - [x] Move service code from `c-service-setup/` to `features/SetupFeature/services/`
  - [x] Update Package.swift (single target for the feature)
  - [x] Update dependency references
  - [x] Update all imports in dependent targets
  - [x] Verify build succeeds

- [ ] **DeployRemoteFeature**
  - [ ] Create `features/DeployRemoteFeature/` with `workflows/` and `services/` subfolders
  - [ ] Move workflow code from `b-workflow-deploy-remote/` to `features/DeployRemoteFeature/workflows/`
  - [ ] Move service code from `c-service-deploy-remote/` to `features/DeployRemoteFeature/services/`
  - [ ] Update Package.swift (single target for the feature)
  - [ ] Update dependency references
  - [ ] Update all imports in dependent targets
  - [ ] Verify build succeeds

- [ ] **DeployRemoteFeatureTests**
  - [ ] Move `Tests/c-service-deploy-remote-tests/` to `Tests/DeployRemoteFeatureTests/`
  - [ ] Update Package.swift test target name and path
  - [ ] Update dependency references
  - [ ] Verify tests pass

- [ ] **DeployLocalXcodeFeature**
  - [ ] Create `features/DeployLocalXcodeFeature/` with `workflows/` and `services/` subfolders
  - [ ] Move workflow code from `b-workflow-deploy-local-xcode/` to `features/DeployLocalXcodeFeature/workflows/`
  - [ ] Add any xcode-specific service code to `services/` subfolder (if applicable)
  - [ ] Update Package.swift (single target for the feature)
  - [ ] Update dependency references
  - [ ] Update all imports in dependent targets
  - [ ] Verify build succeeds

- [ ] **DeployLocalLinuxFeature**
  - [ ] Create `features/DeployLocalLinuxFeature/` with `workflows/` and `services/` subfolders
  - [ ] Move workflow code from `b-workflow-deploy-local-linux/` to `features/DeployLocalLinuxFeature/workflows/`
  - [ ] Add any linux-specific service code to `services/` subfolder (if applicable)
  - [ ] Update Package.swift (single target for the feature)
  - [ ] Update dependency references
  - [ ] Update all imports in dependent targets
  - [ ] Verify build succeeds

### Phase 4: Apps

- [ ] **LambdaApp**
  - [ ] Create `apps/` folder
  - [ ] Move `a-app-lambda/` to `apps/LambdaApp/`
  - [ ] Update Package.swift target name and path
  - [ ] Update dependency references
  - [ ] Update product name if desired
  - [ ] **Update hardcoded target name references:**
    - [ ] GitHub Actions workflows (`.github/workflows/*.yml`) - build scripts reference target name
    - [ ] Swift code that launches/references the Lambda target by string (e.g., `swift build --product`)
    - [ ] `build.sh` and any other shell scripts
    - [ ] Documentation referencing the old target name
  - [ ] Verify build succeeds

- [ ] **CLIApp**
  - [ ] Move `a-app-cli/` to `apps/CLIApp/`
  - [ ] Update Package.swift target name and path
  - [ ] Update dependency references
  - [ ] Update product name if desired
  - [ ] **Update hardcoded target name references:**
    - [ ] `tools.sh` wrapper script (`swift run SwiftDeploy` or similar)
    - [ ] Documentation (CLAUDE.md, README.md) referencing CLI commands
  - [ ] Verify build succeeds

- [ ] **MacApp**
  - [ ] Move `a-app-mac/` to `apps/MacApp/`
  - [ ] Update Package.swift target name and path
  - [ ] Update dependency references
  - [ ] Verify build succeeds

### Phase 5: Cleanup

- [ ] Remove empty old directories
- [ ] Update documentation (CLAUDE.md, README.md, architecture docs)
- [ ] Update any scripts that reference old target names
- [ ] Run full test suite
- [ ] Verify all apps build and run correctly

---

## Dependency Graph (New Names)

```
CLIApp ─────────────────┬─► DeployRemoteFeature ─────┬─► DeployCoreService
                        │                            ├─► AWSSDK
MacApp ─────────────────┼─► DeployLocalXcodeFeature ─┼─► GitHubSDK
                        │                            ├─► CLISDK
                        ├─► DeployLocalLinuxFeature ─┤
                        │                            └─► DeployLocalService
                        └─► SetupFeature ────────────┬─► StorageService
                                                     ├─► ClientService
LambdaApp ──────────────────────────────────────────►│   LambdaBuildService
                                                     │
                                                     └─► (SDKs below)

SDKs (bottom layer):
CLISDK ◄── CLIMacrosSDK
   │
   ├──► DockerCLISDK ──┬──► MinioSDK
   │                   ├──► PostgreSQLSDK
   │                   └──► DynamoDBSDK
   ├──► BrewCLISDK
   ├──► NodeCLISDK ────► AWSSDK
   └──► GitHubSDK
```

---

## Notes

- Each target migration should be a separate commit for easy rollback
- Build and test after each target migration before proceeding
- Import statements will change from `import d_sdk_cli` to `import CLISDK` (underscores become part of the module name based on folder structure)
- Features combine workflow + service into a single target with internal folder organization

---

## Technical Notes

### CLIMacrosSDK Migration (Phase 1.1)

**Key changes:**
- Moved `Sources/d-sdk-cli-macros/` → `Sources/sdks/CLIMacrosSDK/`
- Updated Package.swift: renamed target from `d-sdk-cli-macros` to `CLIMacrosSDK` with explicit path
- Updated `#externalMacro` module references in `Sources/sdks/CLISDK/Macros.swift` from `d_sdk_cli_macros` to `CLIMacrosSDK`
- Updated dependency references in `d-sdk-cli` and `d-sdk-cli-tests` targets

**Module name behavior:**
- Swift macro targets use the target name directly as the module name
- `CLIMacrosSDK` becomes module name `CLIMacrosSDK` (no underscore transformation since no hyphens)

### CLISDK Migration (Phase 1.2)

**Key changes:**
- Moved `Sources/d-sdk-cli/` → `Sources/sdks/CLISDK/`
- Updated Package.swift: renamed target from `d-sdk-cli` to `CLISDK` with explicit path
- Updated all dependency references from `.target(name: "d-sdk-cli")` to `.target(name: "CLISDK")`
- Updated all imports from `import d_sdk_cli` to `import CLISDK` (99 files affected)

**Module name behavior:**
- Regular targets with PascalCase names become module names directly
- `CLISDK` becomes module name `CLISDK` (no underscore transformation)

**Important: Only rename the target being migrated:**
- When updating imports with sed/find, be careful not to accidentally modify imports for other SDK targets
- For example, `d_sdk_cli_docker` should NOT become `CLISDK_docker` - each SDK migrates independently
- Pattern used: `s/import d_sdk_cli$/import CLISDK/` (exact match) rather than `s/d_sdk_cli/CLISDK/g` (global replace)

### DockerCLISDK Migration (Phase 1.3)

**Key changes:**
- Moved `Sources/d-sdk-cli-docker/` → `Sources/sdks/DockerCLISDK/`
- Updated Package.swift: renamed target from `d-sdk-cli-docker` to `DockerCLISDK` with explicit path
- Updated all dependency references from `.target(name: "d-sdk-cli-docker")` to `.target(name: "DockerCLISDK")` (8 references)
- Updated all imports from `import d_sdk_cli_docker` to `import DockerCLISDK` (7 files affected)

**Files updated:**
- `Sources/b-workflow-setup/DependencyStatusWorkflow.swift`
- `Sources/d-sdk-minio/MinIOClient.swift`
- `Sources/d-sdk-postgresql/PostgreSQLClient.swift`
- `Sources/d-sdk-dynamodb/DynamoDBClient.swift`
- `Sources/c-service-deploy-local/LinuxLocalDevelopmentService.swift`
- `Sources/c-service-deploy-local/XcodeLocalDevelopmentService.swift`
- `Tests/c-service-deploy-remote-tests/DockerTests.swift`

**Module name behavior:**
- `DockerCLISDK` becomes module name `DockerCLISDK` directly (PascalCase, no hyphens)

### BrewCLISDK Migration (Phase 1.4)

**Key changes:**
- Moved `Sources/d-sdk-cli-brew/` → `Sources/sdks/BrewCLISDK/`
- Updated Package.swift: renamed target from `d-sdk-cli-brew` to `BrewCLISDK` with explicit path
- Updated all dependency references from `.target(name: "d-sdk-cli-brew")` to `.target(name: "BrewCLISDK")` (2 references in Package.swift)
- Updated all imports from `import d_sdk_cli_brew` to `import BrewCLISDK` (2 files affected)

**Files updated:**
- `Sources/b-workflow-setup/DependencyStatusWorkflow.swift`
- `Sources/b-workflow-setup/DependencyInstallWorkflow.swift`

**Module name behavior:**
- `BrewCLISDK` becomes module name `BrewCLISDK` directly (PascalCase, no hyphens)

### NodeCLISDK Migration (Phase 1.5)

**Key changes:**
- Moved `Sources/d-sdk-cli-node/` → `Sources/sdks/NodeCLISDK/`
- Updated Package.swift: renamed target from `d-sdk-cli-node` to `NodeCLISDK` with explicit path
- Updated all dependency references from `.target(name: "d-sdk-cli-node")` to `.target(name: "NodeCLISDK")` (5 references in Package.swift: d-sdk-aws, b-workflow-setup, a-app-mac, c-service-deploy-remote-tests)
- Updated all imports from `import d_sdk_cli_node` to `import NodeCLISDK` (3 files affected)

**Files updated:**
- `Sources/b-workflow-setup/DependencyStatusWorkflow.swift`
- `Sources/sdks/AWSSDK/CDK/CDKClient.swift`
- `Tests/c-service-deploy-remote-tests/NpmTests.swift`

**Module name behavior:**
- `NodeCLISDK` becomes module name `NodeCLISDK` directly (PascalCase, no hyphens)

### AWSSDK Migration (Phase 1.6)

**Key changes:**
- Moved `Sources/d-sdk-aws/` → `Sources/sdks/AWSSDK/`
- Updated Package.swift: renamed target from `d-sdk-aws` to `AWSSDK` with explicit path
- Updated all dependency references from `.target(name: "d-sdk-aws")` to `.target(name: "AWSSDK")` (5 references in Package.swift: b-workflow-setup, b-workflow-deploy-remote, a-app-cli, c-service-deploy-remote, a-app-mac)
- Updated all imports from `import d_sdk_aws` to `import AWSSDK` (26 files affected)

**Files updated:**
- `Sources/b-workflow-setup/DependencyStatusWorkflow.swift`
- `Sources/a-app-cli/Commands/StatusCommand.swift`
- `Sources/a-app-cli/CLIAWSEnvironment.swift`
- `Sources/a-app-cli/Commands/AWSCommand.swift`
- `Sources/a-app-cli/Commands/DeployInitCommand.swift`
- `Sources/a-app-cli/Commands/DeployCommand.swift`
- `Sources/a-app-cli/Commands/TearDownCommand.swift`
- `Sources/a-app-cli/Commands/UploadLambdaCommand.swift`
- `Sources/a-app-cli/AWSAuthConfiguration+ArgumentParser.swift`
- `Sources/b-workflow-deploy-remote/DeployWorkflow.swift`
- `Sources/b-workflow-deploy-remote/DestroyWorkflow.swift`
- `Sources/b-workflow-deploy-remote/ResumeMonitoringWorkflow.swift`
- `Sources/b-workflow-deploy-remote/DeployInitWorkflow.swift`
- `Sources/b-workflow-deploy-remote/CloudWatchLogsWorkflow.swift`
- `Sources/b-workflow-deploy-remote/DeployStatusWorkflow.swift`
- `Sources/a-app-mac/Models/DeploymentModel.swift`
- `Sources/a-app-mac/Models/CloudWatchLogsModel.swift`
- `Sources/a-app-mac/UI/RemoteService/RemoteServiceView.swift`
- `Sources/a-app-mac/UI/RemoteService/CDKInfrastructureSectionView.swift`
- `Sources/a-app-mac/UI/RemoteService/CloudWatchLogsSectionView.swift`
- `Sources/a-app-mac/UI/Components/AWSCredentialErrorView.swift`
- `Sources/a-app-mac/UI/Settings/SettingsView.swift`
- `Sources/c-service-deploy-remote/Models/DeploymentState.swift`
- `Sources/c-service-deploy-remote/Models/CDKInfrastructureConfiguration.swift`
- `Sources/c-service-deploy-remote/Auth/AWSAuthConfiguration+Persistence.swift`
- `Sources/c-service-deploy-remote/LambdaService/LambdaBuildService.swift`

**Module name behavior:**
- `AWSSDK` becomes module name `AWSSDK` directly (PascalCase, no hyphens)

### GitHubSDK Migration (Phase 1.7)

**Key changes:**
- Moved `Sources/d-sdk-github/` → `Sources/sdks/GitHubSDK/`
- Updated Package.swift: renamed target from `d-sdk-github` to `GitHubSDK` with explicit path
- Updated all dependency references from `.target(name: "d-sdk-github")` to `.target(name: "GitHubSDK")` (6 references in Package.swift: b-workflow-setup, b-workflow-deploy-remote, a-app-cli, c-service-deploy-remote, a-app-mac, c-service-deploy-remote-tests)
- Updated all imports from `import d_sdk_github` to `import GitHubSDK` (11 files affected)
- Fixed one typealias using fully qualified module name (`d_sdk_github.GitStatus` → `GitHubSDK.GitStatus`)

**Files updated:**
- `Sources/b-workflow-setup/DependencyStatusWorkflow.swift`
- `Sources/b-workflow-deploy-remote/DeployInitWorkflow.swift`
- `Sources/b-workflow-deploy-remote/DeployStatusWorkflow.swift`
- `Sources/b-workflow-deploy-remote/UpdateLambdaWorkflow.swift`
- `Sources/b-workflow-deploy-remote/GitHubCIWorkflow.swift`
- `Sources/a-app-mac/Models/DeploymentModel.swift`
- `Sources/a-app-mac/Models/GitHubCIModel.swift`
- `Sources/a-app-mac/UI/RemoteService/GitHubCISectionView.swift`
- `Sources/c-service-deploy-remote/Models/DeploymentState.swift`
- `Sources/c-service-deploy-remote/GitHubService/GitHubConfiguration.swift`
- `Tests/c-service-deploy-remote-tests/GitHubCLITests.swift`

**Module name behavior:**
- `GitHubSDK` becomes module name `GitHubSDK` directly (PascalCase, no hyphens)

### MinioSDK Migration (Phase 1.8)

**Key changes:**
- Moved `Sources/d-sdk-minio/` → `Sources/sdks/MinioSDK/`
- Updated Package.swift: renamed target from `d-sdk-minio` to `MinioSDK` with explicit path
- Updated dependency reference in `c-service-deploy-local` from `.target(name: "d-sdk-minio")` to `.target(name: "MinioSDK")`
- Updated all imports from `import d_sdk_minio` to `import MinioSDK` (3 files affected)

**Files updated:**
- `Sources/c-service-deploy-local/XcodeLocalDevelopmentService.swift`
- `Sources/c-service-deploy-local/LinuxLocalDevelopmentService.swift`
- `Sources/c-service-deploy-local/EnvironmentVariables.swift`

**Module name behavior:**
- `MinioSDK` becomes module name `MinioSDK` directly (PascalCase, no hyphens)

### PostgreSQLSDK Migration (Phase 1.9)

**Key changes:**
- Moved `Sources/d-sdk-postgresql/` → `Sources/sdks/PostgreSQLSDK/`
- Updated Package.swift: renamed target from `d-sdk-postgresql` to `PostgreSQLSDK` with explicit path
- Updated dependency reference in `c-service-deploy-local` from `.target(name: "d-sdk-postgresql")` to `.target(name: "PostgreSQLSDK")`
- Updated all imports from `import d_sdk_postgresql` to `import PostgreSQLSDK` (3 files affected)

**Files updated:**
- `Sources/c-service-deploy-local/XcodeLocalDevelopmentService.swift`
- `Sources/c-service-deploy-local/LinuxLocalDevelopmentService.swift`
- `Sources/c-service-deploy-local/EnvironmentVariables.swift`

**Module name behavior:**
- `PostgreSQLSDK` becomes module name `PostgreSQLSDK` directly (PascalCase, no hyphens)

### DynamoDBSDK Migration (Phase 1.10)

**Key changes:**
- Moved `Sources/d-sdk-dynamodb/` → `Sources/sdks/DynamoDBSDK/`
- Updated Package.swift: renamed target from `d-sdk-dynamodb` to `DynamoDBSDK` with explicit path
- Updated dependency reference in `c-service-deploy-local` from `.target(name: "d-sdk-dynamodb")` to `.target(name: "DynamoDBSDK")`
- Updated all imports from `import d_sdk_dynamodb` to `import DynamoDBSDK` (3 files affected)

**Files updated:**
- `Sources/c-service-deploy-local/XcodeLocalDevelopmentService.swift`
- `Sources/c-service-deploy-local/LinuxLocalDevelopmentService.swift`
- `Sources/c-service-deploy-local/EnvironmentVariables.swift`

**Module name behavior:**
- `DynamoDBSDK` becomes module name `DynamoDBSDK` directly (PascalCase, no hyphens)

### CLISDKTests Migration (Phase 1.11)

**Key changes:**
- Moved `Tests/d-sdk-cli-tests/` → `Tests/CLISDKTests/`
- Updated Package.swift: renamed test target from `d-sdk-cli-tests` to `CLISDKTests` with explicit path
- Dependencies already referenced new target names (`CLISDK`, `CLIMacrosSDK`) from previous migrations
- No import statement changes needed (test files already used `import CLISDK`)

**Test files migrated:**
- `SdkCliTests.swift` - Core CLI component tests (Git commands, parsers)
- `StandardCommandTests.swift` - Standard Unix command tests (Id, Kill, Lsof, Sh, Open, Rm, Which)
- `CLIOutputStreamTests.swift` - CLI output stream and subscriber tests

**Test verification:**
- All 104 tests pass across 12 test suites

**Note:** This completes Phase 1 (SDKs). All SDK targets and their tests have been migrated to the new `sdks/` folder structure with PascalCase naming.

### StorageService Migration (Phase 2.1)

**Key changes:**
- Created `Sources/services/` folder for service layer targets
- Moved `Sources/c-service-storage/` → `Sources/services/StorageService/`
- Updated Package.swift: renamed target from `c-service-storage` to `StorageService` with explicit path
- Updated all dependency references from `.target(name: "c-service-storage")` to `.target(name: "StorageService")` (3 references in Package.swift: c-service-deploy-local, c-service-deploy-remote, a-app-mac)
- Updated all imports from `import c_service_storage` to `import StorageService` (8 files affected)

**Files updated:**
- `Sources/c-service-deploy-local/XcodeLocalDevelopmentService.swift`
- `Sources/c-service-deploy-local/LinuxLocalDevelopmentService.swift`
- `Sources/c-service-deploy-local/Containers/StorageKeys.swift`
- `Sources/c-service-deploy-remote/GitHubService/GitHubConfiguration.swift`
- `Sources/c-service-deploy-remote/Auth/AWSAuthConfiguration+Persistence.swift`
- `Sources/a-app-mac/Models/LinuxLocalModel.swift`
- `Sources/a-app-mac/Models/AppModel.swift`
- `Sources/a-app-mac/Models/XcodeLocalModel.swift`

**Module name behavior:**
- `StorageService` becomes module name `StorageService` directly (PascalCase, no hyphens)

**Note:** This is the first service layer migration. The `services/` folder now exists for subsequent service migrations.

### ClientService Migration (Phase 2.2)

**Key changes:**
- Moved `Sources/c-service-client/` → `Sources/services/ClientService/`
- Updated Package.swift: renamed target from `c-service-client` to `ClientService` with explicit path
- Updated all dependency references from `.target(name: "c-service-client")` to `.target(name: "ClientService")` (5 references in Package.swift: c-service-deploy-core, c-service-deploy-local, c-service-deploy-remote, a-app-lambda, a-app-mac)
- Updated all imports from `import c_service_client` to `import ClientService` (20 files affected)

**Files updated:**
- `Sources/a-app-mac/Models/XcodeLocalModel.swift`
- `Sources/a-app-mac/Models/AppModel.swift`
- `Sources/a-app-mac/Models/LinuxLocalModel.swift`
- `Sources/a-app-mac/Models/DeploymentModel.swift`
- `Sources/a-app-mac/UI/LocalService/LocalServicesModel.swift`
- `Sources/a-app-mac/UI/Client/S3View.swift`
- `Sources/a-app-mac/UI/Client/PostgresView.swift`
- `Sources/a-app-mac/UI/Client/RemindersView.swift`
- `Sources/a-app-mac/UI/Client/UserFormView.swift`
- `Sources/a-app-mac/UI/Client/APIClient+Previews.swift`
- `Sources/a-app-mac/UI/Client/ClientView.swift`
- `Sources/c-service-deploy-local/LinuxLocalDevelopmentService.swift`
- `Sources/c-service-deploy-local/XcodeLocalDevelopmentService.swift`
- `Sources/c-service-deploy-core/LambdaService.swift`
- `Sources/a-app-lambda/Handlers/APIGatewayHandler.swift`
- `Sources/a-app-lambda/DynamoDB/DynamoDBDataStoreProduction.swift`
- `Sources/a-app-lambda/DynamoDB/DynamoDBDataStoreInterface.swift`
- `Sources/a-app-lambda/DynamoDB/DynamoDBDataStoreAWS.swift`
- `Sources/a-app-lambda/SwiftServerApp.swift`
- `Tests/c-service-deploy-remote-tests/AWSIntegrationTests.swift`

**Module name behavior:**
- `ClientService` becomes module name `ClientService` directly (PascalCase, no hyphens)

### LambdaBuildService Migration (Phase 2.3)

**Key changes:**
- Moved `Sources/c-service-lambda-build/` → `Sources/services/LambdaBuildService/`
- Updated Package.swift: renamed target from `c-service-lambda-build` to `LambdaBuildService` with explicit path
- Updated all dependency references from `.target(name: "c-service-lambda-build")` to `.target(name: "LambdaBuildService")` (4 references in Package.swift: c-service-deploy-local, c-service-deploy-remote, a-app-mac, c-service-deploy-remote-tests)
- Updated all imports from `import c_service_lambda_build` to `import LambdaBuildService` (11 files affected)

**Files updated:**
- `Sources/a-app-mac/Models/LinuxLocalModel.swift`
- `Sources/a-app-mac/Models/XcodeLocalModel.swift`
- `Sources/a-app-mac/UI/LocalService/LocalServicesModel.swift`
- `Sources/a-app-mac/UI/RemoteService/LambdaUploadSectionView.swift`
- `Sources/c-service-deploy-local/LinuxLocalDevelopmentService.swift`
- `Sources/c-service-deploy-local/XcodeLocalDevelopmentService.swift`
- `Sources/c-service-deploy-local/LocalService.swift`
- `Sources/c-service-deploy-remote/LambdaService/LambdaBuildService.swift`
- `Tests/c-service-deploy-remote-tests/BuildScriptTests.swift`
- `Tests/c-service-deploy-remote-tests/SwiftCLITests.swift`

**Module name behavior:**
- `LambdaBuildService` becomes module name `LambdaBuildService` directly (PascalCase, no hyphens)

### DeployCoreService Migration (Phase 2.4)

**Key changes:**
- Moved `Sources/c-service-deploy-core/` → `Sources/services/DeployCoreService/`
- Updated Package.swift: renamed target from `c-service-deploy-core` to `DeployCoreService` with explicit path
- Updated all dependency references from `.target(name: "c-service-deploy-core")` to `.target(name: "DeployCoreService")` (6 references in Package.swift: c-service-deploy-local, c-service-deploy-remote, b-workflow-deploy-remote, b-workflow-deploy-local-xcode, b-workflow-deploy-local-linux, a-app-mac)
- Updated all imports from `import c_service_deploy_core` to `import DeployCoreService` (17 files affected)

**Files updated:**
- `Sources/c-service-deploy-local/LocalService.swift`
- `Sources/c-service-deploy-local/LinuxLocalDevelopmentService.swift`
- `Sources/c-service-deploy-local/XcodeLocalDevelopmentService.swift`
- `Sources/a-app-mac/UI/LocalService/LocalServicesModel.swift`
- `Sources/a-app-mac/UI/LocalService/DockerServicesView.swift`
- `Sources/a-app-mac/Models/XcodeLocalModel.swift`
- `Sources/a-app-mac/Models/LinuxLocalModel.swift`
- `Sources/a-app-mac/Models/DeploymentModel.swift`
- `Sources/a-app-mac/Models/AppModel.swift`
- `Sources/b-workflow-deploy-remote/GitHubCIWorkflow.swift`
- `Sources/b-workflow-deploy-remote/UpdateLambdaWorkflow.swift`
- `Sources/b-workflow-deploy-remote/DeployInitWorkflow.swift`
- `Sources/a-app-cli/Commands/TearDownCommand.swift`
- `Sources/a-app-cli/AWSAuthConfiguration+ArgumentParser.swift`
- `Sources/a-app-cli/Commands/LocalCommand.swift`
- `Sources/b-workflow-deploy-local-linux/LinuxStatusWorkflow.swift`
- `Sources/b-workflow-deploy-local-xcode/XcodeStatusWorkflow.swift`

**Module name behavior:**
- `DeployCoreService` becomes module name `DeployCoreService` directly (PascalCase, no hyphens)

### DeployLocalService Migration (Phase 2.5)

**Key changes:**
- Moved `Sources/c-service-deploy-local/` → `Sources/services/DeployLocalService/`
- Updated Package.swift: renamed target from `c-service-deploy-local` to `DeployLocalService` with explicit path
- Updated all dependency references from `.target(name: "c-service-deploy-local")` to `.target(name: "DeployLocalService")` (5 references in Package.swift: b-workflow-deploy-local-xcode, b-workflow-deploy-local-linux, a-app-cli, a-app-mac, c-service-deploy-remote-tests)
- Updated all imports from `import c_service_deploy_local` to `import DeployLocalService` (27 files affected)
- Updated `@testable import c_service_deploy_local` to `@testable import DeployLocalService` (1 test file)

**Files updated:**
- `Sources/b-workflow-deploy-local-xcode/XcodeStopLambdaWorkflow.swift`
- `Sources/b-workflow-deploy-local-xcode/XcodeCopyConfigWorkflow.swift`
- `Sources/b-workflow-deploy-local-xcode/XcodeStopServicesWorkflow.swift`
- `Sources/b-workflow-deploy-local-xcode/XcodeTestWorkflow.swift`
- `Sources/b-workflow-deploy-local-xcode/XcodeStartAllWorkflow.swift`
- `Sources/b-workflow-deploy-local-xcode/XcodeStatusWorkflow.swift`
- `Sources/b-workflow-deploy-local-xcode/XcodeBuildWorkflow.swift`
- `Sources/b-workflow-deploy-local-xcode/XcodeStartLambdaWorkflow.swift`
- `Sources/b-workflow-deploy-local-xcode/XcodeStopAllWorkflow.swift`
- `Sources/b-workflow-deploy-local-xcode/XcodeStartServicesWorkflow.swift`
- `Sources/b-workflow-deploy-local-linux/LinuxRunInteractiveWorkflow.swift`
- `Sources/b-workflow-deploy-local-linux/LinuxSetupNetworkWorkflow.swift`
- `Sources/b-workflow-deploy-local-linux/LinuxStatusWorkflow.swift`
- `Sources/b-workflow-deploy-local-linux/LinuxStartAllWorkflow.swift`
- `Sources/b-workflow-deploy-local-linux/LinuxStopLambdaWorkflow.swift`
- `Sources/b-workflow-deploy-local-linux/LinuxCopyConfigWorkflow.swift`
- `Sources/b-workflow-deploy-local-linux/LinuxStopAllWorkflow.swift`
- `Sources/b-workflow-deploy-local-linux/LinuxBuildWorkflow.swift`
- `Sources/b-workflow-deploy-local-linux/LinuxStartLambdaWorkflow.swift`
- `Sources/b-workflow-deploy-local-linux/LinuxStartServicesWorkflow.swift`
- `Sources/b-workflow-deploy-local-linux/LinuxTestWorkflow.swift`
- `Sources/b-workflow-deploy-local-linux/LinuxStopServicesWorkflow.swift`
- `Sources/a-app-cli/Commands/LocalCommand.swift`
- `Sources/a-app-mac/Models/LinuxLocalModel.swift`
- `Sources/a-app-mac/Models/XcodeLocalModel.swift`
- `Sources/a-app-mac/UI/LocalService/DockerServicesView.swift`
- `Sources/a-app-mac/UI/LocalService/LocalServicesModel.swift`
- `Tests/c-service-deploy-remote-tests/LinuxDeployTests.swift`

**Module name behavior:**
- `DeployLocalService` becomes module name `DeployLocalService` directly (PascalCase, no hyphens)

**Note:** This completes Phase 2 (Services). All service layer targets have been migrated to the new `services/` folder structure with PascalCase naming.

### SetupFeature Migration (Phase 3.1)

**Key changes:**
- Created `Sources/features/` folder for feature layer targets
- Created `Sources/features/SetupFeature/` with `workflows/` and `services/` subfolders
- Moved `Sources/b-workflow-setup/` files → `Sources/features/SetupFeature/workflows/`
- Moved `Sources/c-service-setup/` files → `Sources/features/SetupFeature/services/`
- Removed old directories after migration
- Updated Package.swift: merged `b-workflow-setup` and `c-service-setup` targets into single `SetupFeature` target
- Updated dependency references in `a-app-mac` from two targets (`b-workflow-setup`, `c-service-setup`) to single `SetupFeature`
- Updated all imports from `import b_workflow_setup` and `import c_service_setup` to `import SetupFeature`
- Removed internal `import c_service_setup` from workflow files (now same module)

**Files moved to workflows/:**
- `DependencyStatusWorkflow.swift`
- `DependencyInstallWorkflow.swift`

**Files moved to services/:**
- `DependencySnapshot.swift`
- `CLIToolStatus.swift`
- `CLITool.swift`

**Files updated (imports):**
- `Sources/a-app-mac/Models/DependencyStatusModel.swift`
- `Sources/a-app-mac/UI/SetupViews.swift`
- `Sources/a-app-mac/UI/LocalService/ServicesView.swift`

**Feature consolidation:**
- Features combine workflow + service code into a single target
- Internal folder organization (`workflows/`, `services/`) provides logical separation without module boundary
- Types from former `c-service-setup` (CLITool, CLIToolStatus, DependencySnapshot) are now public exports of SetupFeature module
- Workflows no longer need to import service types - they're in the same module

**Module name behavior:**
- `SetupFeature` becomes module name `SetupFeature` directly (PascalCase, no hyphens)

**Note:** This is the first feature layer migration. The `features/` folder now exists for subsequent feature migrations.
