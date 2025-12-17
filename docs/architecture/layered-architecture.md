# Layered Architecture

This document defines the layered architecture for organizing Swift targets across the project.

## Overview

The project uses a four-layer architecture where dependencies flow downward:

```
┌─────────────────────────────────────────────────────────────┐
│                          APP (a-)                            │
│       a-app-lambda  ·  a-app-mac  ·  a-app-cli               │
│                                                              │
│   Entry points, I/O, @Observable models (where needed)       │
└────────────────────────┬────────────────────────────────────┘
                         │ uses
                         ▼
┌─────────────────────────────────────────────────────────────┐
│                       WORKFLOW (b-)                          │
│     b-workflow-deploy-remote  ·  b-workflow-setup            │
│                                                              │
│   Multi-step orchestration returning AsyncThrowingStream     │
└────────────────────────┬────────────────────────────────────┘
                         │ uses
                         ▼
┌─────────────────────────────────────────────────────────────┐
│                       SERVICE (c-)                           │
│  c-service-deploy-remote · c-service-deploy-local · c-service-storage │
│                                                              │
│   Models, configuration, auth, stateful utilities            │
└────────────────────────┬────────────────────────────────────┘
                         │ uses
                         ▼
┌─────────────────────────────────────────────────────────────┐
│                         SDK (d-)                             │
│    d-sdk-aws  ·  d-sdk-github  ·  d-sdk-cli  ·  d-sdk-client │
│                                                              │
│   Stateless clients and utilities                            │
└─────────────────────────────────────────────────────────────┘
```

## Layer Definitions

### Apps (`a-app-*`)

Entry points that handle I/O.

- Executable targets (apps, CLI tools, Lambda handlers)
- Platform-specific I/O (SwiftUI views, terminal output, Lambda encoding)
- `@Observable` models live here when needed (e.g., app-mac for SwiftUI)
- CLI commands are parallel to Mac models—both are app-layer constructs
- Minimal business logic; focus on I/O and calling workflows

### Workflows (`b-workflow-*`)

Multi-step orchestration operations.

- Workflows are structs returning `AsyncThrowingStream<Progress, Error>`
- Coordinate multiple SDK clients and services
- App-specific business logic and orchestration
- **Not** `@Observable`—that belongs in the app layer
- Depend on services and SDKs, but never vice versa

### Services (`c-service-*`)

Models, configuration, and stateful utilities.

- App-specific models and types
- Configuration persistence (AWS auth, GitHub config)
- Stateful utilities that don't orchestrate multi-step operations
- Provide types and utilities used by workflows

### SDKs (`d-sdk-*`)

Stateless reusable utilities.

- Wrap external tools and services
- **Stateless**—no internal state management
- Operations return `AsyncThrowingStream` for progress or values for one-shot queries
- Can be extracted to separate packages
- **Use `Sendable` structs** for clients, not actors or classes—no mutable state means no need for isolation

## Target Naming

Targets use a letter prefix (`a-`, `b-`, `c-`, `d-`) followed by layer and specificity:

```
<letter>-<layer>-<area>[-<specific>]
```

The letter prefix ensures alphabetical sorting matches the architectural hierarchy (top to bottom):

| Prefix | Layer | Position |
|--------|-------|----------|
| `a-` | App | Top (entry points) |
| `b-` | Workflow | Second |
| `c-` | Service | Third |
| `d-` | SDK | Bottom (reusable) |

**Examples:**

| Target | Letter | Layer | Area | Specific |
|--------|--------|-------|------|----------|
| `d-sdk-cli` | d | sdk | cli | - |
| `d-sdk-cli-docker` | d | sdk | cli | docker |
| `d-sdk-cli-macros` | d | sdk | cli | macros |
| `d-sdk-aws` | d | sdk | aws | - |
| `d-sdk-github` | d | sdk | github | - |
| `c-service-deploy-remote` | c | service | deploy | remote |
| `c-service-deploy-local` | c | service | deploy | local |
| `c-service-storage` | c | service | storage | - |
| `b-workflow-deploy-remote` | b | workflow | deploy | remote |
| `b-workflow-setup` | b | workflow | setup | - |
| `a-app-mac` | a | app | mac | - |
| `a-app-cli` | a | app | cli | - |
| `a-app-lambda` | a | app | lambda | - |

**Benefits:**

1. **Architectural sorting**: `ls Sources/` shows targets in dependency order (top to bottom)
   ```
   a-app-cli
   a-app-lambda
   a-app-mac
   b-workflow-deploy-remote
   b-workflow-setup
   c-service-deploy-local
   c-service-deploy-remote
   c-service-storage
   d-sdk-aws
   d-sdk-cli
   d-sdk-cli-docker
   d-sdk-cli-macros
   d-sdk-github
   ```

2. **Layer visibility**: The prefix immediately identifies which architectural layer a target belongs to

3. **Discoverability**: Finding all CLI-related SDKs is easy—look for `d-sdk-cli-*`

## Key Principles

### Stateless SDKs

SDK clients don't maintain internal state. Each method call is independent. Use `Sendable` structs—no mutable state means no need for actor isolation.

```swift
public struct CDKClient: Sendable {
    private let cliClient: CLIClient

    // Returns stream—no internal state tracking
    public func deployStream(options: DeployOptions) -> AsyncThrowingStream<CDKProgress, Error>

    // Returns value directly
    public func getStackOutputs(stackName: String) async throws -> [String: String]
}
```

### Workflows for Orchestration

Multi-step operations live in workflows that yield progress via streams.

```swift
public struct DeployWorkflow {
    public func run(options: Options) -> AsyncThrowingStream<Progress, Error> {
        AsyncThrowingStream { continuation in
            Task {
                // Coordinate SDK clients, yield progress
                for try await cdkProgress in cdkClient.deployStream(options: opts) {
                    continuation.yield(...)
                }
                continuation.finish()
            }
        }
    }
}
```

### @Observable Only in App Layer

`@Observable` models exist only where UI binding is needed (app-mac). They consume workflow streams.

### Minimal Logic in Models (MV Pattern)

Models should contain minimal logic—their role is to monitor workflow streams and update state for the UI. Business logic belongs in:

- **Services (Workflows)**: Orchestration, multi-step operations, app-specific logic
- **SDKs (Clients)**: Reusable operations, external service interactions

This keeps models thin and testable, with clear separation between state management and business logic.

#### Model → Workflow State Flow

When consuming workflow streams, models should do the minimum work necessary: receive state from the workflow and assign it directly to a state enum. Avoid excessive translations, mapping, or reconstruction of state in the model layer.

**Preferred pattern:**
```swift
@MainActor @Observable
class DeploymentModel {
    var state: ModelState = .uninitialized

    func deploy() {
        let prior = state.snapshot
        Task {
            for try await workflowState in workflow.run(options: opts) {
                // Direct assignment—no transformation
                state = ModelState(from: workflowState, prior: prior)
            }
        }
    }
}
```

**Avoid this pattern:**
```swift
// Don't manually reconstruct state from workflow progress
for try await progress in workflow.run(options: opts) {
    // Excessive mapping and transformation
    let outputs = progress.detail?.outputs ?? prior?.outputs
    let infrastructure = progress.detail?.infrastructure ?? prior?.infrastructure
    let deployedStack = DeployedStack(
        outputs: outputs?.allOutputs ?? [:],
        infrastructure: infrastructure?.detected ?? DetectedInfrastructure()
    )
    state = .operating(RunningWorkflow(
        kind: .deploying(progress),
        startTime: startTime,
        prior: prior
    ))
    if progress.step == .complete {
        state = .ready(Snapshot(status: .deployed(deployedStack), ...))
    }
}
```

The workflow should yield state that the model can use directly. If the model needs to do complex mapping, that's a signal the workflow should be returning better-structured state.

#### State Ownership

**Workflows own state data; models own state transitions.**

- Workflows define and return snapshot types (e.g., `DeploymentSnapshot`, `GitHubCISnapshot`)
- Models define their enum cases for app-layer concerns (`uninitialized`, `loading`, `operating`, `ready`)
- Associated values in model state should come directly from workflow types

```swift
// Model defines enum cases (app-layer concerns)
enum ModelState {
    case uninitialized
    case loading(prior: WorkflowSnapshot?)
    case ready(WorkflowSnapshot)           // ← Associated value from workflow
    case operating(WorkflowState, prior: WorkflowSnapshot?)  // ← From workflow
}
```

**Code smell**: Switching on workflow state to create model state with similar cases.

```swift
// ❌ Bad: Redundant transformation
for try await workflowState in workflow.run() {
    switch workflowState {
    case .deploying(let progress):
        state = .operating(step: progress.step, startTime: progress.startTime)
    case .completed(let runId):
        state = .ready(status: .success(runId: runId))
    case .failed(let runId, let reason):
        state = .ready(status: .failed(runId: runId, reason: reason))
    }
}

// ✅ Good: Direct assignment via init
for try await workflowState in workflow.run() {
    state = ModelState(from: workflowState, prior: prior)
}
```

The `ModelState.init(from:prior:)` should be trivial—typically just checking if the workflow completed:

```swift
init(from workflowState: WorkflowState, prior: Snapshot?) {
    if let snapshot = workflowState.completedSnapshot {
        self = .ready(snapshot)
    } else {
        self = .operating(workflowState, prior: prior)
    }
}
```

#### Enum-Based State in Models

Use enums to represent model state rather than multiple independent properties.

**Why enums:**

1. **Impossible invalid states**: An enum with associated values guarantees only valid combinations exist. You can't have `isLoading = true` while also having `deployedStack != nil` if the enum doesn't allow it.

2. **Exhaustive handling**: Switch statements force you to handle every case. Adding a new state is a compile-time change, not a runtime bug.

3. **Clear state transitions**: The current state is always unambiguous—one case, not a combination of booleans and optionals to interpret.

4. **Easier to reason about**: Reading `case operating(WorkflowState, prior: Snapshot?)` tells you exactly what data is available during an operation.

**Preferred:**
```swift
enum ModelState {
    case uninitialized
    case loading(prior: Snapshot?)
    case ready(Snapshot)
    case operating(WorkflowState, prior: Snapshot?)
}
```

**Avoid:**
```swift
// Multiple properties create ambiguous states
class Model {
    var isLoading = false
    var isOperating = false
    var snapshot: Snapshot?
    var workflowState: WorkflowState?
    var prior: Snapshot?
    // What if isLoading && isOperating? What if snapshot != nil && isLoading?
}
```

#### CLI Commands

CLI commands use workflows directly without the `@Observable` wrapper:

```swift
struct DeployCommand: AsyncParsableCommand {
    func run() async throws {
        for try await workflowState in workflow.run(options: opts) {
            print(workflowState)
        }
    }
}
```

## Data Flow

**CLI**: `Workflow stream → print progress`

**Mac App**: `Workflow stream → @Observable model → View`

## Dependency Rules

1. **Apps** depend on Workflows, Services, and SDKs
2. **Workflows** depend on Services and SDKs
3. **Services** depend on other Services and SDKs
4. **SDKs** depend only on other SDKs or external packages
5. Never depend upward

## When to Create a New Target

**SDK**: Reusable, no app-specific logic, wraps external tool/service

**Workflow**: Multi-step orchestration, coordinates SDKs and services, returns `AsyncThrowingStream`

**Service**: Models, configuration, stateful utilities that don't orchestrate

**App**: Entry point, UI, platform-specific I/O
