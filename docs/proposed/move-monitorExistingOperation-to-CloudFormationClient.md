# Move monitorExistingOperation Logic to CloudFormationClient

## Overview

This document analyzes moving the `monitorExistingOperation()` polling logic from `DeploymentService` to `CloudFormationClient`, using the existing `states()` AsyncStream mechanism.

## Current State

### DeploymentService.monitorExistingOperation() (service-deploy)

Location: `Sources/service-deploy/DeploymentService.swift:710-750`

```swift
private func monitorExistingOperation() async {
    var pollCount = 0
    let startTime = operationStartTime ?? Date()

    while !Task.isCancelled {
        pollCount += 1

        do {
            let events = try await getStackEvents()
            let newProgress = DeploymentProgress.from(
                events: events,
                since: nil,
                pollCount: pollCount
            )
            progress = newProgress

            // Update deploymentState with new progress, preserving operation name
            if case .deploying(let op, _, _) = deploymentState {
                deploymentState = .deploying(operation: op, progress: newProgress, startTime: startTime)
            } else if case .destroying = deploymentState {
                deploymentState = .destroying(progress: newProgress, startTime: startTime)
            }

            let status = try await cloudFormationClient.getStackStatus(name: stackName)

            if !StackStatus.isInProgress(status) {
                let finalState = try await queryCurrentState()
                deploymentState = finalState
                operationStartTime = nil
                return
            }
        } catch {
            // Continue polling
        }

        try await Task.sleep(for: .seconds(2))
    }
}
```

### Current CloudFormationClient.State

```swift
public enum State: Sendable, Equatable {
    case idle
    case querying(operation: String)
    case ready(stackExists: Bool)
    case failed(error: String)
}
```

This represents **client activity** (is it making API calls?), not **deployment state** (what's the stack doing?).

### The Problem: Two Different State Types

| CloudFormationClient.State | DeploymentState |
|---------------------------|-----------------|
| "What is the client doing?" | "What is the stack's state?" |
| `idle`, `querying`, `ready` | `deploying`, `destroying`, `deployed` |
| No progress info | Has `DeploymentProgress` |

During monitoring, we need to emit `DeploymentState` with progress updates, but `states()` emits `CloudFormationClient.State`.

## Proposed Design: Replace State Type with DeploymentState

Consolidate into a single state type. CloudFormationClient publishes `DeploymentState` via the existing `states()` mechanism.

### Key Insight

The `.querying` state provides little value to consumers. What they actually care about is deployment state. By switching to `DeploymentState`, the client can:

1. Publish deployment state via `states()`
2. Run `monitorExistingOperation` internally
3. Just call `publish()` as it polls - no new streams needed

### CloudFormationClient Changes

```swift
// sdk-aws/CloudFormation/CloudFormationClient.swift

public actor CloudFormationClient {
    // CHANGE: State type is now DeploymentState
    private var currentState: DeploymentState = .unknown
    private var continuations: [UUID: AsyncStream<DeploymentState>.Continuation] = [:]

    // Stack name for monitoring (set when monitoring starts)
    private var monitoredStackName: String?
    private var monitorTask: Task<Void, Never>?

    // MARK: - State Stream (unchanged API, different type)

    public nonisolated func states() -> AsyncStream<DeploymentState> {
        AsyncStream { continuation in
            let id = UUID()
            Task {
                await self.addContinuation(id: id, continuation: continuation)
                continuation.onTermination = { @Sendable _ in
                    Task { await self.removeContinuation(id: id) }
                }
            }
        }
    }

    private func publish(_ state: DeploymentState) {
        currentState = state
        for continuation in continuations.values {
            continuation.yield(state)
        }
    }

    // MARK: - Deployment State Query (already implemented)

    public func queryDeploymentState(stackName: String) async throws -> DeploymentState {
        // ... existing implementation ...
        // Now also publishes state
        let state = // ... query logic ...
        publish(state)
        return state
    }

    // MARK: - Monitor Operation (NEW)

    /// Start monitoring an in-progress operation.
    /// Publishes state updates via states() as progress changes.
    /// Call stopMonitoring() or let it complete naturally.
    public func startMonitoring(stackName: String) {
        guard monitorTask == nil else { return }

        monitoredStackName = stackName
        monitorTask = Task {
            await runMonitorLoop(stackName: stackName)
        }
    }

    public func stopMonitoring() {
        monitorTask?.cancel()
        monitorTask = nil
        monitoredStackName = nil
    }

    private func runMonitorLoop(stackName: String) async {
        var pollCount = 0
        let startTime = currentState.operationStartTime ?? Date()
        let operation = currentState.operationName ?? "Updating"

        while !Task.isCancelled {
            pollCount += 1

            do {
                let events = try await getStackEvents(name: stackName, limit: 50)
                let newProgress = DeploymentProgress.from(
                    events: events,
                    since: nil,
                    pollCount: pollCount
                )

                // Publish updated state with new progress
                switch currentState {
                case .deploying:
                    publish(.deploying(operation: operation, progress: newProgress, startTime: startTime))
                case .destroying:
                    publish(.destroying(progress: newProgress, startTime: startTime))
                default:
                    break
                }

                // Check if complete
                let status = try await getStackStatus(name: stackName)
                if !StackStatus.isInProgress(status) {
                    let finalState = try await queryDeploymentState(stackName: stackName)
                    publish(finalState)
                    monitorTask = nil
                    monitoredStackName = nil
                    return
                }
            } catch {
                // Continue polling on transient errors
            }

            do {
                try await Task.sleep(for: .seconds(2))
            } catch {
                break
            }
        }

        monitorTask = nil
        monitoredStackName = nil
    }
}
```

### DeploymentService Changes

```swift
// service-deploy/DeploymentService.swift

@MainActor @Observable
public class DeploymentService {
    // REMOVE: cloudFormationState property (no longer needed)
    // public private(set) var cloudFormationState: CloudFormationClient.State = .idle

    // KEEP: deploymentState (now fed directly from SDK)
    public private(set) var deploymentState: DeploymentState = .unknown

    // MARK: - SDK State Observation

    private func startObservingSDKStates() async {
        async let cdk: Void = observeCDKState()
        async let cf: Void = observeDeploymentState()  // RENAMED
        async let gh: Void = observeGitHubState()
        _ = await (cdk, cf, gh)
    }

    // CHANGE: Now observes DeploymentState directly
    private func observeDeploymentState() async {
        for await state in cloudFormationClient.states() {
            self.deploymentState = state
            self.progress = state.progress

            if !state.isBusy {
                self.operationStartTime = nil
            }
        }
    }

    // MARK: - Refresh

    public func refresh() async {
        do {
            let state = try await cloudFormationClient.queryDeploymentState(stackName: stackName)
            // State is automatically published via states()

            // Handle app-specific concerns
            if case .deployed(let outputs) = state {
                let config = try await detectConfiguration()
                infrastructureConfiguration = config
                stackOutputs = CDKStackOutputs.from(outputs)
            } else if case .notDeployed = state {
                infrastructureConfiguration = nil
                stackOutputs = nil
            }

            // Start monitoring if operation in progress
            if state.isBusy {
                await cloudFormationClient.startMonitoring(stackName: stackName)
            }
        } catch {
            // Handle errors...
        }
    }

    // REMOVE: monitorExistingOperation() - now handled by SDK
}
```

### DeploymentState Additions

```swift
// sdk-aws/CloudFormation/DeploymentState.swift

public enum DeploymentState: Sendable, Equatable {
    // ... existing cases ...

    // ADD: Helper to extract operation name
    public var operationName: String? {
        if case .deploying(let operation, _, _) = self {
            return operation
        }
        return nil
    }
}
```

## Data Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                    CloudFormationClient                          │
│                                                                  │
│  queryDeploymentState() ──→ publish(state) ──→ states()         │
│                                    ↑                             │
│  runMonitorLoop() ─────────────────┘                            │
│    - polls events                                                │
│    - calculates progress                                         │
│    - publishes updates                                           │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ AsyncStream<DeploymentState>
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    DeploymentService                             │
│                                                                  │
│  observeDeploymentState()                                        │
│    for await state in cloudFormationClient.states() {           │
│        self.deploymentState = state    // @Observable            │
│        self.progress = state.progress                            │
│    }                                                             │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ @Observable
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                         SwiftUI View                             │
└─────────────────────────────────────────────────────────────────┘
```

## Migration Steps

1. **Add `operationName` computed property to DeploymentState**

2. **Change CloudFormationClient state type from `State` to `DeploymentState`**
   - Update `currentState` property type
   - Update `continuations` type
   - Update `states()` return type
   - Update `publish()` parameter type

3. **Add monitoring methods to CloudFormationClient**
   - `startMonitoring(stackName:)`
   - `stopMonitoring()`
   - `runMonitorLoop(stackName:)` (private)

4. **Update `queryDeploymentState` to publish state**

5. **Update DeploymentService**
   - Remove `cloudFormationState` property
   - Rename `observeCloudFormationState()` to `observeDeploymentState()`
   - Update observer to handle `DeploymentState`
   - Remove `monitorExistingOperation()` method
   - Update `refresh()` to call `startMonitoring()` when needed

6. **Update any views** that referenced `cloudFormationState`

7. **Test**
   - Verify state flows from SDK to service to view
   - Verify progress updates during deploy/destroy
   - Verify completion detection
   - Verify cancellation works

## Benefits

1. **Single state stream**: No new AsyncStream, uses existing `states()`
2. **SDK owns deployment state**: All CloudFormation state logic in one place
3. **Simpler service**: Just observes and updates `@Observable` properties
4. **Natural fit**: `states()` now publishes what consumers actually care about
5. **Testability**: Monitor logic can be tested in SDK isolation

## What We Lose

1. **Client activity granularity**: No more `.querying` state
   - Mitigation: Consumers rarely used this anyway
   - Could add `.loading` case to DeploymentState if needed

2. **Breaking change**: `cloudFormationClient.states()` returns different type
   - Mitigation: Compile-time error, easy to fix

## Files Changed

| File | Change |
|------|--------|
| `Sources/sdk-aws/CloudFormation/DeploymentState.swift` | Add `operationName` computed property |
| `Sources/sdk-aws/CloudFormation/CloudFormationClient.swift` | Change state type to `DeploymentState`, add monitoring |
| `Sources/service-deploy/DeploymentService.swift` | Remove `cloudFormationState`, simplify observer, remove `monitorExistingOperation()` |

## Comparison: Before and After

### Before (Current)

```
CloudFormationClient                    DeploymentService
┌──────────────────────┐               ┌──────────────────────┐
│ State: idle/querying │──states()───→│ cloudFormationState  │
└──────────────────────┘               │                      │
                                       │ monitorExisting...() │ ← polling logic here
                                       │   └→ deploymentState │
                                       └──────────────────────┘
```

### After (Proposed)

```
CloudFormationClient                    DeploymentService
┌──────────────────────┐               ┌──────────────────────┐
│ DeploymentState      │──states()───→│ deploymentState      │
│ + monitoring loop    │               │ (just observes)      │
└──────────────────────┘               └──────────────────────┘
```
