# CLI Commands Directory Reorganization

**Date:** 2025-12-18
**Status:** Completed
**Type:** Code Organization / Refactoring

## Objective

Reorganize the `Sources/apps/CLIApp/Commands/` directory into subdirectories that group commands by their domain, mirroring the organizational pattern used in `Sources/apps/MacApp/Models/`.

## Background

Currently, the CLIApp Commands directory contains all command files in a flat structure:

```
Sources/apps/CLIApp/Commands/
├── AWSCommand.swift           # Top-level parent + configuration
├── DeployCommand.swift        # extension AWSCommand
├── DeployInitCommand.swift    # extension AWSCommand
├── LocalCommand.swift         # Contains LocalMacCommand, LocalLinuxCommand + all subcommands
├── StatusCommand.swift        # extension AWSCommand
├── TearDownCommand.swift      # extension AWSCommand
├── UpdateLambdaCommand.swift  # extension AWSCommand
└── UploadLambdaCommand.swift  # extension AWSCommand
```

The MacApp/Models directory follows a cleaner pattern with separate files per model:

```
Sources/apps/MacApp/Models/
├── AppModel.swift
├── CloudWatchLogsModel.swift
├── DependencyStatusModel.swift
├── DeployLinuxModel.swift
├── DeployRemoteModel.swift
├── DeployXcodeModel.swift
└── GitHubCIModel.swift
```

The Commands directory has two issues:
1. **LocalCommand.swift** is 1,100+ lines containing two parent commands and ~30+ subcommands with all progress printing logic
2. All AWS-related commands use `extension AWSCommand` pattern but live as separate files at the top level

## Technical Approach

### Proposed Directory Structure

```
Sources/apps/CLIApp/Commands/
├── AWS/
│   ├── AWSCommand.swift           # Top-level parent command
│   ├── DeployCommand.swift
│   ├── DeployInitCommand.swift
│   ├── StatusCommand.swift
│   ├── TearDownCommand.swift
│   ├── UpdateLambdaCommand.swift
│   └── UploadLambdaCommand.swift
├── LocalMac/
│   ├── LocalMacCommand.swift      # Parent command + subcommands
│   └── LocalMacProgressPrinters.swift  # Progress printing functions
└── LocalLinux/
    ├── LocalLinuxCommand.swift    # Parent command + subcommands
    └── LocalLinuxProgressPrinters.swift  # Progress printing functions
```

### Implementation Steps

#### Phase 1: Create Directory Structure ✅ COMPLETED

1. Create `Commands/AWS/` directory
2. Create `Commands/LocalMac/` directory
3. Create `Commands/LocalLinux/` directory

**Completed:** 2025-12-18
**Notes:** Directories created, build verified successful. Empty directories are included by git when files are added in subsequent phases.

#### Phase 2: Migrate AWS Commands ✅ COMPLETED

Move existing files (no code changes needed):
- `AWSCommand.swift` → `AWS/AWSCommand.swift`
- `DeployCommand.swift` → `AWS/DeployCommand.swift`
- `DeployInitCommand.swift` → `AWS/DeployInitCommand.swift`
- `StatusCommand.swift` → `AWS/StatusCommand.swift`
- `TearDownCommand.swift` → `AWS/TearDownCommand.swift`
- `UpdateLambdaCommand.swift` → `AWS/UpdateLambdaCommand.swift`
- `UploadLambdaCommand.swift` → `AWS/UploadLambdaCommand.swift`

**Completed:** 2025-12-18
**Notes:** All 7 AWS command files moved to `Commands/AWS/` using `git mv` to preserve history. Build verified successful. CLI commands work correctly (`swift run CLIApp aws --help` shows all subcommands).

#### Phase 3: Split LocalCommand.swift ✅ COMPLETED

**LocalMac/LocalMacCommand.swift** - Extract:
- `LocalMacCommand` struct and configuration
- All `extension LocalMacCommand` subcommands:
  - `BuildCommand`, `StartCommand`, `StopCommand`
  - `StartAllCommand`, `StopAllCommand`
  - `StartDatabaseCommand`, `StopDatabaseCommand`
  - `StartDynamoDBCommand`, `StopDynamoDBCommand`
  - `StartS3Command`, `StopS3Command`
  - `TestCommand`, `StatusCommand`, `CopyConfigCommand`

**LocalMac/LocalMacProgressPrinters.swift** - Extract:
- `printXcodeBuildProgress`
- `printXcodeStartLambdaProgress`
- `printXcodeStopLambdaProgress`
- `printXcodeStartServicesProgress`
- `printXcodeStopServicesProgress`
- `printXcodeStartAllProgress`
- `printXcodeStopAllProgress`
- `printXcodeTestProgress`
- `printXcodeCopyConfigProgress`
- `printXcodeStatusProgress`

**LocalLinux/LocalLinuxCommand.swift** - Extract:
- `LocalLinuxCommand` struct and configuration
- All `extension LocalLinuxCommand` subcommands (parallel to Mac)
- `SetupNetworkCommand`, `RunInteractiveCommand` (Linux-specific)

**LocalLinux/LocalLinuxProgressPrinters.swift** - Extract:
- `printLinuxBuildProgress`
- `printLinuxStartLambdaProgress`
- `printLinuxStopLambdaProgress`
- `printLinuxStartServicesProgress`
- `printLinuxStopServicesProgress`
- `printLinuxStartAllProgress`
- `printLinuxStopAllProgress`
- `printLinuxTestProgress`
- `printLinuxCopyConfigProgress`
- `printLinuxSetupNetworkProgress`
- `printLinuxRunInteractiveProgress`
- `printLinuxStatusProgress`

**Shared/StatusPrinter.swift** - Extract:
- `printStatus(_ status: DeploymentStatus, mode: String)` - used by both Mac and Linux

**Completed:** 2025-12-18
**Notes:**
- Split 1,183-line `LocalCommand.swift` into 5 focused files across 3 directories
- Created `LocalMac/` directory with `LocalMacCommand.swift` (270 lines) and `LocalMacProgressPrinters.swift` (210 lines)
- Created `LocalLinux/` directory with `LocalLinuxCommand.swift` (305 lines) and `LocalLinuxProgressPrinters.swift` (230 lines)
- Created `Shared/` directory with `StatusPrinter.swift` (19 lines) for the shared `printStatus` function
- Progress printer functions changed from `private` to `internal` (default) to allow cross-file access within same module
- `DeploymentStatus` type is in `DeployCoreService`, not `DeployLocalService` - updated import accordingly
- Build verified successful, CLI help commands verified working for both `local-mac` and `local-linux`

#### Phase 4: Update Imports (if needed)

Swift Package Manager automatically includes all `.swift` files in subdirectories, so no `Package.swift` changes should be needed. However, verify that:
- All files compile correctly after moves
- No circular dependencies are introduced
- Progress printer functions have correct visibility (`internal` is fine since same module)

## File Counts

**Before:**
- 8 files in Commands/

**After:**
- 4 directories (AWS/, LocalMac/, LocalLinux/, Shared/)
- 7 files in AWS/
- 2 files in LocalMac/
- 2 files in LocalLinux/
- 1 file in Shared/

**Total: 12 files across 4 directories** (vs 8 flat files)

## Testing Considerations

1. Run `swift build` after each phase to verify compilation
2. Run `swift run CLIApp --help` to verify command structure is preserved
3. Run `swift run CLIApp aws --help` to verify AWS subcommands
4. Run `swift run CLIApp local-mac --help` to verify LocalMac subcommands
5. Run `swift run CLIApp local-linux --help` to verify LocalLinux subcommands

## Benefits

1. **Better organization**: Related commands grouped together
2. **Easier navigation**: Find AWS commands in AWS/, local commands in their respective directories
3. **Smaller files**: LocalCommand.swift goes from 1,100+ lines to ~300 lines per file
4. **Separation of concerns**: Progress printing logic separated from command logic
5. **Mirrors MacApp pattern**: Consistent organizational approach across apps

## Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| Git history fragmentation | Use `git mv` to preserve file history where possible |
| Missing files in compilation | SPM auto-includes subdirectories; verify with build |
| Broken imports | Same module, no import changes needed |

## Success Criteria

- [x] All commands accessible via same CLI interface
- [x] `swift build` succeeds
- [x] No functionality changes (pure refactor)
- [x] LocalCommand.swift eliminated (split into 5 files across 3 directories)
- [x] Each directory has clear purpose
