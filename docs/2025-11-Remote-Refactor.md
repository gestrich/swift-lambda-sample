# Remote Tab Refactor Plan

**Date**: November 30, 2025
**Status**: Planning

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
- [ ] Create `githubCISection` view in `DeployView.swift`
- [ ] Display latest workflow run status (badge: In Progress/Success/Failed)
- [ ] Add "Push & Deploy" button that:
  1. Commits any staged changes (or prompts user)
  2. Pushes to remote
  3. Waits for GitHub Actions to complete
  4. Shows real-time progress in unified output
- [ ] Add "View Logs" button to open workflow logs
- [ ] Add state properties to `MacAppModel` for workflow status

**Files**: `DeployView.swift`, `MacAppModel.swift`

**Note**: All GitHub CI operations stream output to the Output view for real-time feedback.

---

### Phase 3: Add CDK Deploy Section
- [ ] Create `cdkDeploySection` view in `DeployView.swift`
- [ ] Display current stack status (Deployed/Not Deployed/Updating)
- [ ] Display detected configuration (Database: YES/NO, NAT Gateway: YES/NO)
- [ ] Add "Deploy" button with options dropdown:
  - Deploy (maintain current config)
  - Deploy with PostgreSQL
  - Deploy with PostgreSQL + NAT Gateway
- [ ] Add "Destroy" button with confirmation dialog
- [ ] Show stack outputs in collapsible section (API URL, Lambda ARN, etc.)
- [ ] Add state properties to `MacAppModel` for stack status

**Files**: `DeployView.swift`, `MacAppModel.swift`

**Note**: All CDK operations (deploy, destroy, diff) stream output to the Output view for real-time feedback.

---

### Phase 4: Wire Up Service Calls
- [ ] Connect GitHub CI section to `RemoteService.updateLambdaCode()`
- [ ] Connect CDK Deploy to `RemoteService.deployInit()` and `RemoteService.deploy()`
- [ ] Connect Destroy to `RemoteService.tearDown()`
- [ ] Add `refreshStatus()` calls to update both GitHub and CDK status
- [ ] Stream output to `UnifiedOutputState` for all operations

**Files**: `MacAppModel.swift`, `RemoteService.swift` (if needed)

---

### Phase 5: Polish and Testing
- [ ] Add loading indicators during async operations
- [ ] Add error handling and user-friendly error messages
- [ ] Test full workflow: Push -> CI -> Verify deployment
- [ ] Test CDK deploy/destroy with different configurations
- [ ] Ensure unified output shows real-time progress

**Files**: `DeployView.swift`, `MacAppModel.swift`

---

### Phase 6: Protocol Refactor - LocalDockerServicesProvider
- [ ] Create `LocalDockerServicesProvider` protocol with Docker service methods:
  - `startS3()`, `stopS3()`
  - `startDatabase()`, `stopDatabase()`
  - `s3DataDirectory`, `postgresDataDirectory`
  - Related status properties (`s3State`, `postgresState`)
- [ ] Have `XcodeLocalService` and `LinuxLocalService` conform to this protocol
- [ ] Remove Docker service methods from base `LambdaService` protocol
- [ ] Remove dead Docker service implementations from `RemoteService`
- [ ] Update `DeployView` to use protocol conformance check for Docker Services section

**Files**:
- `Sources/SwiftDeploy/LambdaServices/LambdaService.swift`
- `Sources/SwiftDeploy/LambdaServices/RemoteService.swift`
- `Sources/SwiftDeploy/LambdaServices/XcodeLocalService.swift`
- `Sources/SwiftDeploy/LambdaServices/LinuxLocalService.swift`
- `Sources/MacApp/DeployView.swift`

---

### Phase 7: Protocol Refactor - LocalBuildProvider
- [ ] Create `LocalBuildProvider` protocol with build methods:
  - `build(clean:)`, `deleteBuild()`
  - `buildState` property
- [ ] Have `XcodeLocalService` and `LinuxLocalService` conform to this protocol
- [ ] Remove build methods from base `LambdaService` protocol
- [ ] Remove dead build implementations from `RemoteService`
- [ ] Update `DeployView` to use protocol conformance check for Build section

**Files**:
- `Sources/SwiftDeploy/LambdaServices/LambdaService.swift`
- `Sources/SwiftDeploy/LambdaServices/RemoteService.swift`
- `Sources/SwiftDeploy/LambdaServices/XcodeLocalService.swift`
- `Sources/SwiftDeploy/LambdaServices/LinuxLocalService.swift`
- `Sources/MacApp/DeployView.swift`

---

### Phase 8: Protocol Refactor - LocalLambdaProvider
- [ ] Create `LocalLambdaProvider` protocol with local Lambda lifecycle:
  - `startLambda()`, `stopLambda()`
  - `startWithServices()`, `stopWithServices()`
  - `lambdaState` property
- [ ] Have `XcodeLocalService` and `LinuxLocalService` conform to this protocol
- [ ] Remove local Lambda lifecycle methods from base `LambdaService` protocol
- [ ] Remove dead Lambda lifecycle implementations from `RemoteService`
- [ ] Update `DeployView` to use protocol conformance check for Lambda section
- [ ] Keep only shared methods in base `LambdaService` protocol (`endpoint`, `testLambda`, `status`, etc.)

**Files**:
- `Sources/SwiftDeploy/LambdaServices/LambdaService.swift`
- `Sources/SwiftDeploy/LambdaServices/RemoteService.swift`
- `Sources/SwiftDeploy/LambdaServices/XcodeLocalService.swift`
- `Sources/SwiftDeploy/LambdaServices/LinuxLocalService.swift`
- `Sources/MacApp/DeployView.swift`
- `Sources/MacApp/MacAppModel.swift` (update if needed)

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
