# Workflow State Model Alignment

**Date:** 2025-12-16
**Status:** Completed

## Goal

Refactor the state modeling between workflows (service layer) and DeploymentModel (app layer) so that workflows return state types that can be used directly by the app layer, eliminating the need for DeploymentModel to manually construct state snapshots from workflow progress.

## Problem Statement

Currently, there is a mismatch between what workflows return and what DeploymentModel needs to track:

**Current Flow:**
```
Workflow (service-deploy)
├── DeployWorkflow.Progress
├── DestroyWorkflow.Progress
└── UpdateLambdaWorkflow.Progress
         ↓ consumed by
DeploymentModel (app-mac)
├── Creates ModelState.DeploymentSnapshot manually
├── Creates ModelState.RunningWorkflow manually
└── Maps workflow progress to state (lines 200-218, 254-268, 298-316)
```

**Issues:**
1. **Duplication**: DeploymentModel duplicates state construction logic that could live in workflows
2. **Manual Mapping**: DeploymentModel manually extracts and reassembles data from workflow progress (e.g., lines 209-217)
3. **Inconsistent Abstraction**: Workflows return progress with embedded SDK types, but DeploymentModel needs app-level state types
4. **Layer Confusion**: `ModelState` and its nested types (`DeploymentSnapshot`, `RunningWorkflow`) are defined in app-mac but represent service-level concerns

## Current Architecture Analysis

### State Types Location (app-mac)

From `Sources/app-mac/Models/DeploymentModel.swift`:

```swift
// Lines 337-562: ModelState defined in app-mac
public enum ModelState {
    case uninitialized
    case loading(prior: DeploymentSnapshot?)
    case ready(DeploymentSnapshot)
    case operating(RunningWorkflow)

    // Lines 353-441: DeploymentSnapshot
    public struct DeploymentSnapshot: Sendable {
        public let status: DeploymentStatus
        public let outputs: CDKStackOutputs?
        public let infrastructure: CDKInfrastructureConfiguration?

        // Contains: status (notDeployed/deployed/failed/credentialExpired)
        // Convenience: apiGatewayUrl, isDeployed, canDeploy, etc.
    }

    // Lines 446-477: RunningWorkflow
    public struct RunningWorkflow: Sendable {
        public let kind: Kind
        public let startTime: Date
        public let prior: DeploymentSnapshot?

        public enum Kind: Sendable {
            case deploying(DeployWorkflow.Progress)
            case destroying(DestroyWorkflow.Progress)
            case updatingLambda(UpdateLambdaWorkflow.Progress)
        }
    }
}
```

### Workflow Progress Types (service-deploy)

**DeployWorkflow.Progress** (lines 89-164):
```swift
public struct Progress: Sendable {
    public let step: Step  // .building, .deploying, .monitoring, .complete
    public let detail: Detail?

    public enum Detail: Sendable {
        case cdk(DeploymentProgress)
        case outputs(CDKStackOutputs?, CDKInfrastructureConfiguration?)
    }

    // Convenience accessors
    var stackOutputs: CDKStackOutputs?
    var infrastructureConfiguration: CDKInfrastructureConfiguration?
}
```

**DestroyWorkflow.Progress** (lines 67-93):
```swift
public struct Progress: Sendable {
    public let step: Step  // .destroying, .complete
    public let detail: DeploymentProgress?
}
```

**UpdateLambdaWorkflow.Progress** (lines 49-71):
```swift
public struct Progress: Sendable {
    public let step: Step  // checkingGitStatus, pushing, triggeringWorkflow, waitingForWorkflow, complete
    public let detail: Detail?

    public enum Detail: Sendable {
        case gitStatus(hasCommitsToPush: Bool)
        case workflowProgress(WorkflowProgress)
        case skippedPush
    }
}
```

### SDK-Layer State Types (sdk-aws)

From `Sources/sdk-aws/CloudFormation/CloudFormationState.swift`:

```swift
public struct DetectedInfrastructure: Sendable, Equatable {
    public let hasDatabase: Bool
    public let hasNATGateway: Bool
    public let hasVPC: Bool
}

public struct DeployedStack: Sendable, Equatable {
    public let outputs: [String: String]
    public let infrastructure: DetectedInfrastructure
}

public enum CloudFormationState: Sendable, Equatable {
    case unknown
    case loading
    case notDeployed
    case deployed(DeployedStack)
    case deploying(operation: DeployOperation, progress: DeploymentProgress, startTime: Date)
    case destroying(progress: DeploymentProgress, startTime: Date)
    case failed(reason: String)
    case credentialExpired(message: String)
}
```

### Manual State Construction in DeploymentModel

**Deploy operation** (lines 200-218):
```swift
for try await progress in workflow.run(options: options, output: output) {
    // DeploymentModel manually creates RunningWorkflow from progress
    state = .operating(ModelState.RunningWorkflow(
        kind: .deploying(progress),
        startTime: startTime,
        prior: prior
    ))

    // On completion, manually creates DeploymentSnapshot
    if progress.step == .complete {
        let deployedStack = DeployedStack(
            outputs: progress.stackOutputs?.allOutputs ?? [:],
            infrastructure: progress.infrastructureConfiguration?.detectedInfrastructure ?? DetectedInfrastructure()
        )
        state = .ready(ModelState.DeploymentSnapshot(
            status: .deployed(deployedStack),
            outputs: progress.stackOutputs,
            infrastructure: progress.infrastructureConfiguration
        ))
    }
}
```

**Destroy operation** (lines 254-268): Similar pattern

**Update Lambda operation** (lines 298-316): Similar pattern

## Design Considerations

### Layer Boundaries

Per `docs/architecture/layered-architecture.md`:

```
App (app-mac)       → @Observable models, UI binding, I/O
Service (service-deploy) → Workflows, multi-step orchestration
SDK (sdk-aws)       → Stateless clients, single operations
```

**Key Principles:**
1. **SDKs are stateless** - No internal state, each method is independent
2. **Workflows orchestrate** - Multi-step operations via AsyncThrowingStream
3. **@Observable only in app layer** - Where SwiftUI binding is needed
4. **Minimal logic in models** - Business logic belongs in services/SDKs

### Type Ownership Questions

**Where should state types live?**

1. **Option A: Move ModelState to service-deploy**
   - ✅ Workflows can return complete state directly
   - ✅ Better separation - service layer owns state modeling
   - ❌ Makes `@Observable` harder (can't observe service-layer types directly)
   - ❌ Creates dependency from service → app for UI-specific concerns

2. **Option B: Create parallel service-layer state types**
   - ✅ Clean layer separation
   - ✅ Workflows return service-appropriate types
   - ✅ App layer maps to UI-appropriate types
   - ❌ Duplication of similar structures
   - ❌ Mapping code still needed (but in one place)

3. **Option C: Enhance workflow Progress to be directly observable**
   - ✅ Minimal changes to existing code
   - ✅ Workflows already return progress with most needed data
   - ❌ Progress types become heavier
   - ❌ Still need separate snapshot vs. running state distinction

4. **Option D: Workflows return SDK-layer state (CloudFormationState)**
   - ✅ Reuses existing SDK types
   - ✅ No new types needed
   - ❌ Loses app-specific context (e.g., which workflow is running)
   - ❌ `CloudFormationState` doesn't cover Lambda updates

### Existing Patterns to Consider

**StatusWorkflow already demonstrates a snapshot pattern:**

From `Sources/service-deploy/Workflows/StatusWorkflow.swift` (lines 146-157):
```swift
public struct Status: Sendable {
    public let git: GitStatus
    public let github: GitHubStatus?
    public let stack: StackStatus
}
```

This workflow returns a complete snapshot type (`Status`) that aggregates multiple SDK results. This is a model we could follow.

**DeployWorkflow already has state conversion logic:**

Lines 114-146 of `DeployWorkflow.swift`:
```swift
public func toDeploymentState(startTime: Date) -> CloudFormationState {
    switch step {
    case .building:
        return .deploying(operation: .building, progress: DeploymentProgress(), startTime: startTime)
    case .deploying:
        // ...
    case .complete:
        // ...
    }
}
```

This method converts workflow progress to SDK state, but it's incomplete (doesn't handle app-level concerns like outputs/infrastructure).

## Proposed Design

### Key Design Principle: Separation of Concerns

**Workflow's responsibility:**
- `startTime` - the workflow knows when it started (internal to execution)
- Progress/state during operation
- Final snapshot on completion

**App layer's responsibility:**
- `prior` snapshot - UI state preservation concern
- Combining workflow state with prior to construct `ModelState`

### Approach: Workflows as State Machines

Workflows should be **state machines that yield their current state**, not progress objects that need interpretation. The app layer simply observes and combines with its own concerns.

**Target usage pattern:**

```swift
let prior = state.snapshot  // App captures before starting
for try await workflowState in workflow.run(options: options) {
    state = ModelState(from: workflowState, prior: prior)
}
```

**Benefits:**
- Workflows own their state modeling entirely
- `startTime` is internal to workflow (captured at start)
- App layer only adds `prior` (its own concern)
- Clean 1:1 mapping from workflow state to model state
- Highly testable - workflow state can be unit tested in isolation

### New Service-Layer Types

**Location:** `Sources/service-deploy/Models/DeploymentState.swift`

```swift
import Foundation
import sdk_aws

// MARK: - Deployment Snapshot (Stable State)

/// Represents stable deployment state (not currently operating)
public struct DeploymentSnapshot: Sendable, Equatable {
    public let status: DeploymentStatus
    public let outputs: CDKStackOutputs?
    public let infrastructure: CDKInfrastructureConfiguration?

    public init(
        status: DeploymentStatus,
        outputs: CDKStackOutputs?,
        infrastructure: CDKInfrastructureConfiguration?
    ) {
        self.status = status
        self.outputs = outputs
        self.infrastructure = infrastructure
    }

    public enum DeploymentStatus: Sendable, Equatable {
        case notDeployed
        case deployed(DeployedStack)
        case failed(reason: String)
        case credentialExpired(message: String)
    }

    // Convenience accessors
    public var deployedStack: DeployedStack? {
        if case .deployed(let stack) = status { return stack }
        return nil
    }

    public var isDeployed: Bool { deployedStack != nil }

    public var canDeploy: Bool {
        switch status {
        case .notDeployed, .deployed, .failed: return true
        case .credentialExpired: return false
        }
    }

    public var canDestroy: Bool {
        if case .deployed = status { return true }
        return false
    }

    /// Create from CloudFormation state
    public static func from(_ cfState: CloudFormationState) -> DeploymentSnapshot {
        let stack = cfState.deployedStack
        let status: DeploymentStatus
        switch cfState {
        case .unknown, .loading, .notDeployed:
            status = .notDeployed
        case .deployed(let deployedStack):
            status = .deployed(deployedStack)
        case .deploying, .destroying:
            status = .notDeployed
        case .failed(let reason):
            status = .failed(reason: reason)
        case .credentialExpired(let message):
            status = .credentialExpired(message: message)
        }
        return DeploymentSnapshot(
            status: status,
            outputs: stack.map { CDKStackOutputs.from($0.outputs) },
            infrastructure: stack.map { CDKInfrastructureConfiguration($0.infrastructure) }
        )
    }
}

// MARK: - Workflow State (What workflows yield)

/// State yielded by a running workflow - includes startTime (workflow's concern)
public enum WorkflowState: Sendable, Equatable {
    case deploying(DeployProgress)
    case destroying(DestroyProgress)
    case updatingLambda(UpdateLambdaProgress)
    case completed(DeploymentSnapshot)

    /// Progress info for deploy operations
    public struct DeployProgress: Sendable, Equatable {
        public let step: Step
        public let startTime: Date
        public let detail: DeploymentProgress?

        public enum Step: Sendable, Equatable {
            case building
            case deploying
            case monitoring
        }
    }

    /// Progress info for destroy operations
    public struct DestroyProgress: Sendable, Equatable {
        public let step: Step
        public let startTime: Date
        public let detail: DeploymentProgress?

        public enum Step: Sendable, Equatable {
            case destroying
        }
    }

    /// Progress info for Lambda update operations
    public struct UpdateLambdaProgress: Sendable, Equatable {
        public let step: Step
        public let startTime: Date

        public enum Step: Sendable, Equatable {
            case checkingGitStatus
            case pushing
            case triggeringWorkflow
            case waitingForWorkflow
        }
    }

    /// Start time extracted from any state
    public var startTime: Date? {
        switch self {
        case .deploying(let p): return p.startTime
        case .destroying(let p): return p.startTime
        case .updatingLambda(let p): return p.startTime
        case .completed: return nil
        }
    }

    /// Final snapshot if completed
    public var completedSnapshot: DeploymentSnapshot? {
        if case .completed(let snapshot) = self { return snapshot }
        return nil
    }
}
```

### Workflow Implementation Pattern

Workflows capture `startTime` internally and yield complete state:

```swift
public struct DeployWorkflow {
    // ...

    public func run(options: Options, output: CLIOutputStream? = nil) -> AsyncThrowingStream<WorkflowState, Error> {
        AsyncThrowingStream { continuation in
            Task {
                let startTime = Date()  // Workflow captures its own start time

                // Building phase
                continuation.yield(.deploying(DeployProgress(
                    step: .building,
                    startTime: startTime,
                    detail: nil
                )))

                try await build()

                // Deploying phase
                continuation.yield(.deploying(DeployProgress(
                    step: .deploying,
                    startTime: startTime,
                    detail: nil
                )))

                // ... monitoring with progress updates ...

                // Completion - yield final snapshot
                let snapshot = DeploymentSnapshot(
                    status: .deployed(deployedStack),
                    outputs: outputs,
                    infrastructure: config
                )
                continuation.yield(.completed(snapshot))
                continuation.finish()
            }
        }
    }
}
```

### Simplified DeploymentModel

**Location:** `Sources/app-mac/Models/DeploymentModel.swift`

```swift
@MainActor @Observable
public class DeploymentModel {
    public private(set) var state: ModelState = .uninitialized

    // MARK: - Deploy Operations

    public func deploy(options: DeployWorkflow.Options, output: CLIOutputStream? = nil) async {
        guard state.canDeploy else { return }

        let prior = state.snapshot  // App layer captures prior (its concern)

        let workflow = DeployWorkflow(cdkClient: cdkClient, cfClient: cfClient, stackName: stackName)

        do {
            for try await workflowState in workflow.run(options: options, output: output) {
                state = ModelState(from: workflowState, prior: prior)
            }
        } catch {
            state = ModelState(error: error, preserving: prior)
        }
    }

    // MARK: - Model State

    public enum ModelState {
        case uninitialized
        case loading(prior: DeploymentSnapshot?)
        case ready(DeploymentSnapshot)
        case operating(WorkflowState, prior: DeploymentSnapshot?)

        /// Construct from workflow state + app-layer prior
        public init(from workflowState: WorkflowState, prior: DeploymentSnapshot?) {
            if let snapshot = workflowState.completedSnapshot {
                self = .ready(snapshot)
            } else {
                self = .operating(workflowState, prior: prior)
            }
        }

        /// Construct a failed state from a caught error
        public init(error: Error, preserving prior: DeploymentSnapshot?) {
            self = .ready(.failed(reason: error.localizedDescription, preserving: prior))
        }

        public var snapshot: DeploymentSnapshot? {
            switch self {
            case .uninitialized: return nil
            case .loading(let prior): return prior
            case .ready(let snapshot): return snapshot
            case .operating(_, let prior): return prior
            }
        }

        // ... other accessors ...
    }
}
```

### Before/After Comparison

**Before (19 lines):**
```swift
lastOperationError = nil
let startTime = Date()
let prior = state.snapshot

do {
    for try await progress in workflow.run(options: options, output: output) {
        state = .operating(ModelState.RunningWorkflow(
            kind: .deploying(progress),
            startTime: startTime,
            prior: prior
        ))

        if progress.step == .complete {
            let deployedStack = DeployedStack(
                outputs: progress.stackOutputs?.allOutputs ?? [:],
                infrastructure: progress.infrastructureConfiguration?.detectedInfrastructure ?? DetectedInfrastructure()
            )
            state = .ready(ModelState.DeploymentSnapshot(
                status: .deployed(deployedStack),
                outputs: progress.stackOutputs,
                infrastructure: progress.infrastructureConfiguration
            ))
        }
    }
}
```

**After (6 lines):**
```swift
let prior = state.snapshot

do {
    for try await workflowState in workflow.run(options: options, output: output) {
        state = ModelState(from: workflowState, prior: prior)
    }
}
```

## Implementation Plan

### Phase 1: Create Service-Layer State Types

**Status:** Not Started

**Files to Create:**
- `Sources/service-deploy/Models/DeploymentState.swift`

**Changes:**
1. Create `DeploymentSnapshot` struct in service-deploy
2. Create `WorkflowState` struct in service-deploy
3. Create `WorkflowKind` enum in service-deploy
4. Add `from(_ cfState: CloudFormationState)` factory method
5. Add convenience accessors (`isDeployed`, `canDeploy`, `canDestroy`)

**Verification:**
```bash
swift build
# Should compile with new types in service-deploy
```

### Phase 2: Update DeployWorkflow to Return Snapshot

**Status:** Not Started

**Files to Modify:**
- `Sources/service-deploy/Workflows/DeployWorkflow.swift`

**Changes:**
1. Update `Progress.Step.complete` to include `DeploymentSnapshot`:
   ```swift
   case complete(DeploymentSnapshot)
   ```
2. Add `toWorkflowState()` method to Progress
3. Add `completedSnapshot` computed property
4. Modify workflow completion to create snapshot:
   ```swift
   // In runWorkflow(), when CloudFormation reaches .deployed
   let snapshot = DeploymentSnapshot(
       status: .deployed(stack),
       outputs: CDKStackOutputs.from(stack.outputs),
       infrastructure: CDKInfrastructureConfiguration(stack.infrastructure)
   )
   continuation.yield(Progress(step: .complete(snapshot)))
   ```

**Verification:**
```bash
swift build
# Check that workflow compiles with new Progress type
```

### Phase 3: Update DestroyWorkflow to Return Snapshot

**Status:** Not Started

**Files to Modify:**
- `Sources/service-deploy/Workflows/DestroyWorkflow.swift`

**Changes:**
1. Update `Progress.Step.complete` to include `DeploymentSnapshot`:
   ```swift
   case complete(DeploymentSnapshot)
   ```
2. Add `toWorkflowState()` method to Progress
3. Add `completedSnapshot` computed property
4. Modify workflow completion to create snapshot:
   ```swift
   // On destroy completion
   let snapshot = DeploymentSnapshot(
       status: .notDeployed,
       outputs: nil,
       infrastructure: nil
   )
   continuation.yield(Progress(step: .complete(snapshot)))
   ```

**Verification:**
```bash
swift build
```

### Phase 4: Update UpdateLambdaWorkflow to Support WorkflowState

**Status:** Not Started

**Files to Modify:**
- `Sources/service-deploy/Workflows/UpdateLambdaWorkflow.swift`

**Changes:**
1. Add `toWorkflowState()` method to Progress
2. No snapshot on completion (Lambda updates don't change infrastructure)

**Verification:**
```bash
swift build
```

### Phase 5: Update DeploymentModel to Use Service-Layer Types

**Status:** Not Started

**Files to Modify:**
- `Sources/app-mac/Models/DeploymentModel.swift`

**Changes:**
1. Import service-layer types: `import service_deploy_remote`
2. Update `ModelState` to use service-layer types:
   - Keep `ModelState` enum (app-specific state machine)
   - Use `DeploymentSnapshot` from service-deploy
   - Use `WorkflowState` from service-deploy
3. Simplify `deploy()` to use `progress.toWorkflowState()` and `progress.completedSnapshot`
4. Simplify `destroy()` similarly
5. Simplify `updateLambdaCode()` similarly
6. Update `refresh()` to use `DeploymentSnapshot.from()`

**Before (lines 200-218):**
```swift
for try await progress in workflow.run(options: options, output: output) {
    state = .operating(ModelState.RunningWorkflow(
        kind: .deploying(progress),
        startTime: startTime,
        prior: prior
    ))

    if progress.step == .complete {
        let deployedStack = DeployedStack(
            outputs: progress.stackOutputs?.allOutputs ?? [:],
            infrastructure: progress.infrastructureConfiguration?.detectedInfrastructure ?? DetectedInfrastructure()
        )
        state = .ready(ModelState.DeploymentSnapshot(
            status: .deployed(deployedStack),
            outputs: progress.stackOutputs,
            infrastructure: progress.infrastructureConfiguration
        ))
    }
}
```

**After:**
```swift
for try await progress in workflow.run(options: options, output: output) {
    state = .operating(progress.toWorkflowState(startTime: startTime, prior: prior))

    if let snapshot = progress.completedSnapshot {
        state = .ready(snapshot)
    }
}
```

**Verification:**
```bash
swift build
# Verify Mac app compiles
open SwiftLambdaSample.xcodeproj
# Test deploy/destroy operations in Mac app
```

### Phase 6: Remove Duplicate Types from DeploymentModel

**Status:** Not Started

**Files to Modify:**
- `Sources/app-mac/Models/DeploymentModel.swift`

**Changes:**
1. Remove `ModelState.DeploymentSnapshot` (lines 353-441)
2. Remove `ModelState.RunningWorkflow` (lines 446-477)
3. Keep `ModelState` enum as thin wrapper
4. Update all references to use service-layer types directly

**Verification:**
```bash
swift build
# Ensure no compilation errors
# Run Mac app to verify UI still works correctly
```

### Phase 7: Update CLI Commands (Optional)

**Status:** Not Started

**Files to Modify (if needed):**
- `Sources/app-cli/Commands/StatusCommand.swift`
- Any CLI commands that construct state manually

**Note:** CLI commands already use workflows directly and don't need `ModelState`, but they may benefit from using `DeploymentSnapshot` for consistent state representation.

## Migration Strategy

### Backward Compatibility

During migration (Phases 1-4), both old and new state types coexist:
- Service-layer workflows return enhanced Progress with snapshots
- App-layer DeploymentModel continues to work (both old and new patterns)
- No breaking changes until Phase 6 (cleanup)

### Testing Approach

**Unit Tests:**
```swift
// Test DeploymentSnapshot creation
func testSnapshotFromCloudFormationState() {
    let cfState = CloudFormationState.deployed(DeployedStack(
        outputs: ["ApiGatewayUrl": "https://example.com"],
        infrastructure: DetectedInfrastructure(hasDatabase: true)
    ))

    let snapshot = DeploymentSnapshot.from(cfState)

    XCTAssertTrue(snapshot.isDeployed)
    XCTAssertTrue(snapshot.canDestroy)
    XCTAssertEqual(snapshot.outputs?.apiGatewayUrl, "https://example.com")
}

// Test WorkflowState creation from progress
func testWorkflowStateFromProgress() {
    let progress = DeployWorkflow.Progress(step: .building)
    let startTime = Date()
    let prior = DeploymentSnapshot(status: .notDeployed, outputs: nil, infrastructure: nil)

    let workflowState = progress.toWorkflowState(startTime: startTime, prior: prior)

    XCTAssertEqual(workflowState.startTime, startTime)
    XCTAssertEqual(workflowState.prior, prior)
}
```

**Integration Tests:**
- Deploy operation end-to-end in Mac app
- Destroy operation end-to-end in Mac app
- Lambda update operation in Mac app
- Verify UI displays progress correctly
- Verify state transitions are correct

### Rollback Plan

Each phase is independently reversible:
- **Phase 1-4:** Additive changes - can be kept or removed without impact
- **Phase 5:** If DeploymentModel breaks, revert to manual state construction
- **Phase 6:** Can defer cleanup indefinitely if needed

## Success Criteria

1. **Compilation:** All phases compile without errors
2. **Functionality:** Mac app deploy/destroy/update operations work correctly
3. **State Accuracy:** UI displays correct state at all stages (building, deploying, complete, etc.)
4. **Code Simplification:** DeploymentModel operations are 30-50% fewer lines
5. **No Duplication:** State construction logic lives in service layer, not duplicated in app layer
6. **Layer Compliance:** Service layer has no dependency on app layer
7. **Testability:** State construction can be unit tested in service layer

## Tradeoffs and Alternatives

### Chosen Approach: Service-Layer State with App Mapping

**Pros:**
- ✅ Clear layer separation
- ✅ Workflows own state modeling (better SoC)
- ✅ Testable state construction
- ✅ App layer stays thin
- ✅ No circular dependencies

**Cons:**
- ⚠️ Some type duplication (`ModelState` wraps service types)
- ⚠️ Mapping code still exists (but centralized)

### Alternative: Move Everything to Service Layer

**Rejected because:**
- ❌ Would create service → app dependency (for @Observable)
- ❌ Violates "models in app layer" principle
- ❌ Makes SwiftUI binding harder

### Alternative: Keep Status Quo with Better Helpers

**Rejected because:**
- ❌ Doesn't solve duplication problem
- ❌ State construction logic still scattered
- ❌ Doesn't improve testability

## Related Documentation

- `docs/architecture/layered-architecture.md` - Layer definitions and principles
- `docs/proposed/workflow-refactor.md` - Original workflow refactor specification
- `Sources/app-mac/Models/DeploymentModel.swift` - Current model implementation
- `Sources/service-deploy/Workflows/` - Current workflow implementations
- `Sources/sdk-aws/CloudFormation/CloudFormationState.swift` - SDK state types

## Open Questions

1. **Should `DeploymentSnapshot` be its own file or part of `DeploymentState.swift`?**
   - Recommendation: Start together, split if file grows large

2. **Should workflows always return snapshots, or only on completion?**
   - Recommendation: Only on completion (keeps Progress lightweight)

3. **Should `WorkflowState` include more context (e.g., operation options)?**
   - Recommendation: No - keep it minimal (kind, startTime, prior)

4. **Should StatusWorkflow also return a service-layer snapshot?**
   - Recommendation: Consider in future refactor (lower priority)

5. **How to handle error state snapshots?**
   - Recommendation: App layer catches errors and creates failed snapshots (current pattern is fine)

## Next Steps

1. **Review this specification** with Bill to confirm approach
2. **Create Phase 1** - Service-layer state types
3. **Test incrementally** after each phase
4. **Update this document** as implementation reveals issues/learnings
