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
│                         FEATURES                            │
│   DeployRemoteFeature · SetupFeature · DeployXcodeFeature   │
│   Multi-step orchestration returning AsyncThrowingStream    │
│   Features combine use case + service code in one target    │
└──────────────────────────┬──────────────────────────────────┘
                           │ uses
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                         SERVICES                            │
│  DeployCoreService · DeployLocalService · ClientService     │
│   Models, configuration, auth, shared use case utilities    │
└──────────────────────────┬──────────────────────────────────┘
                           │ uses
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                           SDKS                              │
│       AWSSDK  ·  GitHubSDK  ·  CLISDK  ·  DockerCLISDK      │
│   Reusable utilities, not app-specific                      │
│   Stateless clients and utilities                           │
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

**Responsibilities:**

- Executable targets (apps, CLI tools, Lambda handlers)
- Platform-specific I/O (SwiftUI views, terminal output, Lambda encoding)
- `@Observable` models live here when needed (e.g., MacApp for SwiftUI)
- CLI commands are parallel to Mac models—both are app-layer constructs
- Minimal business logic; focus on I/O and calling features

#### @Observable Only in App Layer

`@Observable` models exist only where UI binding is needed (MacApp). They consume use case streams.

#### Minimal Logic in Models (MV Pattern)

Models should contain minimal logic—their role is to monitor use case streams and update state for the UI. Business logic belongs in:

- **Features (Use Cases)**: Orchestration, multi-step operations, app-specific logic
- **SDKs (Clients)**: Reusable operations, external service interactions

This keeps models thin and testable, with clear separation between state management and business logic.

#### Model → Use Case State Flow

When consuming use case streams, models should do the minimum work necessary: receive state from the use case and assign it directly to a state enum. Avoid excessive translations, mapping, or reconstruction of state in the model layer.

**Preferred pattern:**
```swift
@MainActor @Observable
class DeploymentModel {
    var state: ModelState = .uninitialized

    func deploy() {
        let prior = state.snapshot
        Task {
            for try await useCaseState in useCase.run(options: opts) {
                // Direct assignment—no transformation
                state = ModelState(from: useCaseState, prior: prior)
            }
        }
    }
}
```

**Avoid this pattern:**
```swift
// Don't manually reconstruct state from use case progress
for try await progress in useCase.run(options: opts) {
    // Excessive mapping and transformation
    let outputs = progress.detail?.outputs ?? prior?.outputs
    let infrastructure = progress.detail?.infrastructure ?? prior?.infrastructure
    let deployedStack = DeployedStack(
        outputs: outputs?.allOutputs ?? [:],
        infrastructure: infrastructure?.detected ?? DetectedInfrastructure()
    )
    state = .operating(RunningUseCase(
        kind: .deploying(progress),
        startTime: startTime,
        prior: prior
    ))
    if progress.step == .complete {
        state = .ready(Snapshot(status: .deployed(deployedStack), ...))
    }
}
```

The use case should yield state that the model can use directly. If the model needs to do complex mapping, that's a signal the use case should be returning better-structured state.

#### State Ownership

**Use cases own state data; models own state transitions.**

- Use cases define and return snapshot types (e.g., `DeploymentSnapshot`, `GitHubCISnapshot`)
- Models define their enum cases for app-layer concerns (`uninitialized`, `loading`, `operating`, `ready`)
- Associated values in model state should come directly from use case types

```swift
// Model defines enum cases (app-layer concerns)
enum ModelState {
    case uninitialized
    case loading(prior: UseCaseSnapshot?)
    case ready(UseCaseSnapshot)           // ← Associated value from use case
    case operating(UseCaseState, prior: UseCaseSnapshot?)  // ← From use case
}
```

**Code smell**: Switching on use case state to create model state with similar cases.

```swift
// ❌ Bad: Redundant transformation
for try await useCaseState in useCase.run() {
    switch useCaseState {
    case .deploying(let progress):
        state = .operating(step: progress.step, startTime: progress.startTime)
    case .completed(let runId):
        state = .ready(status: .success(runId: runId))
    case .failed(let runId, let reason):
        state = .ready(status: .failed(runId: runId, reason: reason))
    }
}

// ✅ Good: Direct assignment via init
for try await useCaseState in useCase.run() {
    state = ModelState(from: useCaseState, prior: prior)
}
```

The `ModelState.init(from:prior:)` should be trivial—typically just checking if the use case completed:

```swift
init(from useCaseState: UseCaseState, prior: Snapshot?) {
    if let snapshot = useCaseState.completedSnapshot {
        self = .ready(snapshot)
    } else {
        self = .operating(useCaseState, prior: prior)
    }
}
```

#### Enum-Based State in Models

Use enums to represent model state rather than multiple independent properties.

**Why enums:**

1. **Impossible invalid states**: An enum with associated values guarantees only valid combinations exist. You can't have `isLoading = true` while also having `deployedStack != nil` if the enum doesn't allow it.

2. **Exhaustive handling**: Switch statements force you to handle every case. Adding a new state is a compile-time change, not a runtime bug.

3. **Clear state transitions**: The current state is always unambiguous—one case, not a combination of booleans and optionals to interpret.

4. **Easier to reason about**: Reading `case operating(UseCaseState, prior: Snapshot?)` tells you exactly what data is available during an operation.

**Preferred:**
```swift
enum ModelState {
    case uninitialized
    case loading(prior: Snapshot?)
    case ready(Snapshot)
    case operating(UseCaseState, prior: Snapshot?)
}
```

**Avoid:**
```swift
// Multiple properties create ambiguous states
class Model {
    var isLoading = false
    var isOperating = false
    var snapshot: Snapshot?
    var useCaseState: UseCaseState?
    var prior: Snapshot?
    // What if isLoading && isOperating? What if snapshot != nil && isLoading?
}
```

#### Model Composition

Parent models can hold child models as properties. For features that require configuration (AWS credentials, GitHub tokens, etc.), prefer optional child models over models that exist in an "unconfigured" state.

**Rationale**: A model that doesn't exist is clearer than a model that exists but can't do anything. Views naturally handle this via `if let`, and there's no ambiguity about whether the feature is available.

```swift
@MainActor @Observable
class AppModel {
    var githubModel: GitHubModel?  // nil if GitHub not configured

    init() {
        // Only create if configuration exists
        if let config = try? GitHubConfiguration.load() {
            self.githubModel = GitHubModel(config: config)
        }
    }

    func configureGitHub(_ config: GitHubConfiguration) {
        githubModel = GitHubModel(config: config)
    }

    func clearGitHub() {
        githubModel = nil
    }
}
```

**View conditional rendering:**

```swift
struct ContentView: View {
    @State var appModel = AppModel()

    var body: some View {
        // View accesses appModel.githubModel → registers observation
        // When property changes (nil ↔ value), view re-renders
        if let githubModel = appModel.githubModel {
            GitHubView(model: githubModel)
        } else {
            ConfigureGitHubPrompt()
        }
    }
}
```

SwiftUI's `@Observable` tracks property access. When the view reads `appModel.githubModel`, it subscribes to changes. Setting the property to a new value (or nil) triggers a view update.

**Two levels of observation:**

| Change | What Updates |
|--------|--------------|
| `appModel.githubModel = newModel` | Parent view re-renders (model existence changed) |
| `githubModel.state = .loading` | Child view re-renders (model's internal state changed) |

**Requirements:**

- Use `@MainActor` on all models—observation may fail silently for changes on background threads
- Store root models in the `App` struct, not individual views, to avoid re-initialization on view rebuilds

**Passing models via Environment:**

Inject models at the root and access them in child views:

```swift
// App struct injects models
WindowGroup {
    ContentView()
        .environment(appModel)
        .environment(appModel.githubModel)  // nil is fine
}

// Child view receives optional model
struct GitHubSection: View {
    @Environment(GitHubModel.self) private var githubModel: GitHubModel?
}
```

**Configuration-driven model lifecycle:**

When settings change, the settings view saves configuration and notifies the parent model:

```swift
struct SettingsView: View {
    @Environment(AppModel.self) private var appModel
    @State private var token = ""

    var body: some View {
        Form {
            SecureField("Token", text: $token)
            Button("Save") {
                let config = GitHubConfiguration(token: token)
                try? config.save()              // Persist
                appModel.configureGitHub(config) // Create model
            }
            Button("Clear") {
                GitHubConfiguration.delete()
                appModel.clearGitHub()          // Set model to nil
            }
        }
    }
}
```

When configuration changes, simply replace the model. The old model deallocates and views automatically observe the new one. For cleanup of in-flight work, cancel tasks in `deinit`.

#### Model Lifecycle

Models self-initialize on `init`. This eliminates the need for views to trigger loading on appear.

```swift
@MainActor @Observable
class DeploymentModel {
    var state: ModelState = .loading(prior: nil)
    private let useCase: DeploymentUseCase

    init(useCase: DeploymentUseCase) {
        self.useCase = useCase
        Task { await load() }
    }

    private func load() async {
        let snapshot = try? await useCase.fetchStatus()
        state = .ready(snapshot ?? .empty)
    }
}
```

**When child models affect parent state:**

If a parent model's state depends on a child model, refresh when the child is set:

```swift
@MainActor @Observable
class AppModel {
    var state: AppState = .loading
    var githubModel: GitHubModel? {
        didSet { Task { await refreshState() } }
    }

    init() {
        Task { await refreshState() }
    }

    private func refreshState() async {
        let gitStatus = await githubModel?.fetchStatus()
        state = .ready(AppSnapshot(github: gitStatus))
    }
}
```

This pattern keeps views simple—they observe state without triggering loads.

#### CLI Commands

CLI commands use use cases directly without the `@Observable` wrapper. Use `stream()` for progress output, or `run()` for fire-and-forget:

```swift
struct DeployCommand: AsyncParsableCommand {
    func run() async throws {
        // Use stream() when you want progress output
        for try await state in useCase.stream(options: opts) {
            printProgress(state)
        }
    }
}

struct QuickCheckCommand: AsyncParsableCommand {
    func run() async throws {
        // Use run() when you only care about the final result
        let result = try await useCase.run(options: opts)
        print(result)
    }
}
```

### Features (`Sources/features/`)

Multi-step orchestration operations. Features combine use case logic and feature-specific service code in one target.

| Target | Description |
|--------|-------------|
| `DeployRemoteFeature` | AWS deployment use cases |
| `SetupFeature` | Setup and dependency use cases |
| `DeployXcodeFeature` | Xcode local development use cases |
| `DeployLinuxFeature` | Linux container development use cases |

**Responsibilities:**

- Use cases are structs conforming to `UseCase` or `StreamingUseCase` protocols (from `Uniflow`)
- Coordinate multiple SDK clients and services
- App-specific business logic and orchestration
- **Not** `@Observable`—that belongs in the app layer
- Depend on services and SDKs, but never vice versa

#### Features for Orchestration

Multi-step operations live in features as `StreamingUseCase` conformers.

```swift
import Uniflow

public struct DeployUseCase: StreamingUseCase {
    public typealias State = UseCaseState
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

### Services (`Sources/services/`)

Models, configuration, and stateful utilities shared across features.

| Target | Description |
|--------|-------------|
| `DeployCoreService` | Core deployment utilities and types |
| `DeployLocalService` | Local development shared configuration |
| `ClientService` | HTTP client utilities |
| `StorageService` | Local file storage service |
| `LambdaBuildService` | Lambda build utilities |

**Responsibilities:**

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
| `Uniflow` | Use case protocol definitions |

**Responsibilities:**

- Wrap external tools and services
- **Stateless**—no internal state management
- Operations return `AsyncThrowingStream` for progress or values for one-shot queries
- Can be extracted to separate packages
- **Use `Sendable` structs** for clients, not actors or classes—no mutable state means no need for isolation

#### Stateless SDKs

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

#### Use Case Protocols (Uniflow)

The `Uniflow` SDK defines two protocols for use case execution:

**`UseCase`** — Base protocol with a single `run(options:)` method:

```swift
public protocol UseCase: Sendable {
    associatedtype Options: Sendable = Void
    associatedtype Result: Sendable

    func run(options: Options) async throws -> Result
}
```

**`StreamingUseCase`** — Extends `UseCase` with streaming state updates:

```swift
public protocol StreamingUseCase: UseCase {
    associatedtype State: Sendable

    func stream(options: Options) -> AsyncThrowingStream<State, Error>
}
```

When `Result == State`, `StreamingUseCase` provides a default `run()` implementation that consumes the stream and returns the last state.

**When to use each:**

| Protocol | Use When | Example |
|----------|----------|---------|
| `UseCase` | Single result, no intermediate progress | Status checks, configuration loading |
| `StreamingUseCase` | Multi-step with progress updates | Deployments, builds, installations |

Most use cases in this codebase conform to `StreamingUseCase` since they perform multi-step operations.

## Source Code Structure

Targets are organized by architectural layer in folders:

```
Sources/
├── apps/                     # Entry points
│   ├── CLIApp/               # CLI tool (deployment commands)
│   ├── LambdaApp/            # AWS Lambda handler (entry point)
│   └── MacApp/               # Mac app (SwiftUI views, @Observable models)
├── features/                 # Feature modules (use case + service combined)
│   ├── DeployRemoteFeature/  # AWS deployment feature
│   │   ├── usecases/         # DeployUseCase, DestroyUseCase, etc.
│   │   └── services/         # Models, auth config, GitHub config
│   ├── DeployXcodeFeature/  # Xcode local development use cases
│   ├── DeployLinuxFeature/  # Linux container development use cases
│   └── SetupFeature/         # Setup and dependency use cases
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
| `SetupFeature` | features | Feature | Setup use cases |
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

## Data Flow

**CLI**: `useCase.stream() → print progress` or `useCase.run() → print result`

**Mac App**: `useCase.stream() → @Observable model → View`

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
