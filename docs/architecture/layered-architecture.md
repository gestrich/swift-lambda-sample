# Layered Architecture

This document defines the layered architecture and naming conventions for organizing Swift targets across the project.

## Overview

The project uses a three-layer architecture where dependencies flow downward:

```
┌─────────────────────────────────────────────────────────┐
│                       FEATURE                           │
│      feature-lambda  ·  feature-mac  ·  feature-cli     │
│                                                         │
│   Entry points, handle input/output                     │
└────────────────────────┬────────────────────────────────┘
                         │ uses
                         ▼
┌─────────────────────────────────────────────────────────┐
│                       SERVICE                           │
│   service-deploy  ·  service-local-dev  ·  ...          │
│                                                         │
│   Often @Observable (services ARE the models)           │
│   App-specific, orchestrates SDKs                       │
└────────────────────────┬────────────────────────────────┘
                         │ uses
                         ▼
┌─────────────────────────────────────────────────────────┐
│                         SDK                             │
│      sdk-cdk  ·  sdk-github  ·  sdk-docker  ·  ...      │
│                                                         │
│   Reusable, not app-specific                            │
│   May have state (publishes via AsyncStream)            │
└─────────────────────────────────────────────────────────┘
```

## Layer Definitions

### Features (`feature-*`)

Features are entry points—the executables that handle I/O.

**Naming**: `feature-lambda`, `feature-mac`, `feature-cli`

**Characteristics**:
- Executable targets (apps, command-line tools, Lambda handlers)
- Handle input/output
- Wire up services and present output
- Platform-specific I/O (SwiftUI views, terminal output, Lambda response encoding)

**What belongs here**:
- SwiftUI `View` structs (feature-mac)
- Argument parsing and output formatting (feature-cli)
- Request/response encoding (feature-lambda)
- Entry point and dependency wiring

```swift
// feature-mac - View observes Service directly
struct DeploymentView: View {
    @Bindable var service: DeploymentService

    var body: some View {
        switch service.state {
        case .idle:
            Button("Deploy") { service.deploy() }
        case .deploying(let progress):
            ProgressView(value: progress)
        case .deployed:
            Text("Deployed")
        case .failed(let error):
            ErrorView(error: error) { service.retry() }
        }
    }
}

// feature-cli - Command uses Service
struct DeployCommand: AsyncParsableCommand {
    func run() async throws {
        let service = DeploymentService(...)
        try await service.deploy()
        print("Deployed successfully")
    }
}
```

---

### Services (`service-*`)

Services contain app-specific business logic. In this architecture, **services ARE the models**—there is no separate model layer.

**Naming**: `service-deploy`, `service-local-dev`, `service-settings`

**Characteristics**:
- Often `@Observable` (for UI binding)
- `@MainActor` when used by UI (feature-mac)
- App-specific—not designed for reuse in other projects
- Orchestrate multiple SDKs
- Can depend on other services
- Hold and manage state for their service area

**State management**:
- Services own their state directly as `@Observable` properties
- Observe SDK state via `AsyncStream` using `for await` loops
- Cross-SDK derived state lives in services

```swift
@MainActor @Observable
class DeploymentService {
    // State from SDKs
    private(set) var cdkState: CDKClient.State = .idle
    private(set) var githubState: GitHubClient.State = .idle

    // SDKs
    private let cdkClient: CDKClient
    private let githubClient: GitHubClient

    // Cross-SDK derived state
    var canDeploy: Bool {
        cdkState.isIdle && githubState.isIdle
    }

    var state: DeploymentState {
        if case .deploying = cdkState { return .deploying }
        if case .deploying = githubState { return .deploying }
        if case .failed(let e) = cdkState { return .failed(e) }
        return .idle
    }

    init(cdkClient: CDKClient, githubClient: GitHubClient) {
        self.cdkClient = cdkClient
        self.githubClient = githubClient
        Task { await startObserving() }
    }

    private func startObserving() async {
        async let cdk: Void = observeCDK()
        async let github: Void = observeGitHub()
        _ = await (cdk, github)
    }

    private func observeCDK() async {
        for await state in await cdkClient.states() {
            self.cdkState = state
        }
    }

    // Actions
    func deploy() {
        Task {
            await cdkClient.deploy()
            await githubClient.triggerWorkflow()
        }
    }
}
```

---

### SDKs (`sdk-*`)

SDKs are reusable utilities that are not specific to this application. They could be extracted into separate open-source packages.

**Naming**: `sdk-cdk`, `sdk-github`, `sdk-docker`, `sdk-cli`

**Characteristics**:
- Library targets
- Reusable—not app-specific
- Can depend on other SDKs
- NOT `@Observable`
- May have state if inherently stateful (CDK deployments, Docker containers)
- Publish state changes via `AsyncStream`
- Many SDKs will be stateless

**Stateful SDK example** (CDK has inherent state—deployments in progress):

```swift
actor CDKClient {
    enum State: Sendable {
        case idle
        case deploying(progress: Double, startTime: Date)
        case deployed(outputs: StackOutputs)
        case failed(error: String)

        var isIdle: Bool {
            if case .idle = self { return true }
            return false
        }

        var isBusy: Bool {
            switch self {
            case .deploying: return true
            default: return false
            }
        }
    }

    private var state: State = .idle
    private var continuations: [UUID: AsyncStream<State>.Continuation] = [:]

    func states() -> AsyncStream<State> {
        AsyncStream { continuation in
            let id = UUID()
            self.continuations[id] = continuation
            continuation.yield(self.state)

            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeContinuation(id) }
            }
        }
    }

    private func removeContinuation(_ id: UUID) {
        continuations.removeValue(forKey: id)
    }

    private func publish(_ newState: State) {
        state = newState
        for continuation in continuations.values {
            continuation.yield(newState)
        }
    }

    func deploy() async {
        guard !state.isBusy else { return }
        publish(.deploying(progress: 0, startTime: Date()))

        do {
            let outputs = try await runCDKDeploy()
            publish(.deployed(outputs: outputs))
        } catch {
            publish(.failed(error: error.localizedDescription))
        }
    }
}
```

**Stateless SDK example** (simple utilities):

```swift
struct ProcessRunner {
    func run(_ command: String, arguments: [String]) async throws -> ProcessResult {
        // Execute process, return result
    }
}

struct ProcessResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}
```

---

## Dependency Rules

1. **Features** may depend on **Services** and **SDKs**
2. **Services** may depend on other **Services** and **SDKs**
3. **SDKs** may depend on other **SDKs** or external packages only
4. **Never** depend upward (SDKs cannot depend on services, services cannot depend on features)

```
feature-mac ──→ service-deploy ──→ sdk-cdk
     │                │                │
     │                │                └──→ sdk-cli
     │                │
     │                └──→ sdk-github ──→ sdk-cli
     │
     └──→ sdk-cdk (direct SDK access allowed for simple cases)
```

---

## State Flow

```
SDK (AsyncStream) → Service (@Observable) → View
```

1. SDK performs operation, updates internal state, publishes via `AsyncStream`
2. Service receives state in `for await` loop, updates `@Observable` property
3. View automatically re-renders due to `@Observable` change

**Key insight**: Services ARE models. There is no separate model layer. This eliminates unnecessary indirection while keeping clear separation between app-specific logic (services) and reusable utilities (SDKs).

---

## Error Handling

Errors flow through the same state system as normal operations.

### Error Flow

```
SDK catches error → publishes .failed state → Service observes → View displays
```

### SDK: Errors as State

Include error cases in the State enum. Use distinct cases for errors that need different UI treatment:

```swift
enum State: Sendable {
    case idle
    case loading
    case ready(data: SomeData)
    case failed(reason: String)
    case credentialExpired(message: String)  // Needs different UI/recovery
}
```

### SDK: Catching and Publishing Errors

Operations catch errors and publish error state:

```swift
func refresh() async {
    guard !state.isBusy else { return }
    publish(.loading)

    do {
        let newState = try await queryState()
        publish(newState)
    } catch CredentialError.expired(let message) {
        publish(.credentialExpired(message: message))
    } catch {
        publish(.failed(reason: error.localizedDescription))
    }
}
```

### View: Error Display with Recovery

Views switch on state and provide error UI with recovery actions:

```swift
var body: some View {
    switch service.sdkState {
    case .failed(let reason):
        ErrorView(message: reason) {
            service.refresh()
        }
    case .credentialExpired(let message):
        CredentialErrorView(message: message) {
            onOpenSettings?()
        }
    // ...
    }
}
```

### Error Handling Principles

1. **Errors are state** - No separate error handling path. Failed is just another state.
2. **SDK categorizes errors** - Different error types get different state cases.
3. **View decides presentation** - Different error states can have different UI and recovery actions.
4. **Recovery through actions** - Error views call service actions (refresh, retry) to recover.

---

## State Monitoring Patterns

SDKs often need to monitor external state (AWS, databases, etc.). There are distinct scenarios:

| Scenario | Trigger | Behavior |
|----------|---------|----------|
| **Startup** | SDK init | Capture initial state |
| **View Refresh** | User navigates to view | Re-fetch current state |
| **In-Progress Polling** | During active operation | Poll until complete |
| **Operation Complete** | After deploy/destroy | Capture final state |

### Centralized State Query

All scenarios use a single `queryState()` method that returns complete state:

```
                    ┌─────────────────┐
                    │  queryState()   │  ← Single source of truth
                    │   (one-shot)    │
                    └────────┬────────┘
                             │
        ┌────────────────────┼────────────────────┐
        │                    │                    │
   ┌────▼────┐         ┌─────▼─────┐        ┌─────▼─────┐
   │ startup │         │  refresh  │        │   poll    │
   └─────────┘         └───────────┘        └───────────┘
```

```swift
private func queryState() async throws -> State {
    let status = try await getStatus()

    switch status {
    case .complete:
        return .ready(data: try await fetchData())
    case .inProgress:
        let events = try await getEvents()
        let progress = buildProgress(from: events)
        let startTime = events.last?.timestamp ?? Date()
        return .operating(progress: progress, startTime: startTime)
    case .notFound:
        return .idle
    }
}
```

### Refresh Method

Handles startup and user-triggered refresh:

```swift
func refresh() async {
    guard !state.isBusy else { return }
    publish(.loading)

    let newState = try await queryState()
    publish(newState)

    // If we discovered an in-progress operation, monitor it
    if newState.isInProgress {
        await monitor()
    }
}
```

### Polling Monitor

For in-progress operations, poll until complete:

```swift
private func monitor() async {
    let startTime = Date()

    while !Task.isCancelled {
        let currentState = try await queryState()

        if case .operating(let progress) = currentState {
            publish(.operating(progress: progress, startTime: startTime))
        } else {
            publish(currentState)
            return  // Done - no longer in progress
        }

        try await Task.sleep(for: .seconds(2))
    }
}
```

### State Monitoring Principles

1. **queryState is pure** - Returns complete state snapshot
2. **Single query method** - All paths use same method for consistency
3. **Monitor discovers external ops** - If app launches during operation, monitor picks it up

---

## Implementation Notes

### Continuation Cleanup

Use `onTermination` to remove continuations when observers stop listening:

```swift
continuation.onTermination = { [weak self] _ in
    Task { await self?.removeContinuation(id) }
}
```

### Concurrency Guards

Prevent multiple operations from running simultaneously:

```swift
func doOperation() async {
    guard !state.isBusy else { return }
    // proceed
}
```

### State Computed Properties

Add helpers on the State enum for common queries:

```swift
extension CDKClient.State {
    var isBusy: Bool {
        switch self {
        case .loading, .operating: return true
        default: return false
        }
    }
}
```

---

## Current Targets Mapping

| Current Target      | Proposed Name           | Layer   |
|---------------------|-------------------------|---------|
| `SwiftLambda`       | `feature-lambda`        | Feature |
| `MacApp`            | `feature-mac`           | Feature |
| `SwiftDeployCLI`    | `feature-cli`           | Feature |
| `RemoteModel` + `RemoteDeploymentService` | `service-deploy` | Service |
| `XcodeLocalModel` + `XcodeLocalDevelopmentService` | `service-local-dev` | Service |
| `LocalStorageService` | `sdk-storage`          | SDK     |
| `CLIKit`            | `sdk-cli`                | SDK     |

---

## When to Create a New Target

**Create a new SDK when**:
- The code has no app-specific business logic
- It could be useful in unrelated projects
- You're wrapping a third-party dependency or external tool

**Create a new Service when**:
- The code contains business logic specific to this app
- You're orchestrating multiple SDKs for an app-specific workflow
- You need @Observable state for a feature area

**Keep code in a Feature when**:
- It's UI-specific (SwiftUI views)
- It's platform-specific I/O (argument parsing, response encoding)

---

## Testing

Each layer has its own test target:
- `feature-*-tests` — UI/integration tests
- `service-*-tests` — Business logic tests (mock SDKs)
- `sdk-*-tests` — Unit tests (minimal mocking)

Services are easily testable because SDKs can be injected as protocols.

---

## Summary

| Layer | @Observable | State | Publishes | Role |
|-------|-------------|-------|-----------|------|
| **Feature** | No | `@State` only | No | Entry point, I/O |
| **Service** | Yes | Cross-SDK | No | Orchestrate, expose to UI |
| **SDK** | No | Single-SDK | Yes (`AsyncStream`) | Do the work |
