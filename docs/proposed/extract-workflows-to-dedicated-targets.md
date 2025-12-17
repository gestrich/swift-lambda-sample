# Extract Workflows to Dedicated Targets

**Date:** 2025-12-17
**Status:** In Progress (Phases 1-2 Complete, Phase 4 Partially Complete)

## Goal

Create dedicated `workflows-*` targets to separate application logic (workflows) from services. This makes it easy to navigate the project and find where orchestration logic lives.

## Motivation

Currently, workflows live alongside models, configuration, and auth code in service targets. While this works, it conflates two distinct responsibilities:
- **Services**: Models, configuration, auth, stateful utilities
- **Workflows**: Multi-step orchestration returning `AsyncThrowingStream<Progress, Error>`

By extracting workflows to their own layer, developers can:
1. Quickly find all application orchestration logic in `workflows-*` targets
2. Understand the dependency hierarchy at a glance (workflows use services and SDKs)
3. Keep service targets focused on models and configuration

## New Architecture

```
┌─────────────────────────────────────────────┐
│ APP LAYER                                    │
│ app-mac · app-cli · app-lambda               │
└──────────────┬──────────────────────────────┘
               │ uses
               ▼
┌─────────────────────────────────────────────┐
│ WORKFLOW LAYER (NEW)                         │
│ workflows-deploy-remote · workflows-setup    │
└──────────────┬──────────────────────────────┘
               │ uses
               ▼
┌─────────────────────────────────────────────┐
│ SERVICE LAYER                                │
│ service-deploy-remote (models, auth, config) │
│ service-deploy-local · service-storage       │
└──────────────┬──────────────────────────────┘
               │ uses
               ▼
┌─────────────────────────────────────────────┐
│ SDK LAYER                                    │
│ sdk-aws · sdk-github · sdk-cli               │
└─────────────────────────────────────────────┘
```

**Key rule:** Workflows depend on services and SDKs, but never vice versa.

## Changes Summary

| Target | Action |
|--------|--------|
| `workflows-deploy-remote` | **NEW** - 8 workflows from service-deploy-remote |
| `workflows-setup` | **RENAME** from service-setup (all 5 files) |
| `service-deploy-remote` | **KEEP** Models/, Auth/, GitHubService/, LambdaService/ - **REMOVE** Workflows/ |
| `app-cli` | Update imports and dependencies |
| `app-mac` | Update imports and dependencies |

---

## Phase 1: Create workflows-deploy-remote Target

### 1.1 Create directory and move files

Create: `Sources/workflows-deploy-remote/`

Move these 8 files from `Sources/service-deploy-remote/Workflows/`:
- `DeployWorkflow.swift`
- `DeployInitWorkflow.swift`
- `DeployStatusWorkflow.swift`
- `DestroyWorkflow.swift`
- `UpdateLambdaWorkflow.swift`
- `GitHubCIWorkflow.swift`
- `CloudWatchLogsWorkflow.swift`
- `ResumeMonitoringWorkflow.swift`

### 1.2 Add target to Package.swift

```swift
.target(
    name: "workflows-deploy-remote",
    dependencies: [
        .target(name: "sdk-cli"),
        .target(name: "sdk-aws"),
        .target(name: "sdk-github"),
        .target(name: "service-deploy-remote"),
        .target(name: "service-deploy-core"),
    ]
),
```

### 1.3 Update workflow imports

Add `import service_deploy_remote` to workflow files that reference types like:
- `InfrastructureShape`
- `CDKStackConfiguration`
- `AWSAuthConfiguration`
- `GitHubConfiguration`

### 1.4 Verification

```bash
swift build --target workflows-deploy-remote
```

### 1.5 Completion Notes ✅

**Completed:** 2025-12-17

- Created `Sources/workflows-deploy-remote/` directory
- Moved all 8 workflow files via `git mv`
- Removed empty `Sources/service-deploy-remote/Workflows/` directory
- Added `workflows-deploy-remote` target to Package.swift with dependencies:
  - `sdk-cli`, `sdk-aws`, `sdk-github`, `service-deploy-remote`, `service-deploy-core`
- Added `import service_deploy_remote` to 7 of 8 workflow files (CloudWatchLogsWorkflow.swift didn't need it)
- Build verification passed: `swift build --target workflows-deploy-remote`

---

## Phase 2: Rename service-setup to workflows-setup

### 2.1 Rename directory

```bash
git mv Sources/service-setup Sources/workflows-setup
```

Files (all move together):
- `CLITool.swift`
- `CLIToolStatus.swift`
- `DependencySnapshot.swift`
- `DependencyStatusWorkflow.swift`
- `DependencyInstallWorkflow.swift`

### 2.2 Update Package.swift

Rename target from `service-setup` to `workflows-setup`:

```swift
.target(
    name: "workflows-setup",
    dependencies: [
        .target(name: "sdk-cli"),
        .target(name: "sdk-cli-brew"),
        .target(name: "sdk-cli-node"),
        .target(name: "sdk-cli-docker"),
        .target(name: "sdk-aws"),
        .target(name: "sdk-github"),
    ]
),
```

### 2.3 Verification

```bash
swift build --target workflows-setup
```

### 2.4 Completion Notes ✅

**Completed:** 2025-12-17

- Renamed directory via `git mv Sources/service-setup Sources/workflows-setup`
- Updated Package.swift: renamed target from `service-setup` to `workflows-setup`
- Updated app-mac dependency in Package.swift: `service-setup` → `workflows-setup`
- Updated imports in app-mac source files:
  - `Sources/app-mac/Models/DependencyStatusModel.swift`: `import service_setup` → `import workflows_setup`
  - `Sources/app-mac/UI/SetupViews.swift`: `import service_setup` → `import workflows_setup`
  - `Sources/app-mac/UI/LocalService/ServicesView.swift`: `import service_setup` → `import workflows_setup`
- Build verification passed: `swift build --target workflows-setup`

**Note:** Phase 4 app layer updates were partially completed here to enable successful build. Added `workflows-deploy-remote` dependency and imports to both app-cli and app-mac.

---

## Phase 3: Update service-deploy-remote

### 3.1 Remove empty Workflows directory

After moving files in Phase 1:

```bash
rmdir Sources/service-deploy-remote/Workflows
```

### 3.2 Update Package.swift dependencies

Remove `sdk-github` from service-deploy-remote dependencies if only workflows used it.

### 3.3 Verification

```bash
swift build --target service-deploy-remote
```

---

## Phase 4: Update App Layer

### 4.1 Update app-cli

**Package.swift dependencies:**
- Add: `workflows-deploy-remote`
- Keep: `service-deploy-remote` (for AWSAuthConfiguration, etc.)

**Files to update imports:**

| File | Add Import |
|------|------------|
| `Sources/app-cli/Commands/DeployCommand.swift` | `import workflows_deploy_remote` |
| `Sources/app-cli/Commands/DeployInitCommand.swift` | `import workflows_deploy_remote` |
| `Sources/app-cli/Commands/UpdateLambdaCommand.swift` | `import workflows_deploy_remote` |
| `Sources/app-cli/Commands/StatusCommand.swift` | `import workflows_deploy_remote` |
| `Sources/app-cli/Commands/TearDownCommand.swift` | `import workflows_deploy_remote` |
| `Sources/app-cli/Commands/LogsCommand.swift` | `import workflows_deploy_remote` |

### 4.2 Update app-mac

**Package.swift dependencies:**
- Add: `workflows-deploy-remote`
- Change: `service-setup` → `workflows-setup`
- Keep: `service-deploy-remote` (for non-workflow types)

**Files to update imports:**

| File | Change |
|------|--------|
| `Sources/app-mac/Models/DeploymentModel.swift` | Add `import workflows_deploy_remote` |
| `Sources/app-mac/Models/DependencyStatusModel.swift` | Change `import service_setup` → `import workflows_setup` |

### 4.3 Verification

```bash
swift build --target app-cli
swift build --target app-mac
```

### 4.4 Partial Completion Notes ✅

**Completed:** 2025-12-17 (during Phase 2)

These changes were required during Phase 2 to enable successful build:

**Package.swift updates:**
- Added `workflows-deploy-remote` dependency to `app-cli`
- Added `workflows-deploy-remote` dependency to `app-mac`
- Changed `service-setup` → `workflows-setup` in `app-mac`

**app-cli import updates:**
- `Sources/app-cli/Commands/DeployCommand.swift`: Added `import workflows_deploy_remote`
- `Sources/app-cli/Commands/DeployInitCommand.swift`: Added `import workflows_deploy_remote`
- `Sources/app-cli/Commands/StatusCommand.swift`: Added `import workflows_deploy_remote`
- `Sources/app-cli/Commands/TearDownCommand.swift`: Added `import workflows_deploy_remote`
- `Sources/app-cli/Commands/UpdateLambdaCommand.swift`: Added `import workflows_deploy_remote`

**app-mac import updates:**
- `Sources/app-mac/Models/DeploymentModel.swift`: Added `import workflows_deploy_remote`
- `Sources/app-mac/Models/DependencyStatusModel.swift`: Changed `import service_setup` → `import workflows_setup`
- `Sources/app-mac/Models/CloudWatchLogsModel.swift`: Added `import workflows_deploy_remote`
- `Sources/app-mac/Models/GitHubCIModel.swift`: Added `import workflows_deploy_remote`
- `Sources/app-mac/UI/SetupViews.swift`: Changed `import service_setup` → `import workflows_setup`
- `Sources/app-mac/UI/LocalService/ServicesView.swift`: Changed `import service_setup` → `import workflows_setup`
- `Sources/app-mac/UI/RemoteService/CloudWatchLogsSectionView.swift`: Added `import workflows_deploy_remote`
- `Sources/app-mac/UI/RemoteService/GitHubCISectionView.swift`: Added `import workflows_deploy_remote`
- `Sources/app-mac/UI/RemoteService/RemoteServiceView.swift`: Added `import workflows_deploy_remote`

**Build verification passed:** `swift build` (full build succeeds)

---

## Phase 5: Update Documentation

### 5.1 Update docs/architecture/layered-architecture.md

- Add WORKFLOW layer to the diagram
- Add `workflows-*` to target naming examples
- Document the workflow layer's responsibilities

### 5.2 Update CLAUDE.md

- Update project structure section
- Update architecture diagram to show 4 layers

---

## Files Modified

**New directories:**
- `Sources/workflows-deploy-remote/` (8 files moved)

**Renamed directories:**
- `Sources/service-setup/` → `Sources/workflows-setup/`

**Modified:**
- `Package.swift`
- `Sources/app-cli/Commands/*.swift` (6 files)
- `Sources/app-mac/Models/DeploymentModel.swift`
- `Sources/app-mac/Models/DependencyStatusModel.swift`
- `docs/architecture/layered-architecture.md`
- `CLAUDE.md`

**Deleted:**
- `Sources/service-deploy-remote/Workflows/` (directory removed after move)

---

## Success Criteria

1. `swift build` succeeds for all targets
3. `swift run SwiftDeploy --help` works
4. Mac app launches and functions correctly
5. All workflow types are accessible from `workflows-*` imports
6. Service targets no longer export workflow types

---

## Related Documentation

- [Layered Architecture](../architecture/layered-architecture.md)
- [Workflow Refactor (completed)](workflow-refactor.md)
