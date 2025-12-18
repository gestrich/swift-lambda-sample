# Workflow Protocol Standardization

**Status:** In Progress (Phase 6 Complete)
**Created:** 2025-12-17
**Related:** [workflow-refactor.md](workflow-refactor.md), [layered-architecture.md](../architecture/layered-architecture.md)

## Objective

Define a protocol hierarchy that standardizes how workflows expose their execution interface:

1. **`Workflow`** - Base protocol with a single `run(options:)` method that executes and returns a final result
2. **`StreamingWorkflow`** - Extends `Workflow` with a `stream(options:)` method that yields state updates via `AsyncThrowingStream`

This two-tier approach enables:
- Simple workflows to conform to just `Workflow` when streaming isn't needed
- Complex workflows to conform to `StreamingWorkflow` when progress updates are valuable
- Consistent consumption patterns across CLI commands, models, and tests

## Background

The codebase has 32 workflows across 4 feature modules with inconsistent interfaces:

| Current Pattern | Example | Count |
|-----------------|---------|-------|
| `run(options:)` returning stream | `XcodeBuildWorkflow` | ~24 |
| `run(options:, output:)` with extra params | `DeployWorkflow` | 2 |
| Multiple operations per workflow | `GitHubCIWorkflow` | 2 |
| `stream(since:, ...)` with inline params | `CloudWatchLogsWorkflow` | 1 |

This inconsistency makes it harder to:
- Build generic workflow consumers (e.g., test harnesses, logging wrappers)
- Understand the execution model when switching between workflows
- Compose workflows in a uniform way

## Technical Approach

### Protocol Location

Create a new SDK target called **Uniflow** at `Sources/sdks/Uniflow/`. This keeps the protocol at the SDK layer where it can be imported by all feature modules without creating circular dependencies.

### Protocol Definition

```swift
/// A workflow that executes and returns a final result.
public protocol Workflow: Sendable {
    /// Configuration options for the workflow (use Void for no options)
    associatedtype Options: Sendable = Void

    /// The final result type returned by `run()`
    associatedtype Result: Sendable

    /// Execute the workflow and return the final result
    func run(options: Options) async throws -> Result
}

/// A workflow that yields state updates during execution via streaming.
/// Conforms to Workflow, providing run() via a default implementation that consumes the stream.
public protocol StreamingWorkflow: Workflow {
    /// The type of state updates yielded during execution
    associatedtype State: Sendable

    /// Execute the workflow, streaming state updates
    func stream(options: Options) -> AsyncThrowingStream<State, Error>
}
```

### Default Implementations

```swift
// MARK: - Workflow Extensions

/// Convenience method for workflows with no options
extension Workflow where Options == Void {
    public func run() async throws -> Result {
        try await run(options: ())
    }
}

// MARK: - StreamingWorkflow Extensions

/// Default run() implementation when Result == State (returns last state from stream)
extension StreamingWorkflow where Result == State {
    public func run(options: Options) async throws -> Result {
        var lastState: State?
        for try await state in stream(options: options) {
            lastState = state
        }
        guard let result = lastState else {
            throw WorkflowError.noStateYielded
        }
        return result
    }
}

/// Convenience methods for streaming workflows with no options
extension StreamingWorkflow where Options == Void {
    public func stream() -> AsyncThrowingStream<State, Error> {
        stream(options: ())
    }
}

/// Error type for workflow execution
public enum WorkflowError: Error, LocalizedError {
    case noStateYielded

    public var errorDescription: String? {
        switch self {
        case .noStateYielded:
            return "Workflow completed without yielding any state"
        }
    }
}
```

### When to Use Each Protocol

| Protocol | Use When | Example |
|----------|----------|---------|
| `Workflow` | The operation completes and returns a single result; no intermediate progress is meaningful | One-shot status checks, configuration loading |
| `StreamingWorkflow` | The operation has multiple steps and callers benefit from progress updates | Deployments, builds, multi-step installations |

Most workflows in this codebase are `StreamingWorkflow` since they perform multi-step operations where progress feedback is valuable for CLI output and UI updates.

## Implementation Plan

### Phase 1: Create Uniflow SDK ✅ COMPLETED

**Create new SDK target** at `Sources/sdks/Uniflow/`:

**Files created:**
- `Sources/sdks/Uniflow/Workflow.swift` - `Workflow` protocol definition and extensions
- `Sources/sdks/Uniflow/StreamingWorkflow.swift` - `StreamingWorkflow` protocol definition and extensions
- `Sources/sdks/Uniflow/WorkflowError.swift` - Error types (requires `import Foundation` for `LocalizedError`)

**Package.swift changes:**
```swift
.target(
    name: "Uniflow",
    path: "Sources/sdks/Uniflow"
),
```

**Uniflow added as dependency** to all feature targets that define workflows:
- `DeployRemoteFeature`
- `DeployLocalXcodeFeature`
- `DeployLocalLinuxFeature`
- `SetupFeature`

**Verification:** ✅ Build succeeds, both protocols compile, features can import Uniflow.

### Phase 2: Migrate Simple Workflows (Category 1) ✅ COMPLETED

These workflows have `run(options:)` returning a stream. Migration involved conforming to `StreamingWorkflow` and renaming the method.

**Pattern:**
```swift
// Before
public func run(options: Options = Options()) -> AsyncThrowingStream<Progress, Error>

// After (conforms to StreamingWorkflow)
public func stream(options: Options) -> AsyncThrowingStream<State, Error>
// run(options:) provided by StreamingWorkflow extension
```

**Migrated Workflows (24 total):**

| Feature | Workflows |
|---------|-----------|
| `DeployLocalXcodeFeature` | `XcodeBuildWorkflow`, `XcodeStartAllWorkflow`, `XcodeStartServicesWorkflow`, `XcodeStartLambdaWorkflow`, `XcodeStopAllWorkflow`, `XcodeStopServicesWorkflow`, `XcodeStopLambdaWorkflow`, `XcodeStatusWorkflow`, `XcodeTestWorkflow`, `XcodeCopyConfigWorkflow` |
| `DeployLocalLinuxFeature` | `LinuxBuildWorkflow`, `LinuxStartAllWorkflow`, `LinuxStartServicesWorkflow`, `LinuxStartLambdaWorkflow`, `LinuxStopAllWorkflow`, `LinuxStopServicesWorkflow`, `LinuxStopLambdaWorkflow`, `LinuxStatusWorkflow`, `LinuxTestWorkflow`, `LinuxSetupNetworkWorkflow`, `LinuxRunInteractiveWorkflow`, `LinuxCopyConfigWorkflow` |
| `SetupFeature` | `DependencyInstallWorkflow`, `DependencyStatusWorkflow` |

**Changes made per workflow:**
1. Added `import Uniflow` and `StreamingWorkflow` protocol conformance
2. Renamed `run(options:)` to `stream(options:)`
3. Renamed `Progress` struct to `State` for consistency
4. Added `typealias Result = State` for default `run()` implementation
5. Updated nested state references (e.g., `servicesProgress` → `servicesState`)

**Callers updated:**
- `Sources/apps/CLIApp/Commands/LocalCommand.swift` - All workflow calls use `stream()`, type references updated to `State`
- `Sources/apps/MacApp/Models/XcodeLocalModel.swift` - Updated to use `stream()`
- `Sources/apps/MacApp/Models/LinuxLocalModel.swift` - Updated to use `stream()`
- `Sources/apps/MacApp/Models/DependencyStatusModel.swift` - Updated to use `stream(options:)`

**Technical notes:**
- Workflows with `Options = Void` can use the convenience `stream()` method without arguments
- Workflows embedding other workflows' state now reference `.State` instead of `.Progress` (e.g., `XcodeStartAllWorkflow.State.Detail.servicesState`)
- The default `run()` implementation consumes the stream and returns the last state

**Verification:** ✅ Build succeeds. All CLI commands and Mac app models compile and use the new API.

### Phase 3: Migrate Extra-Parameter Workflows (Category 2) ✅ COMPLETED

**Workflows:** `DeployWorkflow`, `DestroyWorkflow`

**Previous signature:**
```swift
public func run(options: Options, output: CLIOutputStream?) -> AsyncThrowingStream<WorkflowState, Error>
```

**New signature (StreamingWorkflow conformance):**
```swift
public struct Options: Sendable {
    public let infrastructure: InfrastructureShape
    public let requireApproval: Bool
    public let output: CLIOutputStream?  // moved here

    public init(
        infrastructure: InfrastructureShape = .minimal,
        requireApproval: Bool = false,
        output: CLIOutputStream? = nil
    ) { ... }
}

// Now conforms to StreamingWorkflow protocol
public func stream(options: Options) -> AsyncThrowingStream<State, Error>
```

**Changes made per workflow:**
1. Added `import Uniflow` and `StreamingWorkflow` protocol conformance
2. Renamed `run(options:output:)` to `stream(options:)`
3. Moved `output: CLIOutputStream?` parameter into `Options` struct
4. Added `typealias State = WorkflowState` and `typealias Result = State`
5. Updated private `runWorkflow` method to extract `output` from `options`

**Callers updated:**
- `Sources/apps/CLIApp/Commands/DeployCommand.swift` - Uses `stream(options:)`
- `Sources/apps/CLIApp/Commands/TearDownCommand.swift` - Uses `stream(options:)`
- `Sources/features/DeployRemoteFeature/workflows/DeployInitWorkflow.swift` - Uses `stream(options:)`
- `Sources/apps/MacApp/Models/DeploymentModel.swift` - Uses `stream(options:)`, passes output in options
- `Sources/apps/MacApp/UI/RemoteService/CDKInfrastructureSectionView.swift` - Passes output in options

**Technical notes:**
- `DestroyWorkflow.Options` now includes `output` parameter with default `nil`
- `DeployWorkflow.Options` convenience initializers updated to include `output` parameter
- Both workflows use `typealias State = WorkflowState` so existing `WorkflowState.DeployProgress` and `WorkflowState.DestroyProgress` references continue to work

**Verification:** ✅ Build succeeds. All CLI commands and Mac app compile and use the new API.

### Phase 4: Split Multi-Operation Workflows (Category 3) ✅ COMPLETED

**Previous:** `GitHubCIWorkflow` had multiple operations:
- `pushAndDeploy(timeoutMinutes:)` - Push commits and monitor deployment
- `monitorRun(runId:, timeoutMinutes:)` - Monitor existing run
- `getStatus()` - One-shot status query

**New structure:**

#### 4.1 `GitHubPushAndDeployWorkflow` (StreamingWorkflow)
```swift
public struct GitHubPushAndDeployWorkflow: StreamingWorkflow {
    public typealias State = GitHubCIState
    public typealias Result = State

    public struct Options: Sendable {
        public let timeoutMinutes: Int
        public init(timeoutMinutes: Int = 10) { ... }
    }

    public func stream(options: Options) -> AsyncThrowingStream<State, Error>
}
```

#### 4.2 `GitHubMonitorRunWorkflow` (StreamingWorkflow)
```swift
public struct GitHubMonitorRunWorkflow: StreamingWorkflow {
    public typealias State = GitHubCIState
    public typealias Result = State

    public struct Options: Sendable {
        public let runId: String
        public let timeoutMinutes: Int
        public init(runId: String, timeoutMinutes: Int = 10) { ... }
    }

    public func stream(options: Options) -> AsyncThrowingStream<State, Error>
}
```

#### 4.3 `GitHubStatusQuery` (one-shot query, not a workflow)
```swift
public struct GitHubStatusQuery: Sendable {
    public func execute() async throws -> GitHubCIStatusSnapshot
}
```

Per the design decision on one-shot queries, `getStatus()` was moved to a dedicated query struct rather than conforming to `Workflow`. This keeps the workflow abstraction focused on multi-step operations.

#### 4.4 Shared types in `GitHubCITypes.swift`
- `GitHubCIState` - Streamed state enum (`.deploying`, `.completed`)
- `GitHubCISnapshot` - Complete operation result
- `GitHubCIStatusSnapshot` - Lightweight status for refresh operations
- `GitHubCIGitStatus` - Git repository status
- `GitHubCIDeployProgress` - Progress during deployment
- `GitHubCIStep` - Deployment step enumeration
- `GitHubCIWorkflowError` - Error types

**Files created:**
- `Sources/features/DeployRemoteFeature/workflows/GitHubPushAndDeployWorkflow.swift`
- `Sources/features/DeployRemoteFeature/workflows/GitHubMonitorRunWorkflow.swift`
- `Sources/features/DeployRemoteFeature/services/GitHubCITypes.swift`
- `Sources/features/DeployRemoteFeature/services/GitHubStatusQuery.swift`

**Files deleted:**
- `Sources/features/DeployRemoteFeature/workflows/GitHubCIWorkflow.swift`

**Callers updated:**
- `Sources/apps/MacApp/Models/GitHubCIModel.swift` - Now uses three separate components:
  - `GitHubPushAndDeployWorkflow` for push & deploy operations
  - `GitHubMonitorRunWorkflow` for monitoring existing runs
  - `GitHubStatusQuery` for status refresh
- `Sources/apps/MacApp/UI/RemoteService/GitHubCISectionView.swift` - Updated type references from `GitHubCIWorkflow.Snapshot` to `GitHubCISnapshot`

**Technical notes:**
- The `GitHubCIModel` convenience initializer creates all three components from a single `GitHubConfiguration`
- Shared clients (`GitHubCLIClient`, `GitClient`) are passed to each component
- All types are top-level in their respective files (not nested in workflow structs) for easier access
- `WorkflowRunInfo` extension for parsing `GitHubWorkflowRun` remains in `GitHubCITypes.swift`

**Verification:** ✅ Build succeeds. All CLI commands and Mac app compile and use the new API.

### Phase 5: Migrate Inline-Parameter Workflows (Category 4) ✅ COMPLETED

**Workflow:** `CloudWatchLogsWorkflow`

**Previous signature:**
```swift
public func stream(since: String, pollInterval: Duration, maxEntries: Int) -> AsyncThrowingStream<State, Error>
public func fetch(since: String) async throws -> [CloudWatchLogEntry]
```

**New signature (StreamingWorkflow conformance):**
```swift
import Uniflow

public struct CloudWatchLogsWorkflow: StreamingWorkflow {
    public typealias Result = State

    public struct Options: Sendable {
        public let since: String
        public let pollInterval: Duration
        public let maxEntries: Int

        public init(
            since: String,
            pollInterval: Duration = .seconds(3),
            maxEntries: Int = 1000
        ) { ... }
    }

    // Protocol conformance - streaming logs
    public func stream(options: Options) -> AsyncThrowingStream<State, Error>

    // Kept as convenience method (see rationale below)
    public func fetch(since: String) async throws -> [CloudWatchLogEntry]
}
```

#### Decision on One-Shot Query (`fetch`)

The spec recommended using the SDK client directly (Option 2), but after examining the codebase, **Option 3 (keep as extra method)** was chosen.

**Rationale:**
- `CloudWatchLogsModel` only holds the workflow, not the underlying client, `logGroup`, or `credentialProvider`
- Adopting Option 2 would require significant model refactoring to inject additional dependencies
- The `fetch()` method encapsulates the same orchestration context (client, logGroup, credentials) as `stream()`
- Keeping `fetch()` as a convenience method maintains backward compatibility with minimal changes

**Changes made:**
1. Added `import Uniflow` and `StreamingWorkflow` protocol conformance
2. Created `Options` struct with `since`, `pollInterval`, and `maxEntries` parameters
3. Updated `stream()` signature from inline parameters to `stream(options:)`
4. Added `typealias Result = State` for default `run()` implementation
5. Kept `fetch(since:)` as a convenience method (unchanged)

**Callers updated:**
- `Sources/apps/MacApp/Models/CloudWatchLogsModel.swift` - Uses `CloudWatchLogsWorkflow.Options(since:)` with `stream(options:)`

**Technical notes:**
- The `Options` struct uses default values for `pollInterval` (.seconds(3)) and `maxEntries` (1000), matching the previous defaults
- The `fetch()` method remains unchanged since it's a simple one-shot query, not a streaming operation
- The model creates an `Options` instance inline when starting streaming

**Verification:** ✅ Build succeeds. MacApp compiles and uses the new API.

### Phase 6: Update Remaining DeployRemote Workflows ✅ COMPLETED

**Workflows:** `DeployInitWorkflow`, `DeployStatusWorkflow`, `UpdateLambdaWorkflow`

**Changes made per workflow:**

#### 6.1 `DeployInitWorkflow`
1. Added `import Uniflow` and `StreamingWorkflow` protocol conformance
2. Renamed `run(options:)` to `stream(options:)`
3. Renamed `Progress` struct to `State`
4. Added `typealias Result = State`
5. Renamed nested detail cases: `deployProgress` → `deployState`, `lambdaProgress` → `lambdaState`
6. Updated internal workflow call from `run(options:)` to `stream(options:)` for `UpdateLambdaWorkflow`

#### 6.2 `DeployStatusWorkflow`
1. Added `import Uniflow` and `StreamingWorkflow` protocol conformance
2. Added `typealias Options = Void` (workflow has no options)
3. Renamed `run()` to `stream(options:)` (uses `stream()` convenience method from protocol)
4. Renamed `Progress` struct to `State`
5. Added `typealias Result = State`

#### 6.3 `UpdateLambdaWorkflow`
1. Added `import Uniflow` and `StreamingWorkflow` protocol conformance
2. Renamed `run(options:)` to `stream(options:)`
3. Added `typealias State = WorkflowState` (uses existing type)
4. Added `typealias Result = State`
5. Removed default argument `Options()` from method signature (now provided by protocol extension)

**Callers updated:**
- `Sources/apps/CLIApp/Commands/DeployInitCommand.swift` - Uses `stream(options:)`, renamed helper methods to `printState`, `printDeployState`, `printLambdaState`
- `Sources/apps/CLIApp/Commands/StatusCommand.swift` - Uses `stream()`, renamed helper method to `printState`
- `Sources/apps/CLIApp/Commands/UpdateLambdaCommand.swift` - Uses `stream(options:)`
- `Sources/apps/MacApp/Models/DeploymentModel.swift` - Uses `stream(options:)` for `UpdateLambdaWorkflow`

**Technical notes:**
- `DeployStatusWorkflow` uses `Options = Void` since it has no configurable parameters
- `UpdateLambdaWorkflow` uses `typealias State = WorkflowState` to align with the shared workflow state type
- The detail case renames in `DeployInitWorkflow.State.Detail` (`deployProgress` → `deployState`, `lambdaProgress` → `lambdaState`) follow the convention established in Phase 2

**Verification:** ✅ Build succeeds. All CLI commands and Mac app compile and use the new API.

### Phase 7: Documentation and Cleanup

1. Update `docs/architecture/layered-architecture.md` to document the `Workflow` protocol
2. Add code examples showing both `stream()` and `run()` usage patterns
3. Remove any deprecated methods or backward-compatibility shims

## Migration Strategy

Each phase is independently valuable and testable:

| Phase | Scope | Breaking Changes |
|-------|-------|------------------|
| 1 | Protocol creation (`Workflow` + `StreamingWorkflow`) | None |
| 2 | Simple workflows | Method rename (`run` → `stream`), but `run()` still available via `StreamingWorkflow` extension |
| 3 | DeployWorkflow | Signature change (output moves to options) |
| 4 | GitHubCI split | Type renames, new workflow structs |
| 5 | CloudWatch | Signature change (inline params → options) |
| 6 | Remaining remote | Method rename |
| 7 | Documentation | None |

**Caller updates required:**
- CLI commands: Update method calls from `run()` to `stream()` where streaming is desired (for `StreamingWorkflow` conformers)
- Models: Update to use `stream()` for progress tracking, `run()` for fire-and-forget
- Tests: Can use either `stream()` or `run()` depending on what's being tested (all workflows support `run()`)

## Success Criteria

1. All 32 workflows conform to either `Workflow` or `StreamingWorkflow` protocol
2. Build succeeds with no warnings
3. All existing functionality preserved
4. CLI commands and Mac app work as before
5. Both protocols documented in architecture docs

## Dependencies

- Requires no external dependencies
- Builds on existing `AsyncThrowingStream` patterns already used throughout the codebase

## Testing Considerations

1. **Unit tests** can use `run()` for simple assertions on final state (works for both protocols)
2. **Integration tests** can use `stream()` to verify progress sequence (only for `StreamingWorkflow`)
3. **Generic test harnesses** can be built to verify protocol conformance:

```swift
// Test any Workflow (including StreamingWorkflow)
func verifyWorkflow<W: Workflow>(_ workflow: W, options: W.Options) async throws -> W.Result {
    try await workflow.run(options: options)
}

// Test StreamingWorkflow specifically
func verifyStreamingWorkflow<W: StreamingWorkflow>(_ workflow: W, options: W.Options) async throws {
    var states: [W.State] = []
    for try await state in workflow.stream(options: options) {
        states.append(state)
    }
    XCTAssertFalse(states.isEmpty, "Workflow should yield at least one state")
}
```

## Design Decisions

The following decisions have been made:

| Decision | Resolution |
|----------|------------|
| **Protocol hierarchy** | Two protocols: `Workflow` (base with `run()`) and `StreamingWorkflow` (extends with `stream()`) |
| **Protocol location** | New SDK target called **Uniflow** at `Sources/sdks/Uniflow/` |
| **State naming** | Standardize on `State` for all `StreamingWorkflow` conformers (rename existing `Progress` types) |
| **One-shot queries** | Remove from streaming workflows; callers use SDK clients directly or conform to just `Workflow` |
| **Void options** | The `where Options == Void` extension is sufficient; no default initializer required |

## Open Questions

None remaining.
