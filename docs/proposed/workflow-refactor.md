# Architecture Refactor: App-Service-SDK with Workflows

## Goal

Refactor the deployment architecture to:
- **App layer** (`app-*`): Models (@Observable) + Views + CLI commands
- **Service layer** (`service-*`): Workflows (multi-step orchestration)
- **SDK layer** (`sdk-*`): Stateless Clients

Focus on AWS deployment first as a multi-phase process.

## Target Architecture

```
app-mac                              app-cli
├── DeploymentModel (@Observable)    ├── Commands (use workflows directly)
└── Views                            └── No @Observable needed

         ↓ uses                              ↓ uses

service-deploy
├── DeployWorkflow      → AsyncThrowingStream<DeployProgress, Error>
├── DestroyWorkflow     → AsyncThrowingStream<DestroyProgress, Error>
└── UpdateLambdaWorkflow

         ↓ uses

sdk-aws
├── CDKClient           (stateless - execute, return)
└── CloudFormationClient (stateless - query, return)
```

## Current State (After Phase 8)

| Component | Status |
|-----------|--------|
| `CDKClient` | ✅ Stateless - stream methods only (`deployStream`, `destroyStream`) |
| `CloudFormationClient` | ✅ Stateless - query methods only (`queryState`, `monitorStream`) |
| `DeploymentService` | ✅ DELETED - replaced by workflows and DeploymentModel |
| CLI commands | ✅ Use SDK clients and workflows directly, no @MainActor needed |
| `DeploymentModel` | ✅ App layer @Observable model in feature-mac |
| Workflows | ✅ `DeployWorkflow`, `DestroyWorkflow` orchestrate multi-step operations |

---

## Phase 1: Add Stateless Stream Methods to CDKClient ✅

**Status:** COMPLETED

**Goal:** Add new methods that return progress streams without internal state.

**Files:**
- Create: `Sources/sdk-aws/CDK/CDKProgress.swift`
- Modify: `Sources/sdk-aws/CDK/CDKClient.swift`

**Changes:**

1. Create `CDKProgress` enum:
```swift
public enum CDKProgress: Sendable {
    case installing
    case building
    case deploying(DeploymentProgress)
    case deployed(outputs: [String: String])
    case destroying(DeploymentProgress)
    case destroyed
}
```

2. Add stream-returning methods to CDKClient:
```swift
public func deployStream(options: DeployOptions, output: CLIOutputStream?) -> AsyncThrowingStream<CDKProgress, Error>
public func destroyStream(options: DestroyOptions, output: CLIOutputStream?) -> AsyncThrowingStream<CDKProgress, Error>
```

These methods yield progress directly without using internal `publish()`.

**Verification:** Existing code still works. New methods testable in isolation.

**Technical Notes:**
- Added `installWithoutPublish()` and `buildWithoutPublish()` private helpers to avoid duplicating install/build logic
- Stream methods use `AsyncThrowingStream` with continuation pattern
- Internal `runDeployStream` and `runDestroyStream` methods handle the actual work
- Progress parsing reuses existing `CDKOutputParser` and `CDKProgressAccumulator`
- Errors are propagated via `continuation.finish(throwing:)`

---

## Phase 2: Add Stateless Methods to CloudFormationClient ✅

**Status:** COMPLETED

**Goal:** Add query methods that return results without publishing.

**Files:**
- Modify: `Sources/sdk-aws/CloudFormation/CloudFormationClient.swift`

**Changes:**

1. Add one-shot query:
```swift
public func queryStateOnce(stackName: String) async throws -> CloudFormationState
```

2. Add monitoring stream:
```swift
public func monitorStream(stackName: String, pollInterval: Duration = .seconds(2)) -> AsyncThrowingStream<CloudFormationState, Error>
```

**Verification:** Existing code still works.

**Technical Notes:**
- `queryStateOnce()` reuses existing `getStackStatus()`, `getStackOutputs()`, and `getOperationStartTime()` methods
- Handles same error cases as `queryState()` but without calling `publish()`
- `monitorStream()` uses `nonisolated` to return `AsyncThrowingStream` immediately
- Internal `runMonitorStreamLoop()` runs isolated, polling status and yielding progress updates
- Stream automatically completes when operation finishes (via `continuation.finish()`)
- Properly handles task cancellation and errors during polling

---

## Phase 3: Create DeployWorkflow ✅

**Status:** COMPLETED

**Goal:** Workflow that orchestrates deployment and returns progress stream.

**Files:**
- Created: `Sources/service-deploy/Workflows/DeployWorkflow.swift`

**Design:**
```swift
public struct DeployWorkflow {
    let cdkClient: CDKClient
    let cfClient: CloudFormationClient
    let stackName: String

    public struct Progress: Sendable {
        public enum Step { case building, deploying, monitoring, complete }
        public let step: Step
        public let detail: Detail?

        public enum Detail: Sendable {
            case cdk(DeploymentProgress)
            case outputs(CDKStackOutputs?, CDKInfrastructureConfiguration?)
        }
    }

    public func run(options: Options, output: CLIOutputStream?) -> AsyncThrowingStream<Progress, Error>
}
```

**Verification:** Build succeeds, workflow compiles with correct types.

**Technical Notes:**
- `DeployWorkflow.Options` mirrors `DeploymentService.DeployOptions` with `toCDKOptions()` conversion
- Two-phase approach: CDK deploy stream followed by CloudFormation monitor stream
- CDKClient stream methods (`deployStream`, `destroyStream`) updated to `nonisolated` to allow calling from non-actor context
- Progress steps: `.building` → `.deploying` → `.monitoring` → `.complete`
- Infrastructure configuration detection moved from DeploymentService into workflow
- Final `.complete` progress includes both `CDKStackOutputs` and `CDKInfrastructureConfiguration`
- Proper error handling for credential expiration, stack not found, and deployment failures

---

## Phase 4: Create DestroyWorkflow ✅

**Status:** COMPLETED

**Files:**
- Created: `Sources/service-deploy/Workflows/DestroyWorkflow.swift`

**Design:**
```swift
public struct DestroyWorkflow {
    public struct Progress: Sendable {
        public enum Step { case destroying, complete }
        public let step: Step
        public let detail: DeploymentProgress?
    }

    public func run() -> AsyncThrowingStream<Progress, Error>
}
```

**Verification:** Build succeeds, workflow compiles with correct types.

**Technical Notes:**
- `DestroyWorkflow.Options` wraps CDKClient.DestroyOptions with `force: Bool` (defaults to `true`)
- Two-phase approach: CDK destroy stream followed by CloudFormation monitor stream
- Progress steps: `.destroying` → `.complete`
- CDK phase yields progress updates from `CDKProgress.destroying(DeploymentProgress)`
- CloudFormation phase monitors until `.notDeployed` state (stack fully deleted)
- Handles edge cases: credential expiration, destroy failures, operations still in progress
- Final state query if stream ends unexpectedly (same pattern as DeployWorkflow)
- Simpler than DeployWorkflow - no configuration detection needed since stack is being deleted

---

## Phase 5: Create DeploymentModel in app-mac ✅

**Status:** COMPLETED

**Goal:** Create a thin DeploymentModel in the app layer that uses workflows.

**Files:**
- Created: `Sources/feature-mac/Models/DeploymentModel.swift`

**Design:**
```swift
@MainActor @Observable
public class DeploymentModel {
    // Stable state
    public private(set) var state: CloudFormationState = .unknown
    public private(set) var stackOutputs: CDKStackOutputs?
    public private(set) var infrastructureConfig: CDKInfrastructureConfiguration?

    // Transient workflow state
    public private(set) var activeWorkflow: ActiveWorkflow?

    public enum ActiveWorkflow {
        case deploy(DeployWorkflow.Progress)
        case destroy(DestroyWorkflow.Progress)
    }

    // Derived
    public var isIdle: Bool { activeWorkflow == nil }
    public var canDeploy: Bool { isIdle && state.canDeploy }

    // Actions
    public func deploy(options: DeployOptions) { ... }
    public func destroy() { ... }
    public func refresh() async { ... }
}
```

**Verification:** Build succeeds, model compiles with correct types.

**Technical Notes:**
- Created new `DeploymentModel` in feature-mac rather than moving `DeploymentService` (to allow incremental migration)
- `DeploymentModel` uses `DeployWorkflow` and `DestroyWorkflow` from service-deploy
- Workflow progress updates drive state changes: `activeWorkflow` tracks current step, `state` reflects CloudFormation status
- Uses `cfClient.queryStateOnce()` for refresh (stateless, doesn't publish)
- `DeployOptions` provides same interface as `DeploymentService.DeployOptions` with `toWorkflowOptions()` conversion
- Maintains same derived properties as `DeploymentService` for view compatibility (`canDeploy`, `canDestroy`, `isDeployed`, etc.)
- `DeploymentService` remains in service-deploy for CLI and existing views (will migrate views in Phase 7)
- Both models can coexist during transition, allowing incremental migration of views

---

## Phase 6: Update CLI to Use Workflows Directly ✅

**Status:** COMPLETED

**Goal:** CLI commands consume workflows without DeploymentService.

**Files:**
- Modified: `Sources/feature-cli/Commands/DeployCommand.swift`
- Modified: `Sources/feature-cli/Commands/TearDownCommand.swift`
- Modified: `Sources/feature-cli/Commands/DeployInitCommand.swift`
- Modified: `Package.swift` (added sdk-aws, sdk-cli, sdk-github dependencies to feature-cli)

**Pattern:**
```swift
func run() async throws {
    let clients = makeClients(awsConfig: awsConfig)
    let workflow = DeployWorkflow(cdkClient: clients.cdk, cfClient: clients.cf, stackName: stackName)

    for try await progress in workflow.run(options: options) {
        switch progress.step {
        case .building: print("🔨 Building...")
        case .deploying:
            if case .cdk(let p) = progress.detail {
                print("☁️  \(p.completedCount)/\(p.resources.count)")
            }
        case .complete:
            if case .outputs(let outputs, _) = progress.detail {
                printOutputs(outputs)
            }
        }
    }
}
```

**Verification:** Build succeeds. CLI commands no longer require @MainActor.

**Technical Notes:**
- All three commands (`deploy`, `deploy-init`, `tear-down`) now create CDKClient and CloudFormationClient directly
- Removed @MainActor requirement from command functions (no longer needed since we don't use DeploymentService)
- Added explicit `ArgumentParser.Option` and `ArgumentParser.Flag` qualifiers to avoid shadowing by sdk-cli's `@Option`/`@Flag` macros
- `DeployCommand` detects existing configuration via `cfClient.queryStateOnce()` and `cfClient.describeStackResources()`
- `TearDownCommand` checks stack state before attempting destroy, handles edge cases (already destroying, failed state)
- `DeployInitCommand` includes safety check for database deletion and integrates GitHub Actions workflow for Lambda code updates
- Lambda code update and verification remain using direct SDK clients (GitClient, GitHubActionsClient, CLIClient) since those would be separate workflows

---

## Phase 7: Update app-mac Views to Use DeploymentModel ✅

**Status:** COMPLETED

**Goal:** Update Mac app views to use the new workflow-based DeploymentModel.

**Files:**
- Modified: `Sources/feature-mac/Models/AppModel.swift`
- Modified: `Sources/feature-mac/RemoteService/RemoteServiceView.swift`
- Modified: `Sources/feature-mac/RemoteService/CDKInfrastructureSectionView.swift`
- Modified: `Sources/feature-mac/Models/DeploymentModel.swift` (property name alignment)

**Changes:**
1. AppModel creates `DeploymentModel` instead of `DeploymentService`
2. Views observe `DeploymentModel` properties
3. Progress displayed from `activeWorkflow`
4. `ConnectionMode.remote` now holds `DeploymentModel` instead of `DeploymentService`

**Verification:** Build succeeds, views compile with correct types.

**Technical Notes:**
- Renamed `DeploymentModel.state` to `deploymentState` for API compatibility with `DeploymentService`
- Renamed `DeploymentModel.infrastructureConfig` to `infrastructureConfiguration` for API compatibility
- Both `DeploymentModel` and `DeploymentService` now share the same property interface, enabling gradual migration
- Views use `@Bindable var service: DeploymentModel` (same pattern as before with DeploymentService)
- `RemoteServiceView` and `CDKInfrastructureSectionView` work unchanged except for type declaration
- Mac app now uses workflow-based architecture for deploy/destroy operations

---

## Phase 8: Remove Stateful Code from SDK Clients and DeploymentService ✅

**Status:** COMPLETED

**Goal:** Clean up - remove now-unused state management from SDK clients and remove DeploymentService.

**Files:**
- Modified: `Sources/sdk-aws/CDK/CDKClient.swift`
- Modified: `Sources/sdk-aws/CloudFormation/CloudFormationClient.swift`
- Modified: `Sources/feature-cli/Commands/StatusCommand.swift`
- Modified: `Sources/feature-cli/Commands/UpdateLambdaCommand.swift`
- Deleted: `Sources/service-deploy/DeploymentService.swift`

**Removed from CDKClient:**
- `currentState` property
- `continuations` dictionary
- `publish()`, `addContinuation()`, `removeContinuation()` methods
- `states()` AsyncStream method
- `getState()` method
- Stateful `build()`, `deploy()`, `destroy()`, `install()` methods
- `CDKClient.State` enum
- `CDKError.operationInProgress` case

**Removed from CloudFormationClient:**
- `currentState` property
- `continuations` dictionary
- `monitorTask` property
- `publish()`, `addContinuation()`, `removeContinuation()` methods
- `states()` AsyncStream method
- `getState()` method
- `queryState()` stateful method (renamed stateless `queryStateOnce()` to `queryState()`)
- `startMonitoring()`, `stopMonitoring()`, `isMonitoring` methods
- `runMonitorLoop()` method

**CLI Commands migrated to SDK clients directly:**
- `StatusCommand` - now uses CloudFormationClient, GitClient, GitHubActionsClient directly
- `UpdateLambdaCommand` - now uses GitClient, GitHubActionsClient directly

**Technical Notes:**
- Combined Phase 8 and Phase 9 since all consumers of `DeploymentService` had already been migrated
- `DeploymentService` was no longer used by any actual code after Phases 5-7
- Renamed `queryStateOnce()` to `queryState()` since the "Once" suffix was only to distinguish from the removed stateful version
- Updated all callers to use the new method name (`queryState` instead of `queryStateOnce`)
- Renamed private `installWithoutPublish()` to `install()` and `buildWithoutPublish()` to `build()` since they're now the only implementations
- Updated protocol comments in `LambdaService.swift` and `LocalService.swift` to reference `DeploymentModel` instead of `DeploymentService`

---

## Phase 9: (Merged into Phase 8)

Phase 9 was completed as part of Phase 8 since `DeploymentService` removal was straightforward after migrating all consumers.

---

## Phase 10: Rename feature-* to app-*

**Status:** NOT STARTED

**Files:**
- Modify: `Package.swift`
- Rename: `Sources/feature-mac` → `Sources/app-mac`
- Rename: `Sources/feature-cli` → `Sources/app-cli`
- Rename: `Sources/feature-lambda` → `Sources/app-lambda`

---

## Critical Files

| File | Changes |
|------|---------|
| `Sources/sdk-aws/CDK/CDKClient.swift` | ✅ Now stateless - only stream methods remain |
| `Sources/sdk-aws/CloudFormation/CloudFormationClient.swift` | ✅ Now stateless - queryState + monitorStream |
| `Sources/service-deploy/Workflows/DeployWorkflow.swift` | ✅ Orchestrates deployment |
| `Sources/service-deploy/Workflows/DestroyWorkflow.swift` | ✅ Orchestrates destruction |
| `Sources/feature-mac/Models/DeploymentModel.swift` | ✅ App layer @Observable model |
| `Sources/feature-mac/Models/AppModel.swift` | ✅ Uses DeploymentModel |
| `Sources/feature-cli/Commands/DeployCommand.swift` | ✅ Uses workflow directly |
| `Sources/service-deploy/DeploymentService.swift` | ✅ DELETED |

---

## Execution Order

Phases 1-4 are additive (non-breaking). Phases 5-7 migrate consumers. Phase 8 cleans up. Phase 10 is optional renaming.

Each phase results in working code - can stop and verify at any point.

## Current Architecture Summary

After completing Phase 8, the architecture is:

```
feature-mac                          feature-cli
├── DeploymentModel (@Observable)    ├── Commands (use SDK clients + workflows)
└── Views                            └── No @Observable needed

         ↓ uses                              ↓ uses

service-deploy
├── DeployWorkflow      → AsyncThrowingStream<DeployProgress, Error>
├── DestroyWorkflow     → AsyncThrowingStream<DestroyProgress, Error>
└── (DeploymentService DELETED)

         ↓ uses

sdk-aws
├── CDKClient           (stateless: deployStream, destroyStream, diff, synth, etc.)
└── CloudFormationClient (stateless: queryState, monitorStream, describeStack, etc.)
```

Key benefits achieved:
- SDK layer is fully stateless - no internal state management
- Workflows orchestrate multi-step operations via AsyncThrowingStream
- App layer (@Observable) only in feature-mac where SwiftUI needs it
- CLI commands are simple consumers of SDK clients and workflows
