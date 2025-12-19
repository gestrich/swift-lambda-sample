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

## Phase 2: DeployRemoteFeature Rename (Part 1)

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

**Items: 7**

**Location**: `Sources/features/DeployRemoteFeature/workflows/`

---

## Phase 3: DeployRemoteFeature Rename (Part 2)

**Scope**: Remaining DeployRemoteFeature workflows and state types.

| Current Name | New Name | File |
|--------------|----------|------|
| `CloudWatchLogsWorkflow` | `CloudWatchLogsUseCase` | `CloudWatchLogsWorkflow.swift` → `CloudWatchLogsUseCase.swift` |
| `GitHubMonitorRunWorkflow` | `GitHubMonitorRunUseCase` | `GitHubMonitorRunWorkflow.swift` → `GitHubMonitorRunUseCase.swift` |
| `GitHubPushAndDeployWorkflow` | `GitHubPushAndDeployUseCase` | `GitHubPushAndDeployWorkflow.swift` → `GitHubPushAndDeployUseCase.swift` |
| `ResumeMonitoringWorkflow` | `ResumeMonitoringUseCase` | `ResumeMonitoringWorkflow.swift` → `ResumeMonitoringUseCase.swift` |
| `WorkflowState` | `UseCaseState` | `DeploymentState.swift` |
| `GitHubCIWorkflowError` | `GitHubCIUseCaseError` | `GitHubCITypes.swift` |
| Folder rename | `workflows/` → `usecases/` | `Sources/features/DeployRemoteFeature/` |

**Items: 7**

---

## Phase 4: DeployXcodeFeature Rename

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

---

## Phase 5: DeployLinuxFeature Rename

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

---

## Phase 6: SetupFeature and UI Cleanup

**Scope**: Setup feature workflows, UI components, and documentation updates.

| Current Name | New Name | File |
|--------------|----------|------|
| `DependencyInstallWorkflow` | `DependencyInstallUseCase` | `DependencyInstallWorkflow.swift` → `DependencyInstallUseCase.swift` |
| `DependencyStatusWorkflow` | `DependencyStatusUseCase` | `DependencyStatusWorkflow.swift` → `DependencyStatusUseCase.swift` |
| `WorkflowRow` | `UseCaseRow` | `SetupViews.swift` |
| Folder rename | `workflows/` → `usecases/` | `Sources/features/SetupFeature/` |

**Items: 4**

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
