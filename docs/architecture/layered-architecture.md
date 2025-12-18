# Layered Architecture

This document defines the layered architecture for organizing Swift targets across the project.

## Overview

The project uses a four-layer architecture where dependencies flow downward:

```
┌─────────────────────────────────────────────────────────────┐
│                           APPS                               │
│           LambdaApp  ·  MacApp  ·  CLIApp                    │
│   Entry points, I/O, @Observable models (where needed)       │
└──────────────────────────┬──────────────────────────────────┘
                           │ uses
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                         FEATURES                             │
│   DeployRemoteFeature · SetupFeature · DeployXcodeFeature    │
│   Multi-step orchestration returning AsyncThrowingStream     │
│   Features combine workflow + service code in one target     │
└──────────────────────────┬──────────────────────────────────┘
                           │ uses
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                         SERVICES                             │
│  DeployCoreService · DeployLocalService · ClientService      │
│   Models, configuration, auth, stateful utilities            │
└──────────────────────────┬──────────────────────────────────┘
                           │ uses
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                           SDKS                               │
│       AWSSDK  ·  GitHubSDK  ·  CLISDK  ·  DockerCLISDK       │
│   Reusable utilities, not app-specific                       │
│   Stateless clients and utilities                            │
└─────────────────────────────────────────────────────────────┘
```

## Layer Definitions

### Apps (`Sources/apps/`)

Entry points that handle I/O.

| Target | Description |
|--------|-------------|
| `LambdaApp` | AWS Lambda handler entry point |
| `MacApp` | macOS SwiftUI application |
| `CLIApp` | Command-line interface tool |

- Executable targets (apps, CLI tools, Lambda handlers)
- Platform-specific I/O (SwiftUI views, terminal output, Lambda encoding)
- `@Observable` models live here when needed (e.g., MacApp for SwiftUI)
- CLI commands are parallel to Mac models—both are app-layer constructs
- Minimal business logic; focus on I/O and calling features

### Features (`Sources/features/`)

Multi-step orchestration operations. Features combine workflow logic and feature-specific service code in one target.

| Target | Description |
|--------|-------------|
| `DeployRemoteFeature` | AWS deployment workflows |
| `SetupFeature` | Setup and dependency workflows |
| `DeployXcodeFeature` | Xcode local development workflows |
| `DeployLinuxFeature` | Linux container development workflows |

- Workflows are structs conforming to `Workflow` or `StreamingWorkflow` protocols (from `Uniflow`)
- Coordinate multiple SDK clients and services
- App-specific business logic and orchestration
- **Not** `@Observable`—that belongs in the app layer
- Depend on services and SDKs, but never vice versa

### Services (`Sources/services/`)

Models, configuration, and stateful utilities shared across features.

| Target | Description |
|--------|-------------|
| `DeployCoreService` | Core deployment utilities and types |
| `DeployLocalService` | Local development shared configuration |
| `ClientService` | HTTP client utilities |
| `StorageService` | Local file storage service |
| `LambdaBuildService` | Lambda build utilities |

- App-specific models and types
- Configuration persistence (AWS auth, GitHub config)
- Stateful utilities that don't orchestrate multi-step operations
- Provide types and utilities used by features

### SDKs (`Sources/sdks/`)

Stateless reusable utilities.

| Target | Description |
|--------|-------------|
| `AWSSDK` | AWS SDKs (CDK, CloudFormation, Lambda, S3) |
| `GitHubSDK` | GitHub SDKs (Actions, Git) |
| `CLISDK` | CLI utilities (process execution, streams) |
| `CLIMacrosSDK` | Swift macros for CLI |
| `DockerCLISDK` | Docker CLI utilities |
| `BrewCLISDK` | Homebrew CLI utilities |
| `NodeCLISDK` | Node.js CLI utilities |
| `PostgreSQLSDK` | PostgreSQL database utilities |
| `MinioSDK` | MinIO S3-compatible storage |
| `DynamoDBSDK` | DynamoDB utilities |
| `Uniflow` | Workflow protocol definitions |

- Wrap external tools and services
- **Stateless**—no internal state management
- Operations return `AsyncThrowingStream` for progress or values for one-shot queries
- Can be extracted to separate packages
- **Use `Sendable` structs** for clients, not actors or classes—no mutable state means no need for isolation

## Source Code Structure

Targets are organized by architectural layer in folders:

```
Sources/
├── apps/                     # Entry points
│   ├── CLIApp/               # CLI tool (deployment commands)
│   ├── LambdaApp/            # AWS Lambda handler (entry point)
│   └── MacApp/               # Mac app (SwiftUI views, @Observable models)
├── features/                 # Feature modules (workflow + service combined)
│   ├── DeployRemoteFeature/  # AWS deployment feature
│   │   ├── workflows/        # DeployWorkflow, DestroyWorkflow, etc.
│   │   └── services/         # Models, auth config, GitHub config
│   ├── DeployXcodeFeature/  # Xcode local development workflows
│   ├── DeployLinuxFeature/  # Linux container development workflows
│   └── SetupFeature/         # Setup and dependency workflows
├── services/                 # Shared service modules
│   ├── DeployCoreService/    # Core deployment utilities
│   ├── DeployLocalService/   # Local development services
│   ├── ClientService/        # HTTP client utilities
│   ├── StorageService/       # Local file storage service
│   └── LambdaBuildService/   # Lambda build utilities
└── sdks/                     # Low-level SDK modules
    ├── AWSSDK/               # AWS SDKs (CDK, CloudFormation, Lambda, S3)
    ├── CLISDK/               # CLI utilities (process execution, streams)
    ├── CLIMacrosSDK/         # Swift macros for CLI
    ├── DockerCLISDK/         # Docker CLI utilities
    ├── GitHubSDK/            # GitHub SDKs (Actions, Git)
    ├── MinioSDK/             # MinIO S3-compatible storage
    ├── PostgreSQLSDK/        # PostgreSQL database utilities
    └── ...                   # Other SDKs (BrewCLISDK, NodeCLISDK, DynamoDBSDK)
```

## Target Naming

Targets use PascalCase names organized by folder:

```
<Name><Layer>
```

The folder structure provides architectural hierarchy:

| Folder | Layer | Position |
|--------|-------|----------|
| `apps/` | App | Top (entry points) |
| `features/` | Feature | Second |
| `services/` | Service | Third |
| `sdks/` | SDK | Bottom (reusable) |

**Examples:**

| Target | Folder | Layer | Description |
|--------|--------|-------|-------------|
| `LambdaApp` | apps | App | Lambda entry point |
| `MacApp` | apps | App | macOS application |
| `CLIApp` | apps | App | CLI tool |
| `DeployRemoteFeature` | features | Feature | AWS deployment |
| `DeployXcodeFeature` | features | Feature | Xcode local dev |
| `SetupFeature` | features | Feature | Setup workflows |
| `DeployCoreService` | services | Service | Core deployment |
| `StorageService` | services | Service | Local storage |
| `AWSSDK` | sdks | SDK | AWS utilities |
| `CLISDK` | sdks | SDK | CLI utilities |
| `DockerCLISDK` | sdks | SDK | Docker utilities |

**Benefits:**

1. **Architectural grouping**: `ls Sources/` shows the four layers clearly
   ```
   apps/
   features/
   services/
   sdks/
   ```

2. **Layer visibility**: The folder immediately identifies which architectural layer a target belongs to

3. **Discoverability**: Finding all SDK targets is easy—look in `sdks/`

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

### Workflow Protocols (Uniflow)

The `Uniflow` SDK defines two protocols for workflow execution:

**`Workflow`** — Base protocol with a single `run(options:)` method:

```swift
public protocol Workflow: Sendable {
    associatedtype Options: Sendable = Void
    associatedtype Result: Sendable

    func run(options: Options) async throws -> Result
}
```

**`StreamingWorkflow`** — Extends `Workflow` with streaming state updates:

```swift
public protocol StreamingWorkflow: Workflow {
    associatedtype State: Sendable

    func stream(options: Options) -> AsyncThrowingStream<State, Error>
}
```

When `Result == State`, `StreamingWorkflow` provides a default `run()` implementation that consumes the stream and returns the last state.

**When to use each:**

| Protocol | Use When | Example |
|----------|----------|---------|
| `Workflow` | Single result, no intermediate progress | Status checks, configuration loading |
| `StreamingWorkflow` | Multi-step with progress updates | Deployments, builds, installations |

Most workflows in this codebase conform to `StreamingWorkflow` since they perform multi-step operations.

### Features for Orchestration

Multi-step operations live in features as `StreamingWorkflow` conformers.

```swift
import Uniflow

public struct DeployWorkflow: StreamingWorkflow {
    public typealias State = WorkflowState
    public typealias Result = State

    public struct Options: Sendable {
        public let infrastructure: InfrastructureShape
        public let requireApproval: Bool
    }

    public func stream(options: Options) -> AsyncThrowingStream<State, Error> {
        AsyncThrowingStream { continuation in
            Task {
                continuation.yield(.deploying(.starting))
                for try await cdkState in cdkClient.deployStream(options: opts) {
                    continuation.yield(.deploying(.cdkProgress(cdkState)))
                }
                continuation.yield(.completed(snapshot))
                continuation.finish()
            }
        }
    }
}
```

### @Observable Only in App Layer

`@Observable` models exist only where UI binding is needed (MacApp). They consume workflow streams.

### Minimal Logic in Models (MV Pattern)

Models should contain minimal logic—their role is to monitor workflow streams and update state for the UI. Business logic belongs in:

- **Features (Workflows)**: Orchestration, multi-step operations, app-specific logic
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

CLI commands use workflows directly without the `@Observable` wrapper. Use `stream()` for progress output, or `run()` for fire-and-forget:

```swift
struct DeployCommand: AsyncParsableCommand {
    func run() async throws {
        // Use stream() when you want progress output
        for try await state in workflow.stream(options: opts) {
            printProgress(state)
        }
    }
}

struct QuickCheckCommand: AsyncParsableCommand {
    func run() async throws {
        // Use run() when you only care about the final result
        let result = try await workflow.run(options: opts)
        print(result)
    }
}
```

## Data Flow

**CLI**: `workflow.stream() → print progress` or `workflow.run() → print result`

**Mac App**: `workflow.stream() → @Observable model → View`

## Dependency Rules

1. **Apps** depend on Features, Services, and SDKs
2. **Features** depend on Services and SDKs
3. **Services** depend on other Services and SDKs
4. **SDKs** depend only on other SDKs or external packages
5. Never depend upward

## When to Create a New Target

**SDK**: Reusable, no app-specific logic, wraps external tool/service

**Feature**: Multi-step orchestration, coordinates SDKs and services, returns `AsyncThrowingStream`

**Service**: Models, configuration, stateful utilities that don't orchestrate

**App**: Entry point, UI, platform-specific I/O
