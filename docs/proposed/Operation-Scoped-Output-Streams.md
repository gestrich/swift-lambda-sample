# Operation-Scoped Output Streams

## Status

**Proposed** - Not yet implemented

## Problem

Currently, all CLI output from a service flows to a single global stream. When multiple operations run concurrently (or even sequentially), their output is interleaved in the UI, making it difficult for users to understand which output belongs to which operation.

**Example scenario:**
1. User clicks "Deploy Infrastructure" (CDK deploy)
2. While CDK is deploying, user clicks "Push & Deploy" (GitHub Actions)
3. The output panel shows interleaved output from both operations
4. User cannot distinguish CDK output from GitHub output

## Goals

1. A client calling an operation should be able to see **only** the output from that operation and its child commands
2. **Clients own the output stream** - they create it, pass it to service calls, and consume it
3. Services remain stateless with respect to output - they just forward to whatever stream is passed
4. Maintain backward compatibility - global output stream continues to work
5. Use the existing `CLIOutputStream` pattern (no new stream types)

## Current Architecture

### Data Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ RemoteServiceView                                                           │
│                                                                             │
│   CollapsibleOutputPanel(                                                   │
│     streamProvider: { await service.cliService.outputStream() }             │
│   )                                                                         │
│       │                                                                     │
│       ▼                                                                     │
│   StreamingTextView subscribes to stream                                    │
│   Shows ALL output from ALL operations                                      │
└─────────────────────────────────────────────────────────────────────────────┘
                              │
┌─────────────────────────────────────────────────────────────────────────────┐
│ RemoteService                                                               │
│                                                                             │
│   cliService: CLIService                                                    │
│       │                                                                     │
│       └── globalOutput: CLIOutputStream                                     │
│               │                                                             │
│               └── ALL commands send here                                    │
│                                                                             │
│   Child Services (share same cliService):                                   │
│     cdkService, awsService, githubService, etc.                             │
│     └── all call cliService.execute() → globalOutput                        │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Current Isolation Level

- **Per-service**: RemoteService, XcodeLocalService, and LinuxLocalService each have their own CLIService instance
- **NOT per-operation**: All operations within a service share the same output stream

## Proposed Architecture

### Core Idea

Add an optional `output: CLIOutputStream?` parameter to all service methods. **The client creates and owns the stream**, passes it to service calls, and consumes it. Services simply forward output to whatever stream is passed - they don't own or manage streams themselves.

### Data Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ View (Client)                                                               │
│                                                                             │
│   @State var output: CLIOutputStream?                                       │
│   @State var outputLines: [StreamOutput] = []                               │
│                                                                             │
│   Button("Deploy") {                                                        │
│       let stream = CLIOutputStream()      // 1. Client CREATES stream       │
│       output = stream                                                       │
│       Task {                                                                │
│           try await cdkService.deploy(    // 2. Client PASSES stream        │
│               options: ...,                                                 │
│               output: stream                                                │
│           )                                                                 │
│           await stream.finishAll()        // 4. Client FINISHES stream      │
│       }                                                                     │
│   }                                                                         │
│                                                                             │
│   .task(id: output != nil) {              // 3. Client CONSUMES stream      │
│       guard let output else { return }                                      │
│       for await item in await output.makeStream() {                         │
│           outputLines.append(item)                                          │
│       }                                                                     │
│   }                                                                         │
└─────────────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ Observable Service (e.g., CDKInfrastructureService)                         │
│                                                                             │
│   // NO operationOutput property - services don't own streams               │
│                                                                             │
│   func deploy(options: ..., output: CLIOutputStream? = nil) async throws {  │
│       try await cdkService.build(output: output)    // Thread through       │
│       try await cdkService.deploy(output: output)   // Thread through       │
│   }                                                                         │
└─────────────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ Typed Service Wrapper (e.g., CDKService)                                    │
│                                                                             │
│   func deploy(options: ..., output: CLIOutputStream? = nil) async throws {  │
│       for await _ in cliService.stream(                                     │
│           Cdk.Deploy(...),                                                  │
│           output: output                            // Thread through       │
│       ) { }                                                                 │
│   }                                                                         │
└─────────────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ CLIService                                                                  │
│                                                                             │
│   func execute(..., output: CLIOutputStream? = nil) {                       │
│       // In runProcess:                                                     │
│       await globalOutput.send(item)       // Always (existing behavior)     │
│       await output?.send(item)            // Client's stream (if provided)  │
│   }                                                                         │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Key Design Principle

**Services are stateless with respect to output.** They:
- Accept an optional `output` parameter
- Forward output to that stream (if provided)
- Don't create, own, or manage streams

**Clients own the full lifecycle:**
1. Create the `CLIOutputStream`
2. Start consuming (subscribe via `makeStream()`)
3. Call service methods, passing the stream
4. Finish the stream when done

## Implementation

### Layer 1: CLIService Changes

Add `output` parameter to execution methods:

```swift
// CLIService.swift

public func execute(
    command: String,
    arguments: [String] = [],
    workingDirectory: String? = nil,
    environment: [String: String]? = nil,
    timeout: TimeInterval? = nil,
    printCommand: Bool = true,
    inheritIO: Bool = false,
    output: CLIOutputStream? = nil  // NEW
) async throws -> ExecutionResult

public func stream(
    command: String,
    arguments: [String] = [],
    workingDirectory: String? = nil,
    environment: [String: String]? = nil,
    printCommand: Bool = true,
    output: CLIOutputStream? = nil  // NEW
) -> AsyncStream<StreamOutput>

public func executeForResult<C: CLICommand>(
    _ command: C,
    workingDirectory: String? = nil,
    environment: [String: String]? = nil,
    printCommand: Bool = true,
    inheritIO: Bool = false,
    output: CLIOutputStream? = nil  // NEW
) async throws -> ExecutionResult
```

Modify `runProcess` to send to both streams:

```swift
private func runProcess(
    command: String,
    arguments: [String],
    workingDirectory: String?,
    environment: [String: String],
    timeout: TimeInterval?,
    inheritIO: Bool,
    commandID: CommandID,
    commandContinuation: AsyncStream<StreamOutput>.Continuation?,
    output: CLIOutputStream?  // NEW
) throws -> ExecutionResult {
    // ... existing code ...

    outPipe.fileHandleForReading.readabilityHandler = { handle in
        let data = handle.availableData
        if !data.isEmpty, let text = String(data: data, encoding: .utf8) {
            // ... existing accumulator code ...

            let streamOutput = StreamOutput.stdout(commandID: commandID, text: text)

            // Yield to per-command stream (existing)
            commandContinuation?.yield(streamOutput)

            // Broadcast to global stream (existing)
            Task {
                await self.globalOutput.send(streamOutput)
            }

            // Send to client's stream (NEW)
            if let clientOutput = output {
                Task {
                    await clientOutput.send(streamOutput)
                }
            }
        }
    }
    // ... same pattern for stderr, exit, error ...
}
```

### Layer 2: Typed Service Wrappers

Thread the parameter through intermediate services:

```swift
// GitService.swift
public func push(output: CLIOutputStream? = nil) async throws {
    try await cliService.executeForResult(
        Git.Push(upstream: true, remote: "origin", branch: currentBranch),
        output: output
    )
}

// GitHubCLIService.swift
public func triggerWorkflow(
    workflow: String,
    branch: String,
    output: CLIOutputStream? = nil
) async throws {
    try await cliService.executeForResult(
        Gh.WorkflowRun(workflow: workflow, ref: branch),
        output: output
    )
}

// CDKService.swift
public func deploy(
    options: DeployOptions,
    output: CLIOutputStream? = nil
) async throws {
    for await _ in cliService.stream(
        Cdk.Deploy(...),
        output: output
    ) { }
}
```

### Layer 3: Observable Services

Observable services simply thread the parameter through - they don't own streams:

```swift
// GitHubService.swift
@MainActor
@Observable
public final class GitHubService {
    // Existing state
    public private(set) var ciStatus = GitHubCIStatus()

    // NO operationOutput property - client owns the stream

    public func pushAndDeploy(output: CLIOutputStream? = nil) async throws {
        // Thread the client's stream through all child calls
        try await gitService.push(output: output)
        try await ghCLIService.triggerWorkflow(
            workflow: "Dev Deploy",
            branch: config.branch,
            output: output
        )
        // ... rest of implementation
    }
}
```

```swift
// CDKInfrastructureService.swift
@MainActor
@Observable
public final class CDKInfrastructureService {
    // Existing state
    public private(set) var status: CDKStatus = .unknown

    // NO operationOutput property - client owns the stream

    public func deploy(options: DeployOptions, output: CLIOutputStream? = nil) async throws {
        try await cdkService.build(output: output)
        try await cdkService.deploy(options: ..., output: output)
    }
}
```

### Layer 4: SwiftUI Consumption (Client)

The view (client) creates, passes, and consumes the stream:

```swift
struct CDKInfrastructureSectionView: View {
    @Bindable var service: CDKInfrastructureService

    // Client owns the stream
    @State private var operationOutput: CLIOutputStream?
    @State private var outputLines: [StreamOutput] = []

    var body: some View {
        VStack {
            // ... existing UI ...

            Button("Deploy") {
                // 1. Client CREATES stream
                let stream = CLIOutputStream()
                operationOutput = stream
                outputLines = []

                Task {
                    defer {
                        // 4. Client FINISHES stream
                        Task { await stream.finishAll() }
                        operationOutput = nil
                    }

                    // 2. Client PASSES stream to service
                    try await service.deploy(
                        options: .minimal,
                        output: stream
                    )
                }
            }

            // Operation-specific output
            if !outputLines.isEmpty {
                StreamingTextView(lines: outputLines.compactMap { $0.text })
            }
        }
        // 3. Client CONSUMES stream
        .task(id: operationOutput != nil) {
            guard let output = operationOutput else { return }
            for await item in await output.makeStream() {
                outputLines.append(item)
            }
        }
    }
}
```

Alternative: Pass stream directly to StreamingTextView:

```swift
struct CDKInfrastructureSectionView: View {
    @Bindable var service: CDKInfrastructureService
    @State private var operationOutput: CLIOutputStream?

    var body: some View {
        VStack {
            Button("Deploy") {
                let stream = CLIOutputStream()
                operationOutput = stream

                Task {
                    defer {
                        Task { await stream.finishAll() }
                        operationOutput = nil
                    }
                    try await service.deploy(options: .minimal, output: stream)
                }
            }

            // StreamingTextView subscribes directly
            if let output = operationOutput {
                StreamingTextView(
                    streamProvider: { await output.makeStream() }
                )
            }
        }
    }
}
```

## API Changes Summary

| Layer | File | Change |
|-------|------|--------|
| CLIService | `CLIService.swift` | Add `output` parameter to `execute()`, `stream()`, `executeForResult()`, `runProcess()` |
| Git | `GitService.swift` | Add `output` to `push()`, `commit()`, etc. |
| GitHub CLI | `GitHubCLIService.swift` | Add `output` to `triggerWorkflow()`, `watchWorkflow()`, etc. |
| CDK | `CDKService.swift` | Add `output` to `build()`, `deploy()`, `destroy()` |
| AWS CLI | `AWSCLIService.swift` | Add `output` to methods that produce output |
| GitHubService | `GitHubService.swift` | Add `output` parameter to `pushAndDeploy()` (no property) |
| CDKInfrastructureService | `CDKInfrastructureService.swift` | Add `output` parameter to `deploy()`, `destroy()` (no property) |
| Views | Various | Client creates stream, passes to service, consumes via `.task(id:)` |

## Backward Compatibility

- All new parameters have default value `nil`
- Existing code continues to work without changes
- Global output stream remains functional
- CLI commands continue to output to console

## Benefits

1. **Operation isolation**: Each operation's output is clearly separated
2. **Concurrent operations**: Multiple operations can run without output mixing
3. **Flexible UI**: Views can show global output, operation output, or both
4. **Familiar pattern**: Uses existing `CLIOutputStream` type and `.makeStream()` API
5. **Services stay stateless**: No output-related state in services
6. **Client control**: Client has full control over stream lifecycle
7. **Reusable services**: Same service can be called by different clients with different streams

## Drawbacks

1. **Parameter threading**: Must pass `output` through all layers
2. **API verbosity**: Every method in the chain needs the new parameter
3. **Client responsibility**: Client must manage stream lifecycle (create, consume, finish)
4. **Timing coordination**: Client must start consuming before/as operation starts

## Alternatives Considered

### Service-Owned Streams

Services create and expose an `operationOutput` property:

```swift
@Observable
public final class GitHubService {
    public private(set) var operationOutput: CLIOutputStream?

    public func pushAndDeploy() async throws {
        let output = CLIOutputStream()
        operationOutput = output
        defer { operationOutput = nil }
        // ...
    }
}
```

**Rejected because**: Services become stateful with respect to output. Harder to reuse - what if two different views want to call the same service with different output handling? Client-owned is more flexible.

### Task-Local Storage

Instead of threading parameters, use Swift's task-local values:

```swift
enum OperationContext {
    @TaskLocal static var output: CLIOutputStream?
}

// CLIService checks task-local
await OperationContext.output?.send(output)

// Operation sets task-local
try await OperationContext.$output.withValue(output) {
    try await gitService.push()  // No parameter needed
}
```

**Rejected because**: Implicit behavior is harder to trace and test. Task-local propagation rules can be surprising.

### Return AsyncSequence from Operations

Operations return a stream that yields output:

```swift
func pushAndDeploy() -> AsyncStream<OperationEvent>
```

**Rejected because**: Changes return types significantly, awkward for void operations, harder to integrate with `@Observable` state.

### CommandID Filtering

Filter global stream by operation's command IDs:

```swift
let scope = OperationScope()
try await service.pushAndDeploy(scope: scope)
// Filter: globalStream.filter { scope.contains($0.commandID) }
```

**Rejected because**: Still subscribes to global stream, client must filter manually, more complex implementation.

## Testing

1. Unit test: CLIService sends to both global and operation streams
2. Unit test: Operation stream receives only commands from that operation
3. Integration test: Concurrent operations have isolated output
4. UI test: Section views show only their operation's output

## Implementation Phases

### Phase 1: CLIService Foundation ✅ COMPLETE

Add `output` parameter to CLIService without changing any existing services.

- [x] Add `output: CLIOutputStream? = nil` parameter to `CLIService.execute()`
- [x] Add `output: CLIOutputStream? = nil` parameter to `CLIService.stream()`
- [x] Add `output: CLIOutputStream? = nil` parameter to `CLIService.executeForResult()`
- [x] Update `runProcess()` to send to client stream when provided
- [x] Add unit tests for dual-stream output

**Result**: CLIService supports client-owned streams. All existing code continues to work unchanged.

---

### Phase 2: Test Service & View ✅ COMPLETE

Create a dedicated test service and view to verify the architecture before migrating real services.

- [x] Create `TestCLIService` in SwiftDeploy that makes several CLI calls (e.g., `echo`, `sleep`, `ls`)
- [x] Create `TestOutputStreamView` in MacApp that:
  - Creates a `CLIOutputStream`
  - Passes it to `TestCLIService` methods
  - Displays operation-specific output
  - Has a "Run Test" button to trigger the operation
- [x] Verify output isolation works correctly
- [x] Verify global stream still receives all output
- [x] Verify stream lifecycle (create, consume, finish) works correctly

**Result**: Working proof-of-concept that validates the architecture.

**Files Created**:
- `Sources/SwiftDeploy/Services/TestCLIService.swift` - Test service with multi-step operations
- `Sources/MacApp/OutputView/TestOutputStreamView.swift` - Test view demonstrating client-owned streams

**Access**: Navigate to Debug > Output Streams in the app sidebar

---

### Phase 3: Migrate GitService ✅ COMPLETE

- [x] Add `output` parameter to `GitService.push()`
- [x] Add `output` parameter to `GitService.commit()` - N/A (method does not exist)
- [x] Add `output` parameter to other GitService methods as needed - N/A (other methods use `printCommand: false` for internal queries)
- [x] Update any views that use GitService directly (if applicable) - N/A (no views use GitService directly)

**Result**: GitService.push() now supports client-owned output streams. Other GitService methods are internal queries that don't need user-visible output.

---

### Phase 4: Migrate GitHubCLIService ✅ COMPLETE

- [x] Add `output` parameter to `GitHubCLIService.triggerWorkflow()`
- [x] Add `output` parameter to `GitHubCLIService.watchWorkflowRun()`
- [x] Add `output` parameter to `GitHubCLIService.watchWorkflowRunStreaming()`

**Result**: GitHubCLIService methods that produce user-visible output now support client-owned output streams. Other methods like `listWorkflowRuns()` and `getRunDetail()` are internal queries with `printCommand: false` and don't need the output parameter.

---

### Phase 5: Migrate GitHubService ✅ COMPLETE

- [x] Add `output` parameter to `GitHubService.pushAndDeploy()`
- [x] Thread `output` to child service calls (GitService, GitHubCLIService)
- [x] Update `GitHubCISectionView` to use operation-scoped output

**Result**: GitHubService.pushAndDeploy() now threads the client-owned output stream to git push and workflow trigger operations. GitHubCISectionView creates and manages the stream, displaying operation-specific CLI output below the action buttons.

---

### Phase 6: Migrate CDKService ✅ COMPLETE

- [x] Add `output` parameter to `CDKService.build()`
- [x] Add `output` parameter to `CDKService.deploy()`
- [x] Add `output` parameter to `CDKService.destroy()`
- [x] Add `output` parameter to `CDKService.install()` (called by `build()`)

**Result**: CDKService methods now support client-owned output streams. The `install()` method was also updated since `build()` calls it when node_modules is missing.

---

### Phase 7: Migrate CDKInfrastructureService ✅ COMPLETE

- [x] Add `output` parameter to `CDKInfrastructureService.deploy()`
- [x] Add `output` parameter to `CDKInfrastructureService.updateInfrastructure()`
- [x] Add `output` parameter to `CDKInfrastructureService.destroy()`
- [x] Thread `output` to child service calls (CDKService)
- [x] Update `CDKInfrastructureSectionView` to use operation-scoped output

**Result**: CDKInfrastructureService methods now support client-owned output streams. CDKInfrastructureSectionView creates and manages the stream using a `startOperation` helper function, displaying operation-specific CLI output below the action buttons during deploy/update/destroy operations.

---

### Phase 8: Migrate Remaining Services

- [ ] Add `output` parameter to `AWSCLIService` methods
- [ ] Add `output` parameter to `DockerService` methods
- [ ] Add `output` parameter to `LambdaBuildService` methods
- [ ] Add `output` parameter to local service methods (XcodeLocalService, LinuxLocalService)

---

### Phase 9: Cleanup

- [ ] Remove `UnifiedOutputState` if no longer needed
- [ ] Update documentation
- [ ] Remove test service/view (or keep for regression testing)

## Open Questions

1. Should we keep the global output panel in the UI, or replace it entirely with operation-specific views?
2. Should the client always call `finishAll()`, or should the stream auto-finish somehow?
3. How should errors be surfaced - via the stream, via thrown exceptions, or both?
4. Should we provide a helper/wrapper to reduce boilerplate in views for the create-consume-finish pattern?
