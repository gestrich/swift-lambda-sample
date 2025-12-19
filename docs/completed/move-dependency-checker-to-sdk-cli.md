# Distribute DependencyCheckerService to SDK Clients

## Status: Completed

**Created:** 2025-12-17
**Completed:** 2025-12-17

## Overview

This document plans the elimination of `DependencyCheckerService` by distributing `isInstalled()` checks to individual SDK clients. Each CLI-wrapping client will gain an `isInstalled()` method, and CLI program definitions currently in the wrong layer will be moved to appropriate SDK targets.

## Implementation Summary

All phases have been completed successfully. The migration distributed dependency checking from a centralized `DependencyCheckerService` to individual SDK clients, following the layered architecture principles.

### Changes Made

1. **Created `sdk-cli-brew` target** with:
   - `Brew.swift` - CLI command definitions (moved from service-deploy-remote)
   - `Homebrew.swift` - Shell commands for Homebrew installation (moved from service-deploy-remote)
   - `BrewClient.swift` - Client with `isInstalled()`, `version()`, `install()`, `uninstall()`
   - `BrewError.swift` - Error type

2. **Created `sdk-cli-node` target** with:
   - `Node.swift` - CLI command definitions (moved from service-deploy-remote)
   - `Npm.swift` - npm CLI commands (moved from sdk-aws)
   - `NodeClient.swift` - Client with `isInstalled()` and `version()`
   - `NpmClient.swift` - Client for npm operations
   - `NodeError.swift` - Error type

3. **Updated existing SDK clients**:
   - `DockerClient` (sdk-cli-docker): Added `isInstalled()` instance method
   - `CDKClient` (sdk-aws): Added `isInstalled(cliClient:)` static method
   - `GitHubCLIClient` (sdk-github): Added `isInstalled(cliClient:)` static method
   - Created new `AWSCLIClient` (sdk-aws/AWSCLI/) with `isInstalled()` and `version()`

4. **Updated consumers**:
   - `DependencyStatusModel` now uses individual SDK clients instead of `DependencyCheckerService`
   - Introduced `DependencyUIState` enum (app-layer) replacing `DependencyInstallStatus`
   - Updated `SetupViews.swift` and `ServicesView.swift` to use new enum

5. **Updated Package.swift**:
   - Added `sdk-cli-brew` and `sdk-cli-node` targets
   - Added `sdk-cli-node` as dependency of `sdk-aws` (for CDKClient npm usage)
   - Added all new SDK targets to `app-mac` dependencies

6. **Deleted old files**:
   - `service-deploy-remote/Core/DependencyCheckerService.swift`
   - `service-deploy-remote/ToolsService/CLI/Brew.swift`
   - `service-deploy-remote/ToolsService/CLI/Homebrew.swift`
   - `service-deploy-remote/ToolsService/CLI/Node.swift`
   - `sdk-aws/CLI/NpmCommand.swift`

## Final File Structure

```
Sources/
├── sdk-cli-brew/               # NEW
│   ├── Brew.swift              # Moved from service-deploy-remote
│   ├── Homebrew.swift          # Moved from service-deploy-remote
│   ├── BrewClient.swift        # New client
│   └── BrewError.swift         # New error type
├── sdk-cli-node/               # NEW
│   ├── Node.swift              # Moved from service-deploy-remote
│   ├── Npm.swift               # Moved from sdk-aws/CLI/
│   ├── NodeClient.swift        # New client
│   ├── NpmClient.swift         # New client
│   └── NodeError.swift         # New error type
├── sdk-cli-docker/
│   └── DockerClient.swift      # Added isInstalled()
├── sdk-aws/
│   ├── AWSCLI/
│   │   └── AWSCLIClient.swift  # NEW
│   └── CDK/
│       └── CDKClient.swift     # Added static isInstalled(cliClient:)
├── sdk-github/
│   └── GitHubCLIClient.swift   # Added static isInstalled(cliClient:)
└── app-mac/
    └── Models/
        └── DependencyStatusModel.swift  # Updated to use SDK clients
```

## Technical Notes

### Static vs Instance Methods for isInstalled()

For clients that require additional constructor parameters beyond `CLIClient`:
- `CDKClient` needs `cdkDirectory` and `credentialProvider`
- `GitHubCLIClient` needs `repository`

We used **static methods** for these clients:
```swift
public static func isInstalled(cliClient: CLIClient) async -> Bool
```

This allows checking installation without needing to construct a full client instance.

### DependencyUIState vs DependencyInstallStatus

The old `DependencyInstallStatus` enum had an associated value for version:
```swift
case installed(version: String?)
```

The new `DependencyUIState` is simplified since version display was removed from the UI:
```swift
case installed  // No associated value
```

### sdk-aws Dependency on sdk-cli-node

The `sdk-aws` target now depends on `sdk-cli-node` because `CDKClient` uses `Npm` commands for installing dependencies and building TypeScript.

## Migration Steps (Completed)

### Phase 1: Create New SDK Targets ✅

1. [x] **Create `sdk-cli-brew` target**
   - Add target to Package.swift
   - Move `Brew.swift` from service-deploy-remote
   - Create `BrewClient.swift` with `isInstalled()` and `version()`
   - Create `BrewError.swift`

2. [x] **Create `sdk-cli-node` target**
   - Add target to Package.swift
   - Move `Node.swift` from service-deploy-remote
   - Move `NpmCommand.swift` from sdk-aws/CLI/
   - Create `NodeClient.swift` with `isInstalled()` and `version()`
   - Create `NodeError.swift`

### Phase 2: Update Existing SDK Clients ✅

3. [x] **Add `isInstalled()` to DockerClient**
   - Add method to check Docker installation

4. [x] **Add `isInstalled()` to CDKClient**
   - Add static method to check CDK installation

5. [x] **Add `isInstalled()` to GitHubCLIClient**
   - Add static method to check gh CLI installation

6. [x] **Create AWSCLIClient**
   - Create `Sources/sdk-aws/AWSCLI/AWSCLIClient.swift`
   - Add `isInstalled()` and `version()` methods

### Phase 3: Update Consumers ✅

7. [x] **Update DependencyStatusModel**
   - Import new SDK targets
   - Replace DependencyCheckerService with individual clients
   - Create app-layer `DependencyUIState` enum

8. [x] **Update Package.swift dependencies**
   - Add sdk-cli-brew and sdk-cli-node to app-mac dependencies

### Phase 4: Cleanup ✅

9. [x] **Delete old files**
   - `service-deploy-remote/Core/DependencyCheckerService.swift`
   - `service-deploy-remote/ToolsService/CLI/Brew.swift`
   - `service-deploy-remote/ToolsService/CLI/Homebrew.swift`
   - `service-deploy-remote/ToolsService/CLI/Node.swift`
   - `sdk-aws/CLI/NpmCommand.swift`

10. [x] **Build and verify**
    - Run `swift build` to check for compilation errors ✅

## Benefits Achieved

1. **Correct layer placement**: Each CLI tool has its own SDK client
2. **Single responsibility**: Each client handles one tool
3. **Reusability**: SDK clients can be extracted to separate packages
4. **Consistent pattern**: All clients follow the same `isInstalled()` pattern
5. **Discoverability**: `BrewClient.isInstalled()` is more intuitive than `DependencyCheckerService.checkHomebrew()`
6. **Testability**: Individual clients are easier to mock and test
