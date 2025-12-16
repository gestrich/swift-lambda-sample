# Layered Architecture

This document defines the layered architecture for organizing Swift targets across the project.

## Overview

The project uses a three-layer architecture where dependencies flow downward:

```
┌─────────────────────────────────────────────────────────────┐
│                          APP                                 │
│          app-lambda  ·  app-mac  ·  app-cli                  │
│                                                              │
│   Entry points, I/O, @Observable models (where needed)       │
└────────────────────────┬────────────────────────────────────┘
                         │ uses
                         ▼
┌─────────────────────────────────────────────────────────────┐
│                       SERVICE                                │
│              service-deploy  ·  service-storage              │
│                                                              │
│   Workflows returning AsyncThrowingStream                    │
└────────────────────────┬────────────────────────────────────┘
                         │ uses
                         ▼
┌─────────────────────────────────────────────────────────────┐
│                         SDK                                  │
│        sdk-aws  ·  sdk-github  ·  sdk-cli  ·  sdk-client     │
│                                                              │
│   Stateless clients and utilities                            │
└─────────────────────────────────────────────────────────────┘
```

## Layer Definitions

### Apps (`app-*`)

Entry points that handle I/O.

- Executable targets (apps, CLI tools, Lambda handlers)
- Platform-specific I/O (SwiftUI views, terminal output, Lambda encoding)
- `@Observable` models live here when needed (e.g., app-mac for SwiftUI)
- CLI commands are parallel to Mac models—both are app-layer constructs
- Minimal business logic; focus on I/O and calling workflows

### Services (`service-*`)

Workflows that orchestrate multi-step operations.

- Workflows are structs returning `AsyncThrowingStream<Progress, Error>`
- Coordinate multiple SDK clients
- App-specific business logic
- **Not** `@Observable`—that belongs in the app layer

### SDKs (`sdk-*`)

Stateless reusable utilities.

- Wrap external tools and services
- **Stateless**—no internal state management
- Operations return `AsyncThrowingStream` for progress or values for one-shot queries
- Can be extracted to separate packages

## Key Principles

### Stateless SDKs

SDK clients don't maintain internal state. Each method call is independent.

```swift
public actor CDKClient {
    // Returns stream—no internal state tracking
    public nonisolated func deployStream(options: DeployOptions) -> AsyncThrowingStream<CDKProgress, Error>

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

1. **Apps** depend on Services and SDKs
2. **Services** depend on other Services and SDKs
3. **SDKs** depend only on other SDKs or external packages
4. Never depend upward

## When to Create a New Target

**SDK**: Reusable, no app-specific logic, wraps external tool/service

**Service**: Orchestrates multiple SDKs, app-specific workflow

**App**: Entry point, UI, platform-specific I/O
