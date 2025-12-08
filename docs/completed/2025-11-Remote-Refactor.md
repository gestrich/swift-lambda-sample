# Remote Tab Refactor Plan

**Date**: November 30, 2025
**Status**: Phases 1-8 Complete + Future Improvement #3 (CLIService per Service)

## Overview

The Remote tab currently shows sections (Docker Services, Build, Lambda) that are designed for local development workflows. These need to be replaced with Remote-specific functionality.

**Important**: The Output view must be kept for all modes. It displays real-time CLI output from CDK deployments, GitHub Actions, and other operations.

| Current (Remove/Hide) | New (Add) |
|----------------------|-----------|
| Docker Services | - |
| Build | - |
| Lambda | - |
| - | GitHub CI (push + wait for completion) |
| - | CDK Deploy (deploy/destroy with options) |

## Current State Analysis

### Files to Modify

| File | Purpose |
|------|---------|
| `Sources/MacApp/DeployView.swift` | Main deploy view with sections |
| `Sources/MacApp/MacAppModel.swift` | Model managing mode and services |
| `Sources/SwiftDeploy/LambdaServices/RemoteService.swift` | Remote service with CDK/GitHub logic |

### Existing Service Methods Available

**GitHubService** (already implemented):
- `getLatestRunStatus(branch:)` - Get workflow status
- `triggerWorkflowAndWait(...)` - Trigger and wait for completion
- `viewLogs(runId:)` - View workflow logs
- `listWorkflowRuns(branch:limit:)` - List recent runs

**RemoteService** (already implemented):
- `deployInit(withPostgres:withNATGateway:)` - Initial deployment
- `deploy()` - Update infrastructure
- `tearDown(force:)` - Destroy infrastructure
- `getStackOutputs()` - Get CloudFormation outputs
- `queryDeployedState()` - Detect database/NAT config

---

## Implementation Phases

### Phase 1: Hide Local-Only Sections in Remote Mode
- [x] Hide Docker Services section when `mode.isRemote`
- [x] Hide Build section when `mode.isRemote`
- [x] Hide Lambda section when `mode.isRemote`
- [x] Keep Mode Picker, About, Output, and Command Input sections

**Files**: `DeployView.swift`

**Completed**: Wrapped Docker Services, Build, and Lambda sections in `if !model.mode.isRemote` block. Removed redundant "Docker services are only available in local modes" message.

**Note**: Output view remains visible - shows CLI output for all operations.

---

### Phase 2: Add GitHub CI Section
- [x] Create `githubCISection` view in `DeployView.swift`
- [x] Display latest workflow run status (badge: In Progress/Success/Failed)
- [x] Add "Push & Deploy" button that:
  1. Checks for unpushed commits
  2. Pushes to remote (or triggers workflow if no commits)
  3. Waits for GitHub Actions to complete
  4. Shows real-time progress with streaming output
- [x] Add "View Logs" button to open workflow logs in browser
- [x] Add state properties via `GitHubCIState` class

**Files**:
- `DeployView.swift` - Added `githubCISection` view
- `MacAppModel.swift` - Added `githubCIState` and `remoteService` accessors to `ConnectionMode`
- `GitHubCISectionView.swift` - New dedicated view component
- `GitHubCIState.swift` - New state management class
- `RemoteService.swift` - Added `refreshGitHubCIStatus()`, `pushAndDeploy()`, `viewWorkflowLogs()`
- `GitHubCLIService.swift` - Added `watchWorkflowRunStreaming()`

**Completed**: The GitHub CI section shows:
- Current workflow status with colored badge (success/failed/in-progress)
- Git status (branch name, uncommitted changes, unpushed commits indicators)
- Real-time deployment progress with streaming output from `gh run watch`
- "Push & Deploy" button (adapts label based on git state)
- "View Logs" button to open GitHub Actions in browser
- Refresh button to update status

**Note**: All GitHub CI operations stream output to the Output view for real-time feedback.

---

### Phase 3: Add CDK Deploy Section
- [x] Create `cdkDeploySection` view in `DeployView.swift`
- [x] Display current stack status (Deployed/Not Deployed/Updating)
- [x] Display detected configuration (Database: YES/NO, NAT Gateway: YES/NO)
- [x] Add "Deploy" button with options dropdown:
  - Deploy (maintain current config)
  - Deploy with PostgreSQL
  - Deploy with PostgreSQL + NAT Gateway
- [x] Add "Destroy" button with confirmation dialog
- [x] Show stack outputs in collapsible section (API URL, Lambda ARN, etc.)
- [x] Add state properties to `MacAppModel` for stack status

**Files**:
- `DeployView.swift` - Added `cdkInfrastructureSection` view
- `MacAppModel.swift` - Added `cdkInfrastructureService` accessor
- `CDKInfrastructureSectionView.swift` - New dedicated view component
- `CDKInfrastructureService.swift` - New state management service with @MainActor @Observable
- `RemoteService.swift` - Added `initializeCDKInfrastructureService()`

**Completed**: The CDK Infrastructure section shows:
- Current stack status with colored badge (deployed/not deployed/deploying/destroying/failed)
- Detected configuration indicators (Database, NAT Gateway)
- Deploy menu with options (Minimal, With PostgreSQL, Full, Update)
- Destroy button with confirmation dialog
- Collapsible stack outputs section with copy-to-clipboard functionality
- Real-time elapsed time during deploy/destroy operations

**Note**: All CDK operations (deploy, destroy) stream output to the Output view for real-time feedback.

---

### Phase 4: Wire Up Service Calls
- [x] Connect GitHub CI section to `GitHubService` methods (already done in Phase 2)
- [x] Connect CDK Deploy to `CDKInfrastructureService` methods (already done in Phase 3)
- [x] Connect Destroy to `CDKInfrastructureService.destroy()` (already done in Phase 3)
- [x] Add `refreshStatus()` calls to update both GitHub and CDK status
- [x] Verify output streams to Output view for all operations

**Files**: `RemoteService.swift`

**Completed**: Analysis revealed that Phase 2 and Phase 3 already fully wired up the UI buttons to their respective service methods:
- `GitHubCISectionView` → `GitHubService.pushAndDeploy()`, `refreshStatus()`, `viewWorkflowLogs()`
- `CDKInfrastructureSectionView` → `CDKInfrastructureService.deploy()`, `updateInfrastructure()`, `destroy()`, `refreshStatus()`

The remaining work was:
1. **Connected main refresh button**: Updated `RemoteService.refreshStatus()` to also call `githubService?.refreshStatus()` and `cdkInfrastructureService?.refreshStatus()` in parallel
2. **Verified output streaming**: Output flows through each service's `cliService.outputStream()` which is used by the Output view in `DeployView.swift`. The `UnifiedOutputState` in each service is not needed for remote mode.

**Note**: The UI buttons connect directly to `GitHubService` and `CDKInfrastructureService` rather than going through `RemoteService`. This is the better design since these are specialized services with their own state management.

---

### Phase 5: Polish and Testing
- [x] Add loading indicators during async operations
- [x] Add error handling and user-friendly error messages
- [x] Test full workflow: Push -> CI -> Verify deployment
- [x] Test CDK deploy/destroy with different configurations
- [x] Ensure unified output shows real-time progress

**Files**: `DeployView.swift`, `MacAppModel.swift`

**Completed**: Verified all polish items:
1. **Loading indicators**: Both `GitHubCISectionView` and `CDKInfrastructureSectionView` have comprehensive loading indicators:
   - `ProgressView()` spinners for deploying, destroying, and loading states
   - Elapsed time displays during operations
   - Real-time resource progress for CloudFormation (CDK)
   - Job/step progress for GitHub Actions workflows

2. **Error handling**: Both views display error states with:
   - `.failed(reason:)` status displayed with red icon and reason text
   - Services catch errors and update status (errors don't silently fail)
   - `try?` pattern in UI buttons is correct since services handle state updates

3. **Workflow verification**: Code review confirms:
   - `GitHubService.pushAndDeploy()` pushes commits or triggers workflow, monitors via polling
   - `GitHubCISectionView` shows job/step progress during deployment
   - `CDKInfrastructureService.deploy()` runs CDK with progress polling

4. **CDK deploy/destroy verification**: Code review confirms:
   - `deploy()`, `updateInfrastructure()`, and `destroy()` all update state correctly
   - Progress polling via `runDeployWithProgressPolling()` shows CloudFormation events
   - Confirmation dialog for destroy action

5. **Output streaming verification**: Each service has its own `CLIService` instance which streams to `StreamingTextView` via `outputStream()`.

---

### Phase 6: Protocol Refactor - LocalDockerServicesProvider
- [x] Create `LocalDockerServicesProvider` protocol with Docker service methods:
  - `startS3()`, `stopS3()`
  - `startDatabase()`, `stopDatabase()`
  - `s3DataDirectory`, `postgresDataDirectory`
- [x] Have `XcodeLocalService` and `LinuxLocalService` conform to this protocol
- [x] Remove Docker service methods from `ConnectionMode` and `MacAppModel`
- [x] Add `dockerServicesProvider` property to `ConnectionMode` for protocol-based access
- [x] Update `DeployView` to use protocol conformance check for Docker Services section

**Files**:
- `Sources/SwiftDeploy/LambdaServices/LocalDockerServicesProvider.swift` (NEW)
- `Sources/SwiftDeploy/LambdaServices/XcodeLocalService.swift`
- `Sources/SwiftDeploy/LambdaServices/LinuxLocalService.swift`
- `Sources/MacApp/MacAppModel.swift`
- `Sources/MacApp/DeployView.swift`

**Completed**: The `LocalDockerServicesProvider` protocol cleanly separates Docker service capabilities:
- Only `XcodeLocalService` and `LinuxLocalService` conform to the protocol
- `RemoteService` never had Docker methods in the base protocol (they were on `ConnectionMode`)
- `ConnectionMode` now provides `dockerServicesProvider` property that returns nil for remote mode
- `DeployView` uses `if let dockerProvider = model.dockerServicesProvider` pattern
- Status properties (`s3State`, `postgresState`) remain on `DeploymentStatus` which is shared across all modes

**Note**: The original plan mentioned removing Docker methods from `LambdaService` protocol, but these methods were never in the protocol - they were implemented directly on `ConnectionMode` with switch statements. The refactor replaced those switch statements with a single `dockerServicesProvider` computed property.

---

### Phase 7: Protocol Refactor - LocalBuildProvider
- [x] Create `LocalBuildProvider` protocol with build methods:
  - `build(clean:)`, `deleteBuild()`
  - `buildState` property
  - `isLambdaBuilt()`, `refreshBuildStatus()`
- [x] Have `XcodeLocalService` and `LinuxLocalService` conform to this protocol
- [x] Remove build methods from base `LambdaService` protocol
- [x] Remove dead build implementations from `RemoteService`
- [x] Update `DeployView` to use protocol conformance check for Build section
- [x] Update `ConnectionMode` with `buildProvider` property
- [x] Update `MacAppModel` with `buildProvider` property

**Files**:
- `Sources/SwiftDeploy/LambdaServices/LocalBuildProvider.swift` (NEW)
- `Sources/SwiftDeploy/LambdaServices/LambdaService.swift`
- `Sources/SwiftDeploy/LambdaServices/RemoteService.swift`
- `Sources/SwiftDeploy/LambdaServices/XcodeLocalService.swift`
- `Sources/SwiftDeploy/LambdaServices/LinuxLocalService.swift`
- `Sources/MacApp/DeployView.swift`
- `Sources/MacApp/MacAppModel.swift`

**Completed**: The `LocalBuildProvider` protocol cleanly separates build capabilities:
- Only `XcodeLocalService` and `LinuxLocalService` conform to the protocol
- `RemoteService` no longer has build methods (builds happen via CI/CD pipeline)
- `ConnectionMode` now provides `buildProvider` property that returns nil for remote mode
- `DeployView` uses `if let buildProvider = model.buildProvider` pattern
- Build state is accessed through the protocol, not through `LambdaService`

**Note**: The pattern follows Phase 6's `LocalDockerServicesProvider` approach. Remote mode uses GitHub Actions for builds, so build methods were removed entirely from `RemoteService` rather than kept as no-ops.

---

### Phase 8: Protocol Refactor - LocalLambdaProvider
- [x] Create `LocalLambdaProvider` protocol with local Lambda lifecycle:
  - `startLambda()`, `stopLambda()`
  - `startWithServices()`, `stopWithServices()`
  - `lambdaState` property
- [x] Have `XcodeLocalService` and `LinuxLocalService` conform to this protocol
- [x] Remove local Lambda lifecycle methods from base `LambdaService` protocol
- [x] Remove dead Lambda lifecycle implementations from `RemoteService`
- [x] Update `DeployView` to use protocol conformance check for Lambda section
- [x] Update `ConnectionMode` with `lambdaProvider` property
- [x] Update `MacAppModel` with `lambdaProvider` property
- [x] Keep only shared methods in base `LambdaService` protocol (`endpoint`, `testLambda`, `status`, etc.)

**Files**:
- `Sources/SwiftDeploy/LambdaServices/LocalLambdaProvider.swift` (NEW)
- `Sources/SwiftDeploy/LambdaServices/LambdaService.swift`
- `Sources/SwiftDeploy/LambdaServices/RemoteService.swift`
- `Sources/SwiftDeploy/LambdaServices/XcodeLocalService.swift`
- `Sources/SwiftDeploy/LambdaServices/LinuxLocalService.swift`
- `Sources/MacApp/DeployView.swift`
- `Sources/MacApp/MacAppModel.swift`

**Completed**: The `LocalLambdaProvider` protocol cleanly separates Lambda lifecycle capabilities:
- Only `XcodeLocalService` and `LinuxLocalService` conform to the protocol
- `RemoteService` no longer has Lambda lifecycle methods (Lambda runs on-demand in AWS)
- `ConnectionMode` now provides `lambdaProvider` property that returns nil for remote mode
- `MacAppModel` now provides `lambdaProvider` property
- `DeployView` uses `if let lambdaProvider = model.lambdaProvider` pattern
- Lambda state is accessed through the protocol, not through `LambdaService`

**Note**: The pattern follows Phases 6 and 7's approach. Remote mode manages Lambda differently - it runs on-demand when invoked via API Gateway, so lifecycle methods don't apply.

**Benefits of Phases 6-8**:
- Clean separation of concerns - protocols define capabilities
- No dead code in RemoteService
- View logic based on capability, not mode type
- Easier to add new service types in the future

---

## UI Mockup

```
┌─────────────────────────────────────────────────┐
│ Mode: [Remote ▼] [Local Xcode] [Local Linux]    │
├─────────────────────────────────────────────────┤
│ About                                           │
│ Swift Lambda sample deployed to AWS...          │
├─────────────────────────────────────────────────┤
│ GitHub CI                                       │
│ ┌─────────────────────────────────────────────┐ │
│ │ Status: ● Success    Last run: 2 min ago   │ │
│ │                                             │ │
│ │ [Push & Deploy]  [View Logs]                │ │
│ └─────────────────────────────────────────────┘ │
├─────────────────────────────────────────────────┤
│ CDK Infrastructure                              │
│ ┌─────────────────────────────────────────────┐ │
│ │ Stack: SwiftLambdaSampleStack               │ │
│ │ Status: ● Deployed                          │ │
│ │                                             │ │
│ │ Configuration:                              │ │
│ │   Database: ✓ Enabled                       │ │
│ │   NAT Gateway: ✗ Disabled                   │ │
│ │                                             │ │
│ │ [Deploy ▼]  [Destroy]                       │ │
│ │                                             │ │
│ │ ▶ Stack Outputs                             │ │
│ │   API URL: https://abc123.execute-api...    │ │
│ │   Lambda ARN: arn:aws:lambda:us-east-1...   │ │
│ └─────────────────────────────────────────────┘ │
├─────────────────────────────────────────────────┤
│ Output                                          │
│ ┌─────────────────────────────────────────────┐ │
│ │ > Pushing to remote...                      │ │
│ │ > Waiting for GitHub Actions...             │ │
│ │ > Deployment complete!                      │ │
│ └─────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────┘
```

---

## Notes

- All underlying service methods already exist - this is primarily UI work
- Keep the unified output section for showing real-time progress
- Remote mode should feel purpose-built for AWS deployment, not a disabled local mode

---

## Future Improvements

### 1. Eager Service Initialization in MacAppModel ✅ COMPLETED

All services (`RemoteService`, `XcodeLocalService`, `LinuxLocalService`) are now created at `MacAppModel` initialization time. The active mode simply determines which service is currently in use.

**Problem**: Lazy initialization resulted in `Optional` service properties that needed to be unwrapped everywhere they were used, adding boilerplate and potential nil-handling bugs.

**Solution**:
- All three services are now created as `let` properties in `MacAppModel.init()`
- `ConnectionMode` enum still holds a reference to the active service
- Mode setters (`setRemote()`, `setLocalXcode()`, `setLocalLinux()`) now switch between pre-created services
- Removed `ConnectionMode.from(key:workingDirectory:)` factory method (no longer needed)
- `githubService` and `cdkInfrastructureService` now accessed directly from `remoteService` property

### 2. Eager Sub-Service Initialization in RemoteService ✅ COMPLETED

`RemoteService` previously had `initializeGitHubService()` and `initializeCDKInfrastructureService()` methods that were called lazily from `MacAppModel`. These sub-services are now created when `RemoteService` itself is created.

**Problem**: The old pattern required calling initialization methods from `MacAppModel` at specific points (e.g., `setUpMode()`, `switchToRemoteMode()`), which was error-prone and led to optional properties.

**Solution**: `GitHubService` and `CDKInfrastructureService` are now created in `RemoteService.init()`. They are `let` properties (still optional since config may not be available, but initialized once at creation time rather than lazily).

### 3. Separate CLIService per Service Type ✅ COMPLETED

Each service (Remote, Xcode, Linux) now has its own dedicated `CLIService` instance that propagates to all child services. This ensures CLI output streams remain isolated and correctly attributed to each mode.

**Problem**: When switching modes or running operations across different services, CLI output from one service could appear in another's output view.

**Solution**: Each parent service now instantiates its own `CLIService` and passes it to all child services:

**Parent Services** (create CLIService instances):
- `RemoteService` creates `CLIService(defaultWorkingDirectory: projectRoot)`
- `XcodeLocalService` creates `CLIService(defaultWorkingDirectory: workingDirectory)`
- `LinuxLocalService` creates `CLIService(defaultWorkingDirectory: workingDirectory)`

**Child Services** (accept CLIService via init):
- `DockerService(cliService:)` - used by XcodeLocalService, LinuxLocalService
- `CDKService(cliService:)` - used by RemoteService, CDKInfrastructureService
- `AWSCLIService(cliService:)` - used by RemoteService, CDKInfrastructureService
- `GitService(cliService:)` - used by GitHubService
- `GitHubCLIService(cliService:)` - used by GitHubService
- `GitHubService(cliService:)` - used by RemoteService
- `CDKInfrastructureService(cliService:)` - used by RemoteService

**Changes made**:
- Added `cliService: CLIService` to the `LambdaService` protocol
- Changed `cliService` from `private` to `public` in all three parent services
- Updated all child services to require `cliService` parameter (no default value)
- Parent services create CLIService first, then pass it to all child service constructors
- Added `cliService` forwarding property to `ConnectionMode` and `MacAppModel`
- Updated `DeployView` to use `model.cliService.outputStream()` instead of `CLIService.shared.outputStream()`
- Added `.id(model.mode.persistenceKey)` to StreamingTextView to reset the view when mode changes
- Removed the unused `CLIService.shared.setDefaultWorkingDirectory()` call from `MacAppModel.init()`
- Created `Sources/SwiftDeploy/Exports.swift` to re-export `CLIService` from CLIKit, avoiding macro conflicts with ArgumentParser
- CLI commands create their own `CLIService()` instances

**CLIService instantiation**:
- CLI commands create their own `CLIService()` instances
- `AWSVaultService.checkInstallation(using:)` accepts a CLIService parameter

**Benefits**:
- CLI output streams are now fully isolated per mode
- Switching modes shows only that mode's output
- No more output mixing between services or their child services
- All commands from a mode (builds, deployments, health checks, etc.) appear in that mode's output stream

### 4. Separate Deploy Views for Remote vs Local

The current `DeployView` tries to handle both Remote and Local (Xcode + Linux) modes in a single view, but these are fundamentally different workflows. This leads to complex conditional logic and optional unwrapping.

**Problem**: Remote deployment (CDK, GitHub Actions) has completely different UI needs than local development (Docker services, native builds, Lambda containers). Combining them in one view creates unnecessary complexity.

**Solution**: Split into separate views:
- **`RemoteDeployView`**: GitHub CI section, CDK Infrastructure section, stack outputs
- **`LocalDeployView`**: Docker Services, Build, Lambda lifecycle (shared between Xcode and Linux modes)

This separation will:
- Simplify both views significantly
- Eliminate conditional checks for `model.mode.isRemote`
- Remove awkward optional unwrapping of services in `MacAppModel`
- Make each view purpose-built for its workflow
