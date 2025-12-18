# Model and Feature Target Renaming Specification

**Date**: 2025-12-18
**Status**: In Progress
**Scope**: Rename model types and feature targets for consistency

## Objective

Rename app-layer model types and feature targets to follow a consistent naming convention:
- Models: Use `Deploy*Model` prefix pattern
- Features: Drop redundant "Local" from feature names since the path already indicates locality

## Current State → Target State

### Model Types (App Layer)

| Current Name | New Name | File Location |
|--------------|----------|---------------|
| `DeploymentModel` | `DeployRemoteModel` | Sources/apps/MacApp/Models/ |
| `LinuxLocalModel` | `DeployLocalModel` | Sources/apps/MacApp/Models/ |
| `XcodeLocalModel` | `DeployXcodeModel` | Sources/apps/MacApp/Models/ |

### Feature Targets (Package.swift)

| Current Name | New Name | Directory Path |
|--------------|----------|----------------|
| `DeployLocalLinuxFeature` | `DeployLinuxFeature` | Sources/features/DeployLinuxFeature/ |
| `DeployLocalXcodeFeature` | `DeployXcodeFeature` | Sources/features/DeployXcodeFeature/ |

## Rationale

### Model Renaming

1. **DeploymentModel → DeployRemoteModel**
   - Aligns with the `DeployRemoteFeature` naming pattern
   - Makes it clear this model is for remote (AWS) deployments
   - Distinguishes from local deployment models

2. **LinuxLocalModel → DeployLocalModel**
   - Uses `Deploy*` prefix consistent with other models
   - "Local" indicates this is the primary local development model (Linux container)
   - Removes redundancy since "Linux" is an implementation detail

3. **XcodeLocalModel → DeployXcodeModel**
   - Uses `Deploy*` prefix consistent with other models
   - "Xcode" clearly indicates native macOS development workflow
   - Simpler name that focuses on the development environment

### Feature Renaming

1. **DeployLocalLinuxFeature → DeployLinuxFeature**
   - "Linux" already implies local container-based development
   - Reduces name length without losing meaning
   - Consistent with the target workflow naming (Linux* workflows)

2. **DeployLocalXcodeFeature → DeployXcodeFeature**
   - "Xcode" already implies local native macOS development
   - Reduces name length without losing meaning
   - Consistent with the target workflow naming (Xcode* workflows)

## Implementation Plan

### Phase 1: Model Type Renaming ✅ COMPLETED

**Completed**: 2025-12-18

#### Step 1.1: Rename DeploymentModel → DeployRemoteModel ✅

**File changes:**
- Rename file: `DeploymentModel.swift` → `DeployRemoteModel.swift`
- Rename class: `DeploymentModel` → `DeployRemoteModel`

**Files affected:**
- `Sources/apps/MacApp/Models/DeploymentModel.swift` (rename file + class)
- `Sources/apps/MacApp/Models/AppModel.swift` (update reference)
- `Sources/apps/MacApp/UI/RemoteService/RemoteServiceView.swift` (update reference)
- `Sources/apps/MacApp/UI/RemoteService/CDKInfrastructureSectionView.swift` (update reference)
- `Sources/sdks/AWSSDK/CloudFormation/CloudFormationState.swift` (doc comment)
- `Sources/services/DeployCoreService/LambdaService.swift` (doc comment)
- `Sources/services/DeployLocalService/LocalService.swift` (doc comment)

#### Step 1.2: Rename LinuxLocalModel → DeployLocalModel ✅

**File changes:**
- Rename file: `LinuxLocalModel.swift` → `DeployLocalModel.swift`
- Rename class: `LinuxLocalModel` → `DeployLocalModel`

**Files affected:**
- `Sources/apps/MacApp/Models/LinuxLocalModel.swift` (rename file + class)
- `Sources/apps/MacApp/Models/AppModel.swift` (update reference)
- `Sources/services/DeployCoreService/LambdaService.swift` (doc comment)
- `Sources/services/DeployLocalService/LocalService.swift` (doc comment)

#### Step 1.3: Rename XcodeLocalModel → DeployXcodeModel ✅

**File changes:**
- Rename file: `XcodeLocalModel.swift` → `DeployXcodeModel.swift`
- Rename class: `XcodeLocalModel` → `DeployXcodeModel`

**Files affected:**
- `Sources/apps/MacApp/Models/XcodeLocalModel.swift` (rename file + class)
- `Sources/apps/MacApp/Models/AppModel.swift` (update reference)
- `Sources/services/DeployCoreService/LambdaService.swift` (doc comment)
- `Sources/services/DeployLocalService/LocalService.swift` (doc comment)

**Build verification**: Passed (`swift build` succeeded)

### Phase 2: Feature Target Renaming ✅ COMPLETED

**Completed**: 2025-12-18

#### Step 2.1: Rename DeployLocalLinuxFeature → DeployLinuxFeature ✅

**Changes completed:**
1. Renamed directory: `Sources/features/DeployLocalLinuxFeature/` → `Sources/features/DeployLinuxFeature/`
2. Updated `Package.swift`:
   - Target name: `DeployLocalLinuxFeature` → `DeployLinuxFeature`
   - Path: `"Sources/features/DeployLocalLinuxFeature"` → `"Sources/features/DeployLinuxFeature"`
3. Updated all import statements in dependent files

**Files affected:**
- `Package.swift` (target definition and dependencies for CLIApp, MacApp, and DeployRemoteFeatureTests)
- `Sources/apps/CLIApp/Commands/LocalCommand.swift` (import statement)
- `Sources/apps/MacApp/Models/DeployLocalModel.swift` (import statement)
- `Tests/DeployRemoteFeatureTests/LinuxDeployTests.swift` (import statement)

#### Step 2.2: Rename DeployLocalXcodeFeature → DeployXcodeFeature ✅

**Changes completed:**
1. Renamed directory: `Sources/features/DeployLocalXcodeFeature/` → `Sources/features/DeployXcodeFeature/`
2. Updated `Package.swift`:
   - Target name: `DeployLocalXcodeFeature` → `DeployXcodeFeature`
   - Path: `"Sources/features/DeployLocalXcodeFeature"` → `"Sources/features/DeployXcodeFeature"`
3. Updated all import statements in dependent files

**Files affected:**
- `Package.swift` (target definition and dependencies for CLIApp and MacApp)
- `Sources/apps/CLIApp/Commands/LocalCommand.swift` (import statement)
- `Sources/apps/MacApp/Models/DeployXcodeModel.swift` (import statement)

**Build verification**: Passed (`swift build` succeeded)

### Phase 3: Documentation Updates

Update all references in documentation files:
- `docs/architecture/layered-architecture.md`
- `docs/completed/local-development-workflows.md`
- `docs/completed/workflow-state-model-alignment.md`
- `docs/completed/deployment-architecture-improvements.md`
- `docs/proposed/` - multiple files
- `CLAUDE.md`

## Verification

After completing the renaming:

1. **Build verification:**
   ```bash
   swift build
   ```

2. **Test verification:**
   ```bash
   swift test
   ```

3. **MacApp launch verification:**
   ```bash
   swift run MacApp
   ```

4. **CLIApp verification:**
   ```bash
   swift run CLIApp --help
   swift run CLIApp local --help
   ```

## Summary Table

| Component | Old Name | New Name | Type |
|-----------|----------|----------|------|
| Model | `DeploymentModel` | `DeployRemoteModel` | Class |
| Model | `LinuxLocalModel` | `DeployLocalModel` | Class |
| Model | `XcodeLocalModel` | `DeployXcodeModel` | Class |
| Feature | `DeployLocalLinuxFeature` | `DeployLinuxFeature` | Swift Target |
| Feature | `DeployLocalXcodeFeature` | `DeployXcodeFeature` | Swift Target |

## Rollback Plan

If issues arise, revert the Git commits. Each phase should be committed separately to allow granular rollback:
1. Commit 1: Model type renames
2. Commit 2: Feature target renames
3. Commit 3: Documentation updates
