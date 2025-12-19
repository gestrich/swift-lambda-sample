# Workflow to UseCase Rename

This document outlines the plan to rename `*Workflow` types to `*UseCase` throughout the codebase, aligning with Clean Architecture naming conventions.

## Background

Clean Architecture uses the term "Use Case" to describe application-specific business rules that orchestrate data flow and coordinate entities. While this project does not strictly adhere to Clean Architecture, adopting the `UseCase` naming convention provides clearer intent and aligns with industry-standard terminology.

## Scope

### Files and Types to Rename

| Category | Count | Description |
|----------|-------|-------------|
| Protocol Definitions | 2 | `Workflow`, `StreamingWorkflow` in Uniflow SDK |
| Error Types | 1 | `WorkflowError` in Uniflow SDK |
| Implementations | 35 | `*Workflow` structs across features |
| State Enums | 3 | `WorkflowState`, `XcodeWorkflowState`, `LinuxWorkflowState` |
| Feature Error Types | 2 | `UpdateLambdaWorkflowError`, `GitHubCIWorkflowError` |
| GitHub SDK Types | 3 | `WorkflowRunInfo`, `GitHubWorkflowRun`, `Workflow` (nested struct) |
| UI Components | 1 | `WorkflowRow` view |
| Folders | 4 | `workflows/` directories in each feature |

**Total: ~51 items across 6 phases**

### Out of Scope

GitHub SDK types that refer to actual GitHub Actions workflows (not our UseCase abstraction) will be evaluated case-by-case. `GitHubWorkflowRun` and `WorkflowRunInfo` refer to GitHub's concept of "workflow runs" and may retain their names.

---

## Phase 1: Uniflow SDK Protocol Rename ✅ COMPLETED

**Scope**: Core protocol definitions that all use cases depend on.

| Current Name | New Name | File |
|--------------|----------|------|
| `Workflow` | `UseCase` | `Sources/sdks/Uniflow/Workflow.swift` → `UseCase.swift` |
| `StreamingWorkflow` | `StreamingUseCase` | `Sources/sdks/Uniflow/StreamingWorkflow.swift` → `StreamingUseCase.swift` |
| `WorkflowError` | `UseCaseError` | `Sources/sdks/Uniflow/WorkflowError.swift` → `UseCaseError.swift` |

**Items: 3**

**Completion Notes**:
- Files renamed using `git mv`
- Protocol names updated: `Workflow` → `UseCase`, `StreamingWorkflow` → `StreamingUseCase`
- Error type renamed: `WorkflowError` → `UseCaseError`
- All 29 conforming types updated across all feature modules to use `StreamingUseCase`
- Build verified successfully

**Technical Notes**:
- The original spec mentioned Phase 1 would "cause compilation errors until subsequent phases complete." However, by updating all protocol conformances (`struct X: StreamingWorkflow` → `struct X: StreamingUseCase`) in the same phase, the build remains functional.
- Struct/file names retain "Workflow" suffix - these will be renamed in later phases (2-6).

---

## Phase 2: DeployRemoteFeature Rename (Part 1) ✅ COMPLETED

**Scope**: First half of DeployRemoteFeature workflows and supporting types.

| Current Name | New Name | File |
|--------------|----------|------|
| `DeployInitWorkflow` | `DeployInitUseCase` | `DeployInitWorkflow.swift` → `DeployInitUseCase.swift` |
| `DeployWorkflow` | `DeployUseCase` | `DeployWorkflow.swift` → `DeployUseCase.swift` |
| `DeployStatusWorkflow` | `DeployStatusUseCase` | `DeployStatusWorkflow.swift` → `DeployStatusUseCase.swift` |
| `DestroyWorkflow` | `DestroyUseCase` | `DestroyWorkflow.swift` → `DestroyUseCase.swift` |
| `UpdateLambdaWorkflow` | `UpdateLambdaUseCase` | `UpdateLambdaWorkflow.swift` → `UpdateLambdaUseCase.swift` |
| `UpdateLambdaWorkflowError` | `UpdateLambdaUseCaseError` | (same file as above) |
| `RefreshWorkflow` | `RefreshUseCase` | `RefreshWorkflow.swift` → `RefreshUseCase.swift` |
| `ResumeMonitoringWorkflow` | `ResumeMonitoringUseCase` | `ResumeMonitoringWorkflow.swift` → `ResumeMonitoringUseCase.swift` |

**Items: 8** (originally 7, +1 `ResumeMonitoringWorkflow` moved from Phase 3)

**Location**: `Sources/features/DeployRemoteFeature/workflows/`

**Completion Notes**:
- Files renamed using `git mv`
- All type names updated: struct names, Components.workflow → Components.useCase
- Error type renamed: `UpdateLambdaWorkflowError` → `UpdateLambdaUseCaseError` with updated error cases
- All CLI commands updated (DeployInitCommand, DeployCommand, StatusCommand, TearDownCommand, UpdateLambdaCommand)
- MacApp's DeployRemoteModel updated to use new UseCase names
- Documentation comments updated to use "use case" terminology
- Build verified successfully

**Technical Notes**:
- `ResumeMonitoringWorkflow` was included in this phase since it was referenced by `RefreshUseCase` and needed to be renamed together
- The `Components.workflow` property was renamed to `Components.useCase` in all affected types
- The error type's `.workflowFailed` case was renamed to `.githubActionsFailed` for clarity

---

## Phase 3: DeployRemoteFeature Rename (Part 2) ✅ COMPLETED

**Scope**: Remaining DeployRemoteFeature workflows and state types.

| Current Name | New Name | File |
|--------------|----------|------|
| `CloudWatchLogsWorkflow` | `CloudWatchLogsUseCase` | `CloudWatchLogsWorkflow.swift` → `CloudWatchLogsUseCase.swift` |
| `GitHubMonitorRunWorkflow` | `GitHubMonitorRunUseCase` | `GitHubMonitorRunWorkflow.swift` → `GitHubMonitorRunUseCase.swift` |
| `GitHubPushAndDeployWorkflow` | `GitHubPushAndDeployUseCase` | `GitHubPushAndDeployWorkflow.swift` → `GitHubPushAndDeployUseCase.swift` |
| `WorkflowState` | `UseCaseState` | `DeploymentState.swift` |
| `GitHubCIWorkflowError` | `GitHubCIUseCaseError` | `GitHubCITypes.swift` |
| Folder rename | `workflows/` → `usecases/` | `Sources/features/DeployRemoteFeature/` |

**Items: 6** (reduced from 7, `ResumeMonitoringWorkflow` moved to Phase 2)

**Completion Notes**:
- Files renamed using `git mv`
- All type names updated: `CloudWatchLogsWorkflow` → `CloudWatchLogsUseCase`, `GitHubMonitorRunWorkflow` → `GitHubMonitorRunUseCase`, `GitHubPushAndDeployWorkflow` → `GitHubPushAndDeployUseCase`
- `WorkflowState` renamed to `UseCaseState` in DeploymentState.swift
- `GitHubCIWorkflowError` renamed to `GitHubCIUseCaseError` with `.workflowFailed` → `.githubActionsFailed`
- Folder renamed: `workflows/` → `usecases/` in DeployRemoteFeature
- All MacApp models updated: DeployRemoteModel, GitHubCIModel, CloudWatchLogsModel
- MacApp views updated: CDKInfrastructureSectionView, CloudWatchLogsSectionView
- CLI commands updated: DeployInitCommand
- Private helper renamed: `makeWorkflowState` → `makeUseCaseState` in ResumeMonitoringUseCase
- Build verified successfully

**Technical Notes**:
- The `ModelState.workflowState` property was renamed to `useCaseState` in DeployRemoteModel
- Documentation comments updated to use "use case" terminology consistently
- The error type's `.workflowFailed` case was renamed to `.githubActionsFailed` for clarity (matches UpdateLambdaUseCaseError)

---

## Phase 4: DeployXcodeFeature Rename ✅ COMPLETED

**Scope**: All Xcode local development workflows.

| Current Name | New Name | File |
|--------------|----------|------|
| `XcodeBuildWorkflow` | `XcodeBuildUseCase` | `XcodeBuildWorkflow.swift` → `XcodeBuildUseCase.swift` |
| `XcodeStartLambdaWorkflow` | `XcodeStartLambdaUseCase` | `XcodeStartLambdaWorkflow.swift` → `XcodeStartLambdaUseCase.swift` |
| `XcodeStopLambdaWorkflow` | `XcodeStopLambdaUseCase` | `XcodeStopLambdaWorkflow.swift` → `XcodeStopLambdaUseCase.swift` |
| `XcodeStartServicesWorkflow` | `XcodeStartServicesUseCase` | `XcodeStartServicesWorkflow.swift` → `XcodeStartServicesUseCase.swift` |
| `XcodeStopServicesWorkflow` | `XcodeStopServicesUseCase` | `XcodeStopServicesWorkflow.swift` → `XcodeStopServicesUseCase.swift` |
| `XcodeStartAllWorkflow` | `XcodeStartAllUseCase` | `XcodeStartAllWorkflow.swift` → `XcodeStartAllUseCase.swift` |
| `XcodeStopAllWorkflow` | `XcodeStopAllUseCase` | `XcodeStopAllWorkflow.swift` → `XcodeStopAllUseCase.swift` |
| `XcodeStatusWorkflow` | `XcodeStatusUseCase` | `XcodeStatusWorkflow.swift` → `XcodeStatusUseCase.swift` |
| `XcodeTestWorkflow` | `XcodeTestUseCase` | `XcodeTestWorkflow.swift` → `XcodeTestUseCase.swift` |
| `XcodeCopyConfigWorkflow` | `XcodeCopyConfigUseCase` | `XcodeCopyConfigWorkflow.swift` → `XcodeCopyConfigUseCase.swift` |
| `XcodeWorkflowState` | `XcodeUseCaseState` | `XcodeDeploymentState.swift` |
| Folder rename | `workflows/` → `usecases/` | `Sources/features/DeployXcodeFeature/` |

**Items: 12**

**Completion Notes**:
- Files renamed using `git mv`
- All 10 use case type names updated: struct names, `Components.workflow` → `Components.useCase`
- State type renamed: `XcodeWorkflowState` → `XcodeUseCaseState`
- CLIApp DeployXcodeCommand updated to use new UseCase names and `Components.useCase`
- CLIApp DeployXcodeProgressPrinters updated to use `XcodeUseCaseState` and `XcodeCopyConfigUseCase.State`
- MacApp DeployXcodeModel updated:
  - All use case instantiation references updated
  - `ModelState.workflowState` property renamed to `useCaseState`
  - `ModelState.operating` case updated to use `XcodeUseCaseState`
  - Documentation comments updated to use "use case" terminology
- Folder renamed: `workflows/` → `usecases/` in DeployXcodeFeature
- Build verified successfully

**Technical Notes**:
- The `XcodeCopyConfigUseCase` uses its own nested `State` type rather than `XcodeUseCaseState`
- Internal method names like `runWorkflow` were renamed to `runUseCase` in all use case implementations
- Comments referencing "workflow" terminology were updated to "use case"

---

## Phase 5: DeployLinuxFeature Rename ✅ COMPLETED

**Scope**: All Linux container development workflows.

| Current Name | New Name | File |
|--------------|----------|------|
| `LinuxBuildWorkflow` | `LinuxBuildUseCase` | `LinuxBuildWorkflow.swift` → `LinuxBuildUseCase.swift` |
| `LinuxStartLambdaWorkflow` | `LinuxStartLambdaUseCase` | `LinuxStartLambdaWorkflow.swift` → `LinuxStartLambdaUseCase.swift` |
| `LinuxStopLambdaWorkflow` | `LinuxStopLambdaUseCase` | `LinuxStopLambdaWorkflow.swift` → `LinuxStopLambdaUseCase.swift` |
| `LinuxStartServicesWorkflow` | `LinuxStartServicesUseCase` | `LinuxStartServicesWorkflow.swift` → `LinuxStartServicesUseCase.swift` |
| `LinuxStopServicesWorkflow` | `LinuxStopServicesUseCase` | `LinuxStopServicesWorkflow.swift` → `LinuxStopServicesUseCase.swift` |
| `LinuxStartAllWorkflow` | `LinuxStartAllUseCase` | `LinuxStartAllWorkflow.swift` → `LinuxStartAllUseCase.swift` |
| `LinuxStopAllWorkflow` | `LinuxStopAllUseCase` | `LinuxStopAllWorkflow.swift` → `LinuxStopAllUseCase.swift` |
| `LinuxStatusWorkflow` | `LinuxStatusUseCase` | `LinuxStatusWorkflow.swift` → `LinuxStatusUseCase.swift` |
| `LinuxTestWorkflow` | `LinuxTestUseCase` | `LinuxTestWorkflow.swift` → `LinuxTestUseCase.swift` |
| `LinuxSetupNetworkWorkflow` | `LinuxSetupNetworkUseCase` | `LinuxSetupNetworkWorkflow.swift` → `LinuxSetupNetworkUseCase.swift` |
| `LinuxCopyConfigWorkflow` | `LinuxCopyConfigUseCase` | `LinuxCopyConfigWorkflow.swift` → `LinuxCopyConfigUseCase.swift` |
| `LinuxRunInteractiveWorkflow` | `LinuxRunInteractiveUseCase` | `LinuxRunInteractiveWorkflow.swift` → `LinuxRunInteractiveUseCase.swift` |
| `LinuxWorkflowState` | `LinuxUseCaseState` | `LinuxDeploymentState.swift` |
| Folder rename | `workflows/` → `usecases/` | `Sources/features/DeployLinuxFeature/` |

**Items: 14**

**Completion Notes**:
- Files renamed using `git mv`
- All 12 use case type names updated: struct names, `Components.workflow` → `Components.useCase`
- State type renamed: `LinuxWorkflowState` → `LinuxUseCaseState`
- CLIApp DeployLinuxCommand updated to use new UseCase names and `Components.useCase`
- CLIApp DeployLinuxProgressPrinters updated to use `LinuxUseCaseState`, `LinuxCopyConfigUseCase.State`, `LinuxSetupNetworkUseCase.State`, and `LinuxRunInteractiveUseCase.State`
- MacApp DeployLinuxModel updated:
  - All use case instantiation references updated
  - `ModelState.workflowState` property renamed to `useCaseState`
  - `ModelState.operating` case updated to use `LinuxUseCaseState`
  - Documentation comments updated to use "use case" terminology
- Folder renamed: `workflows/` → `usecases/` in DeployLinuxFeature
- Build verified successfully

**Technical Notes**:
- Similar to Phase 4, use cases like `LinuxCopyConfigUseCase`, `LinuxSetupNetworkUseCase`, and `LinuxRunInteractiveUseCase` use their own nested `State` type rather than `LinuxUseCaseState`
- Internal method names like `runWorkflow` were renamed to `runUseCase` in all use case implementations
- Comments referencing "workflow" terminology were updated to "use case"
- The `LinuxRunInteractiveUseCase` internally calls `LinuxBuildUseCase` when build is needed

---

## Phase 6: SetupFeature and UI Cleanup ✅ COMPLETED

**Scope**: Setup feature workflows, UI components, and documentation updates.

| Current Name | New Name | File |
|--------------|----------|------|
| `DependencyInstallWorkflow` | `DependencyInstallUseCase` | `DependencyInstallWorkflow.swift` → `DependencyInstallUseCase.swift` |
| `DependencyStatusWorkflow` | `DependencyStatusUseCase` | `DependencyStatusWorkflow.swift` → `DependencyStatusUseCase.swift` |
| `WorkflowRow` | `UseCaseRow` | `SetupViews.swift` |
| Folder rename | `workflows/` → `usecases/` | `Sources/features/SetupFeature/` |

**Items: 4**

**Completion Notes**:
- Files renamed using `git mv`
- All 2 use case type names updated: `DependencyInstallWorkflow` → `DependencyInstallUseCase`, `DependencyStatusWorkflow` → `DependencyStatusUseCase`
- UI component renamed: `WorkflowRow` → `UseCaseRow` in SetupViews.swift
- Folder renamed: `workflows/` → `usecases/` in SetupFeature
- MacApp's DependencyStatusModel updated:
  - Property names updated: `statusWorkflow` → `statusUseCase`, `installWorkflow` → `installUseCase`
  - All instantiation and streaming references updated to use new UseCase names
  - Loop variable names updated: `workflowState` → `useCaseState`
  - Documentation comments updated to use "use case" terminology
- Documentation comments in use case files updated to use "use case" terminology
- Build verified successfully

**Technical Notes**:
- `DependencyInstallUseCase` internally creates a `DependencyStatusUseCase` to verify tool installation
- The `UseCaseRow` view is a private UI component used in the OverviewView to display Learn/Setup/Deploy rows
- Internal comments referencing "workflow" were updated to "use case" throughout

---

## Phase 7: Documentation Updates

Update all documentation to reflect the new naming:

| File | Changes |
|------|---------|
| `CLAUDE.md` | Replace "workflow" references with "use case" |
| `docs/architecture/layered-architecture.md` | Update layer descriptions, protocol references |
| `docs/architecture/documentation.md` | Update any workflow mentions |
| `README.md` | Update if workflow terminology appears |

**Notes**:
- Remove all references to the old "Workflow" naming
- Explain that `UseCase` follows Clean Architecture conventions
- Note that the project does not strictly adhere to Clean Architecture

---

## Execution Notes

### Per-Phase Checklist

For each phase:

1. [ ] Rename files using `git mv`
2. [ ] Update type names (struct/protocol/enum)
3. [ ] Update all references in the same module
4. [ ] Update references in dependent modules
5. [ ] Update Package.swift if target names change
6. [ ] Run `swift build` to verify compilation
7. [ ] Run tests to verify functionality
8. [ ] Commit with descriptive message

### Build Verification

After each phase, verify the build:

```bash
swift build
swift test
```

### Git Strategy

Each phase should be a single commit:

```
Phase 1: Rename Uniflow SDK protocols (Workflow → UseCase)
Phase 2: Rename DeployRemoteFeature use cases (part 1)
Phase 3: Rename DeployRemoteFeature use cases (part 2)
Phase 4: Rename DeployXcodeFeature use cases
Phase 5: Rename DeployLinuxFeature use cases
Phase 6: Rename SetupFeature use cases and UI
Phase 7: Update documentation
```

---

## GitHub SDK Decision

The following types in GitHubSDK refer to GitHub Actions "workflows" (GitHub's terminology), not our UseCase abstraction:

- `GitHubWorkflowRun` - Represents a GitHub Actions workflow run
- `WorkflowRunInfo` - Information about a GitHub Actions run
- `Workflow` (nested struct in `Gh`) - GitHub CLI workflow operations

**Decision**: Keep these names unchanged. They refer to GitHub's concept of workflows, not our application use cases.
