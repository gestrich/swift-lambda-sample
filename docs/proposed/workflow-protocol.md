# Workflow Protocol Standardization

**Status:** In Progress (Phase 2 Complete)
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

### Phase 3: Migrate Extra-Parameter Workflows (Category 2)

**Workflows:** `DeployWorkflow`, `DestroyWorkflow`

**Current signature:**
```swift
public func run(options: Options, output: CLIOutputStream?) -> AsyncThrowingStream<WorkflowState, Error>
```

**Change:** Move `output` into `Options` struct:

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
public func stream(options: Options) -> AsyncThrowingStream<WorkflowState, Error>
```

**Update callers:**
- `DeployCommand` - pass `output` in options
- `DeploymentModel` - pass `output` in options

**Verification:** Build succeeds. Deploy commands work as before.

### Phase 4: Split Multi-Operation Workflows (Category 3)

**Current:** `GitHubCIWorkflow` has multiple operations:
- `pushAndDeploy(timeoutMinutes:)` - Push commits and monitor deployment
- `monitorRun(runId:, timeoutMinutes:)` - Monitor existing run
- `getStatus()` - One-shot status query

**Proposed split:**

#### 4.1 `GitHubPushAndDeployWorkflow`
```swift
public struct GitHubPushAndDeployWorkflow: StreamingWorkflow {
    public typealias State = GitHubCIState

    public struct Options: Sendable {
        public let timeoutMinutes: Int
        public init(timeoutMinutes: Int = 10) { ... }
    }

    public func stream(options: Options) -> AsyncThrowingStream<State, Error>
}
```

#### 4.2 `GitHubMonitorRunWorkflow`
```swift
public struct GitHubMonitorRunWorkflow: StreamingWorkflow {
    public typealias State = GitHubCIState

    public struct Options: Sendable {
        public let runId: String
        public let timeoutMinutes: Int
    }

    public func stream(options: Options) -> AsyncThrowingStream<State, Error>
}
```

#### 4.3 Keep shared types
Move shared types to a common location:
- `GitHubCIState` (renamed from `GitHubCIWorkflow.State`)
- `GitHubCIProgress` (renamed from `GitHubCIWorkflow.DeployProgress`)
- `GitStatus`, `Snapshot`, `StatusSnapshot`

#### 4.4 Handle `getStatus()` one-shot query

Similar to `CloudWatchLogsWorkflow.fetch()`, the `getStatus()` method is a one-shot query, not a streaming operation. Per the design decision on one-shot queries:

**Options:**
1. Keep `getStatus()` on one of the new workflows as a convenience method
2. Move to `GitHubCLIClient` or create a dedicated status query

**Recommendation:** Move status query logic to `GitHubCLIClient` in the SDK layer, or provide it as a static factory method that doesn't require workflow instantiation.

**Files:**
- Create: `Sources/features/DeployRemoteFeature/workflows/GitHubPushAndDeployWorkflow.swift`
- Create: `Sources/features/DeployRemoteFeature/workflows/GitHubMonitorRunWorkflow.swift`
- Delete: `Sources/features/DeployRemoteFeature/workflows/GitHubCIWorkflow.swift` (after migration)
- Create: `Sources/features/DeployRemoteFeature/services/GitHubCITypes.swift` - Shared types

**Update callers:**
- `UpdateLambdaWorkflow` - Use `GitHubPushAndDeployWorkflow`
- `ResumeMonitoringWorkflow` - Use `GitHubMonitorRunWorkflow`
- `DeploymentModel` / Mac app - Update to use new workflow types

**Verification:** Build succeeds. Lambda update and monitoring work as before.

### Phase 5: Migrate Inline-Parameter Workflows (Category 4)

**Current:** `CloudWatchLogsWorkflow`
```swift
public func stream(since: String, pollInterval: Duration, maxEntries: Int) -> AsyncThrowingStream<State, Error>
public func fetch(since: String) async throws -> [CloudWatchLogEntry]
```

**Change:** Create `Options` struct for streaming:

```swift
import Uniflow

public struct CloudWatchLogsWorkflow: StreamingWorkflow {
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
}
```

#### Handling One-Shot Queries (`fetch`)

The `fetch(since:)` method is a **one-shot query** - it makes a single call and returns results. This raises the question: how should one-shot operations fit into the protocol hierarchy?

**Options:**

1. **Make it a `Workflow` conformer** - Create `CloudWatchLogsFetchWorkflow: Workflow` with just `run()`. This keeps all operations in the workflow abstraction.

2. **Use SDK client directly** - Remove the wrapper entirely. Callers use `CloudWatchLogsClient.fetchLogs()` from the SDK layer.

3. **Keep as extra method** - The `CloudWatchLogsWorkflow` conforms to `StreamingWorkflow` but also has a `fetch()` convenience method.

**Recommendation:** Option 2 - Use the SDK client directly.

**Rationale:**
- `fetch()` is a thin wrapper around `CloudWatchLogsClient.fetchLogs()` with no meaningful orchestration
- The `Workflow` abstraction is valuable when there's orchestration logic, dependency injection benefits, or testability concerns
- For simple SDK calls, the wrapper adds indirection without benefit
- If orchestration is needed later (retry logic, caching, etc.), a `Workflow` conformer can be added then

**When a one-shot `Workflow` makes sense:**
- The operation has non-trivial logic (retries, fallbacks, composition)
- You want consistent dependency injection patterns
- Testing benefits from the workflow abstraction

**Migration:**
```swift
// Before (on workflow)
let entries = try await workflow.fetch(since: "5m")

// After (use SDK client directly)
let entries = try await cloudWatchClient.fetchLogs(
    logGroup: logGroup,
    since: "5m",
    credentialProvider: credentialProvider
)
```

### Phase 6: Update Remaining DeployRemote Workflows

**Workflows:** `DeployInitWorkflow`, `DeployStatusWorkflow`, `UpdateLambdaWorkflow`

Apply the same pattern:
1. Rename `run(options:)` to `stream(options:)`
2. Add protocol conformance
3. Ensure `Options` struct exists

**Verification:** All DeployRemoteFeature workflows conform to protocol.

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
