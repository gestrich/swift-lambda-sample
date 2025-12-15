# MV Model-Service State Architecture

## Core Principle

The app model should own the state the UI cares about.

Services may hold internal state, but they should not be the primary source of truth for UI behavior unless they represent a clear, stateful subsystem.

## Layer Responsibilities

```
View → Model → Service
```

- **Service** (`actor`): Owns operational state, exposes via `AsyncStream<State>`. Contains all business logic.
- **Model** (`@Observable`): Observes service, holds state for SwiftUI binding. Thin layer - no business logic.
- **View**: Observes model, calls model actions. Never talks to service directly.

## Key Principles

1. **Service owns state** - State lives in the service as a unified enum. No separate "status" structs.

2. **No wrapper models** - Don't create thin model wrappers just to hold state. If the model only mirrors service state, it's unnecessary overhead. Integrate into the parent model.

3. **Operation timing belongs in service** - Things like `startTime` for operations are service concerns. Include them in the state enum's associated values.

4. **Views use models, not services** - Mac views should observe models. Models bridge the actor-isolated service to the @MainActor UI world.

5. **Models expose actions** - The model provides action methods that forward to the service. Views don't create their own Tasks to call services.

---

## Service Pattern

Services own state as a unified enum and expose it via `AsyncStream`:

```swift
actor MyService {
    enum State: Sendable {
        case idle
        case loading
        case ready(data: SomeData)
        case operating(progress: Double, startTime: Date)
        case failed(reason: String)
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

    func doOperation() async {
        guard !state.isBusy else { return }  // Guard against concurrent ops
        publish(.operating(progress: 0, startTime: Date()))
        // ... perform work, publish progress updates ...
        publish(.ready(data: result))
    }
}
```

## Model Pattern

Models observe services and expose state + actions for views:

```swift
@MainActor @Observable
class MyModel {
    private(set) var serviceState: MyService.State = .idle
    private let service: MyService

    init(service: MyService) {
        self.service = service
        Task { await startObserving() }
    }

    private func startObserving() async {
        for await state in await service.states() {
            self.serviceState = state
        }
    }

    // Action methods for views
    func doOperation() {
        Task { await service.doOperation() }
    }

    func refresh() {
        Task { await service.refresh() }
    }
}
```

## View Pattern

Views observe model state and call model actions:

```swift
struct MyView: View {
    @Bindable var model: MyModel

    var body: some View {
        switch model.serviceState {
        case .idle:
            Button("Start") { model.doOperation() }
        case .loading:
            ProgressView()
        case .ready(let data):
            DataView(data: data)
        case .operating(let progress, _):
            ProgressView(value: progress)
        case .failed(let reason):
            ErrorView(reason: reason) { model.refresh() }
        }
    }
}
```

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
extension MyService.State {
    var isBusy: Bool {
        switch self {
        case .loading, .operating: return true
        default: return false
        }
    }
}
```

---

## Error Handling

Errors flow through the same state system as normal operations.

### Error Flow

```
Service catches error → publishes .failed state → Model observes → View displays
```

### Service: Errors as State

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

### Service: Catching and Publishing Errors

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
    switch model.serviceState {
    case .failed(let reason):
        ErrorView(message: reason) {
            model.refresh()
        }
    case .credentialExpired(let message):
        CredentialErrorView(message: message) {
            onOpenSettings?()
        }
    // ...
    }
}
```

### Key Principles

1. **Errors are state** - No separate error handling path. Failed is just another state.
2. **Service categorizes errors** - Different error types get different state cases.
3. **View decides presentation** - Different error states can have different UI and recovery actions.
4. **Recovery through actions** - Error views call model actions (refresh, retry) to recover.

---

## State Monitoring Patterns

Services often need to monitor external state (AWS, databases, etc.). There are distinct scenarios:

| Scenario | Trigger | Behavior |
|----------|---------|----------|
| **Startup** | Service init | Capture initial state |
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
// Returns complete state - timing comes from the source, not the caller
private func queryState() async throws -> State {
    let status = try await getStatus()

    switch status {
    case .complete:
        return .ready(data: try await fetchData())
    case .inProgress:
        let events = try await getEvents()
        let progress = buildProgress(from: events)
        let startTime = events.last?.timestamp ?? Date()  // From source
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
    let startTime = Date()  // Timing tracked here, not in queryState

    while !Task.isCancelled {
        let currentState = try await queryState()

        // Add timing context and publish
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

### Key Principles

1. **queryState is pure** - Returns complete state snapshot, no timing
2. **Caller provides context** - Timing comes from the caller (monitor tracks startTime)
3. **Single query method** - All paths use same method for consistency
4. **Monitor discovers external ops** - If app launches during operation, monitor picks it up

---

## Reference Implementation

See `RemoteDeploymentService` and `RemoteModel` in this codebase for a complete implementation of this pattern.

**File locations:**
- Service: `Sources/service-deploy/CDKService/RemoteDeploymentService.swift`
- Model: `Sources/feature-mac/Models/RemoteModel.swift`

---

## RemoteDeploymentService Compliance

### What's Compliant (Service)

| Pattern | Status | Location |
|---------|--------|----------|
| Actor-based service | ✅ | Line 19 |
| State enum with associated values | ✅ | Lines 25-93 |
| `states()` returning `AsyncStream<State>` | ✅ | Lines 158-172 |
| `publish()` method | ✅ | Lines 178-183 |
| Continuation cleanup with `onTermination` | ✅ | Lines 168-170 |
| Concurrency guards (`isBusy`, `canDeploy`, `canDestroy`) | ✅ | Lines 35-60 |
| Error states (`failed`, `credentialExpired`) | ✅ | Lines 32-33 |
| State computed properties | ✅ | Lines 35-92 |
| Query after operation completes | ✅ | Lines 225-226, 250-251 |
| Auto-refresh on first observation | ✅ | Lines 159-161 |

### What's Compliant (RemoteModel)

| Pattern | Status | Location |
|---------|--------|----------|
| `@MainActor @Observable` class | ✅ | Lines 12-14 |
| Holds observed state (`cdkState`) | ✅ | Line 49 |
| `for await` observation loop | ✅ | Lines 137-142 |
| Action methods forwarding to service | ✅ | Lines 327-345 |
| Service is private, state is public | ✅ | Lines 49, 58 |
| Initial refresh triggered | ✅ | Line 130 |

### Design Decisions

1. **startTime extracted from CloudFormation events** (RemoteDeploymentService)

   `queryCurrentState()` calls `getOperationStartTime()` to extract the actual start time from CloudFormation events when discovering in-progress operations (Lines 593-600).

2. **Automatic refresh on first observation** (RemoteDeploymentService)

   `states()` auto-triggers `refresh()` if state is `.unknown`, making the service self-initializing (Lines 159-161).

3. **RemoteModel triggers initial CDK refresh** (RemoteModel)

   `init` calls `remoteDeploymentService?.refresh()` after starting observation (Line 130).
