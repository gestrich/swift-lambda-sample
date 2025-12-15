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

See `CDKInfrastructureQueryService` and `RemoteModel` in this codebase for a complete implementation of this pattern.

---

## CDKInfrastructureQueryService Compliance

### What's Compliant

| Pattern | Status | Location |
|---------|--------|----------|
| Actor-based service | ✅ | Line 6 |
| State enum with associated values | ✅ | Lines 11-79 |
| `states()` returning `AsyncStream<State>` | ✅ | Lines 113-123 |
| `publish()` method | ✅ | Lines 129-134 |
| Continuation cleanup with `onTermination` | ✅ | Lines 119-121 |
| Concurrency guards (`isBusy`, `canDeploy`) | ✅ | Lines 140, 160, 193 |
| Error states (`failed`, `credentialExpired`) | ✅ | Lines 18-19 |
| State computed properties | ✅ | Lines 21-78 |
| Query after operation completes | ✅ | Lines 176, 201 |

### What's Compliant (RemoteModel)

| Pattern | Status | Location |
|---------|--------|----------|
| `@MainActor @Observable` class | ✅ | Lines 11-13 |
| Holds observed state (`cdkState`) | ✅ | Line 48 |
| `for await` observation loop | ✅ | Lines 132-137 |
| Action methods forwarding to service | ✅ | Lines 315-340 |
| Service is private, state is public | ✅ | Lines 48, 57 |

### Issues to Address

1. **startTime uses `Date()` instead of source** (CDKInfrastructureQueryService lines 278, 281)

   When `queryCurrentState()` discovers an in-progress operation, it creates `startTime: Date()` instead of extracting from CloudFormation events. The actual operation may have started before the app launched.

2. **No automatic refresh on startup** (CDKInfrastructureQueryService)

   Service initializes with `.unknown` state but doesn't auto-refresh. Callers must explicitly call `refresh()`.

3. **RemoteModel doesn't trigger initial CDK refresh** (RemoteModel line 124-127)

   `init` starts observing and fetches endpoint, but doesn't call `cdkInfrastructureService.refresh()`. The CDK state remains `.unknown` until user triggers refresh.

### Refactor Plan

#### 1. Extract startTime from CloudFormation events

Update `queryCurrentState()` to get actual start time from events:

```swift
case CloudFormationStackStatusValues.createInProgress,
     CloudFormationStackStatusValues.updateInProgress:
    let events = try await getStackEvents()
    let startTime = events
        .filter { $0.resourceStatus?.contains("IN_PROGRESS") == true }
        .map { $0.timestamp }
        .min() ?? Date()
    return .deploying(operation: "Updating", progress: CDKDeploymentProgress(), startTime: startTime)
```

#### 2. Add automatic refresh on first observation

Option A: Refresh in `states()` if state is `.unknown`:

```swift
public func states() -> AsyncStream<State> {
    if state == .unknown {
        Task { await refresh() }
    }
    // ... existing continuation logic
}
```

Option B: Refresh in `init` (requires making init async or spawning Task).

#### 3. Trigger CDK refresh in RemoteModel init

```swift
Task {
    await self.startObservingCDKState()
    await self.cdkInfrastructureService?.refresh()  // Add this
    try? await self.fetchEndpoint()
}
```

### Priority

1. **Issue 3** (Low effort, high impact) - Users see actual state on app launch
2. **Issue 2** (Medium effort) - Service becomes self-initializing
3. **Issue 1** (Medium effort) - Accurate timing for discovered operations
