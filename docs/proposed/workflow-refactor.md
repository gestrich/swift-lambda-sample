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

## Current State

| Component | Issue |
|-----------|-------|
| `CDKClient` | Has `states()` AsyncStream, `currentState`, `continuations`, `publish()` |
| `CloudFormationClient` | Has `states()` AsyncStream, monitoring loop, internal state |
| `DeploymentService` | 644 lines, @Observable, observes all SDK streams, does orchestration |
| CLI commands | Create `DeploymentService`, use @MainActor, read state after operations |

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

## Phase 5: Move DeploymentService → DeploymentModel in app-mac

**Goal:** DeploymentService becomes a thin DeploymentModel in the app layer.

**Files:**
- Move & Rename: `Sources/service-deploy/DeploymentService.swift` → `Sources/feature-mac/Models/DeploymentModel.swift`

**Design:**
```swift
@MainActor @Observable
public class DeploymentModel {
    // Stable state
    public private(set) var state: DeploymentState = .unknown
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

**Verification:** Can be tested with mock workflows.

---

## Phase 6: Update CLI to Use Workflows Directly

**Goal:** CLI commands consume workflows without DeploymentService.

**Files:**
- Modify: `Sources/feature-cli/Commands/DeployCommand.swift`
- Modify: `Sources/feature-cli/Commands/TearDownCommand.swift`
- Modify: `Sources/feature-cli/Commands/DeployInitCommand.swift`

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

**Verification:** CLI works without @MainActor requirement.

---

## Phase 7: Update app-mac Views to Use DeploymentModel

**Files:**
- Modify: `Sources/feature-mac/Models/AppModel.swift`
- Modify: `Sources/feature-mac/RemoteService/RemoteServiceView.swift`
- Modify: `Sources/feature-mac/RemoteService/CDKInfrastructureSectionView.swift`

**Changes:**
1. AppModel creates `DeploymentModel` instead of `DeploymentService`
2. Views observe `DeploymentModel` properties
3. Progress displayed from `activeWorkflow`

---

## Phase 8: Remove Stateful Code from SDK Clients

**Goal:** Clean up - remove now-unused state management.

**Files:**
- Modify: `Sources/sdk-aws/CDK/CDKClient.swift`
- Modify: `Sources/sdk-aws/CloudFormation/CloudFormationClient.swift`

**Remove:**
- `currentState`, `continuations`, `publish()` methods
- `states()` AsyncStream methods
- `monitorTask` from CloudFormationClient

**Keep:**
- Stream-returning methods from Phases 1-2
- All query/execute methods

---

## Phase 9: Remove DeploymentService from service-deploy

**Goal:** After Phase 5 moves it to app-mac as DeploymentModel, remove any remnants from service-deploy.

**Result:** service-deploy contains only Workflows. No @Observable code in service layer.

---

## Phase 10: Rename feature-* to app-*

**Files:**
- Modify: `Package.swift`
- Rename: `Sources/feature-mac` → `Sources/app-mac`
- Rename: `Sources/feature-cli` → `Sources/app-cli`
- Rename: `Sources/feature-lambda` → `Sources/app-lambda`

---

## Critical Files

| File | Changes |
|------|---------|
| `Sources/sdk-aws/CDK/CDKClient.swift` | Add stream methods, later remove state |
| `Sources/sdk-aws/CloudFormation/CloudFormationClient.swift` | Add query methods, later remove state |
| `Sources/service-deploy/Workflows/DeployWorkflow.swift` | New - orchestration |
| `Sources/feature-mac/Models/DeploymentModel.swift` | Moved from DeploymentService, made thin |
| `Sources/feature-mac/Models/AppModel.swift` | Use DeploymentModel |
| `Sources/feature-cli/Commands/DeployCommand.swift` | Use workflow directly |
| `Sources/service-deploy/DeploymentService.swift` | Move to app-mac, then delete |

---

## Execution Order

Phases 1-4 are additive (non-breaking). Phases 5-7 migrate consumers. Phases 8-10 clean up.

Each phase results in working code - can stop and verify at any point.
