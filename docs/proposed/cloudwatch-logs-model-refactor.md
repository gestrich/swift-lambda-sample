# CloudWatchLogsModel Refactor

This document proposes refactoring the CloudWatch logs feature to align with the project's layered architecture vision.

## Current Architecture

```
CloudWatchLogsSectionView (app-mac)
    → CloudWatchLogsModel (app-mac/Models)
        → LambdaLogsService (service-deploy)
            → CloudWatchLogsClient (sdk-aws)
```

## Issues Identified

### 1. Model has multiple independent properties (violates enum-based state)

**Current implementation** (`CloudWatchLogsModel.swift:14-24`):

```swift
public private(set) var logEntries: [CloudWatchLogEntry] = []
public private(set) var status: LogsStatus = .idle
public private(set) var errorMessage: String?
```

Per `layered-architecture.md`: "Use enums to represent model state rather than multiple independent properties." Multiple properties create ambiguous states—what if `status = .idle` but `errorMessage != nil`?

### 2. Model contains too much logic (violates minimal logic pattern)

The model currently manages:
- Its own `streamTask` lifecycle (`CloudWatchLogsModel.swift:29`)
- State transitions in `startStreaming()` and `fetchRecentLogs()`
- Business logic like `trimEntriesIfNeeded()`

Per architecture: "Models should contain minimal logic—their role is to monitor workflow streams and update state for the UI."

### 3. LambdaLogsService is a thin passthrough, not a workflow

**Current implementation** (`CloudWatchLogsService.swift:53-58`):

```swift
public nonisolated func tailLogs(
    since: String = "5m",
    output: CLIOutputStream? = nil
) -> AsyncStream<CloudWatchLogsProgress> {
    genericClient.tailLogs(since: since, output: output)
}
```

The service just delegates to the SDK with no orchestration. Per architecture: "Workflows are structs returning `AsyncThrowingStream<Progress, Error>`" that coordinate multi-step operations.

### 4. SDK client has internal state (violates stateless SDK)

`CloudWatchLogsClient` maintains `streamTask` internally (`CloudWatchLogsClient.swift:36`). Per architecture: "SDK clients don't maintain internal state. Each method call is independent."

### 5. Type aliases and re-exports (violates code-style.md)

**Current implementation** (`CloudWatchLogsService.swift:6-8`):

```swift
public typealias CloudWatchLogEntry = sdk_aws.CloudWatchLogEntry
public typealias CloudWatchLogsProgress = sdk_aws.CloudWatchLogsProgress
public typealias CloudWatchLogsError = sdk_aws.CloudWatchLogsError
```

Per `code-style.md`: "Type aliases and re-exports are a code smell. They obscure the actual types being used."

### 6. Default parameter values

**Current implementation** (`CloudWatchLogsService.swift:24-25`):

```swift
lambdaFunctionName: String = "swift-lambda-sample"
```

Per `code-style.md`: "Prefer requiring data explicitly rather than providing defaults."

## Proposed Architecture

```
CloudWatchLogsSectionView (app-mac)
    → CloudWatchLogsModel (app-mac/Models)
        → CloudWatchLogsWorkflow (service-deploy)
            → CloudWatchLogsClient (sdk-aws)
```

### SDK Layer: Stateless `CloudWatchLogsClient`

Remove internal state. The client becomes a pure function wrapper around AWS CLI commands.

```swift
public struct CloudWatchLogsClient {
    private let cliClient: CLIClient

    public init(cliClient: CLIClient) {
        self.cliClient = cliClient
    }

    /// Fetch logs once (non-streaming)
    public func fetchLogs(
        logGroup: String,
        since: String,
        credentialProvider: AWSCredentialProvider
    ) async throws -> [CloudWatchLogEntry]

    /// Stream log entries - caller manages cancellation via task cancellation
    public func tailLogs(
        logGroup: String,
        since: String,
        credentialProvider: AWSCredentialProvider,
        pollInterval: Duration
    ) -> AsyncThrowingStream<CloudWatchLogEntry, Error>
}
```

Key changes:
- Struct instead of actor (stateless)
- No internal `streamTask` tracking
- Caller controls lifecycle via Swift's cooperative cancellation
- All parameters explicit (no defaults)

### Service Layer: `CloudWatchLogsWorkflow`

A workflow that orchestrates log streaming and yields state updates.

```swift
public struct CloudWatchLogsWorkflow {
    private let client: CloudWatchLogsClient
    private let logGroup: String
    private let credentialProvider: AWSCredentialProvider

    public init(
        client: CloudWatchLogsClient,
        logGroup: String,
        credentialProvider: AWSCredentialProvider
    ) {
        self.client = client
        self.logGroup = logGroup
        self.credentialProvider = credentialProvider
    }

    public func stream(since: String) -> AsyncThrowingStream<State, Error> {
        AsyncThrowingStream { continuation in
            Task {
                continuation.yield(.started)
                var entries: [CloudWatchLogEntry] = []

                do {
                    for try await entry in client.tailLogs(
                        logGroup: logGroup,
                        since: since,
                        credentialProvider: credentialProvider,
                        pollInterval: .seconds(3)
                    ) {
                        entries.append(entry)
                        entries = Self.trimIfNeeded(entries, maxCount: 1000)
                        continuation.yield(.streaming(entries: entries))
                    }
                    continuation.yield(.stopped(entries: entries))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    public func fetch(since: String) async throws -> [CloudWatchLogEntry] {
        try await client.fetchLogs(
            logGroup: logGroup,
            since: since,
            credentialProvider: credentialProvider
        )
    }

    private static func trimIfNeeded(_ entries: [CloudWatchLogEntry], maxCount: Int) -> [CloudWatchLogEntry] {
        entries.count > maxCount ? Array(entries.suffix(maxCount)) : entries
    }

    // MARK: - State

    public enum State: Sendable {
        case started
        case streaming(entries: [CloudWatchLogEntry])
        case stopped(entries: [CloudWatchLogEntry])
    }
}
```

Key changes:
- Workflow struct with `AsyncThrowingStream<State, Error>` return type
- Business logic (trimming) lives here, not in the model
- State enum captures all valid states

### App Layer: Minimal `CloudWatchLogsModel`

The model becomes a thin state holder that assigns workflow state directly.

```swift
import sdk_aws
import service_deploy
import Foundation
import Observation

@MainActor
@Observable
public final class CloudWatchLogsModel {
    // MARK: - State

    public private(set) var state: State = .idle
    public var sincePeriod: String = "1h"

    // MARK: - Private

    private let workflow: CloudWatchLogsWorkflow
    private var streamTask: Task<Void, Never>?

    // MARK: - Init

    public init(workflow: CloudWatchLogsWorkflow) {
        self.workflow = workflow
    }

    // MARK: - Public Methods

    public func startStreaming() {
        guard state.canStart else { return }

        stopStreaming()
        state = .streaming(entries: [])

        streamTask = Task {
            do {
                for try await workflowState in workflow.stream(since: sincePeriod) {
                    guard !Task.isCancelled else { break }

                    // Direct state assignment from workflow
                    switch workflowState {
                    case .started:
                        state = .streaming(entries: [])
                    case .streaming(let entries):
                        state = .streaming(entries: entries)
                    case .stopped(let entries):
                        state = .stopped(entries: entries)
                    }
                }
            } catch {
                state = .error(error.localizedDescription)
            }
        }
    }

    public func stopStreaming() {
        streamTask?.cancel()
        streamTask = nil

        if case .streaming(let entries) = state {
            state = .stopped(entries: entries)
        }
    }

    public func fetchRecentLogs() async {
        guard state.canStart else { return }

        stopStreaming()
        state = .loading

        do {
            let entries = try await workflow.fetch(since: sincePeriod)
            state = .idle(entries: entries)
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    public func clearLogs() {
        state = .idle
    }

    // MARK: - State Enum

    public enum State: Equatable {
        case idle
        case idle(entries: [CloudWatchLogEntry])
        case loading
        case streaming(entries: [CloudWatchLogEntry])
        case stopped(entries: [CloudWatchLogEntry])
        case error(String)

        public var entries: [CloudWatchLogEntry] {
            switch self {
            case .idle: return []
            case .idle(let entries): return entries
            case .loading: return []
            case .streaming(let entries): return entries
            case .stopped(let entries): return entries
            case .error: return []
            }
        }

        public var isStreaming: Bool {
            if case .streaming = self { return true }
            return false
        }

        public var isLoading: Bool {
            switch self {
            case .loading, .streaming: return true
            default: return false
            }
        }

        public var canStart: Bool {
            switch self {
            case .idle, .stopped, .error: return true
            default: return false
            }
        }

        public var errorMessage: String? {
            if case .error(let message) = self { return message }
            return nil
        }

        public var displayText: String {
            switch self {
            case .idle: return "Ready"
            case .loading: return "Loading..."
            case .streaming: return "Streaming"
            case .stopped: return "Stopped"
            case .error(let message): return "Error: \(message)"
            }
        }
    }
}
```

Key changes:
- Single enum-based state (no separate `logEntries`, `status`, `errorMessage`)
- Direct assignment from workflow state (minimal transformation)
- Business logic (trimming) removed—handled by workflow
- Model receives workflow via init (no internal service creation)

## Migration Steps

- [ ] **Refactor `CloudWatchLogsClient`** (sdk-aws)
   - Convert from actor to struct
   - Remove internal `streamTask` state
   - Return `AsyncThrowingStream<CloudWatchLogEntry, Error>` that respects task cancellation

- [ ] **Create `CloudWatchLogsWorkflow`** (service-deploy)
   - New workflow struct with `State` enum
   - Move trimming logic here
   - Return `AsyncThrowingStream<State, Error>`

- [ ] **Remove `LambdaLogsService`** (service-deploy)
   - Delete the thin wrapper
   - Remove type aliases and re-exports

- [ ] **Refactor `CloudWatchLogsModel`** (app-mac)
   - Convert to enum-based state
   - Remove business logic
   - Accept workflow via init

- [ ] **Update `CloudWatchLogsSectionView`** (app-mac)
   - Update to use new `State` enum
   - Update model initialization

- [ ] **Update dependent code**
   - `RemoteServiceView.swift` - Update model creation
   - Any tests that reference these types

## Files Affected

| File | Action |
|------|--------|
| `Sources/sdk-aws/CloudWatch/CloudWatchLogsClient.swift` | Refactor to stateless |
| `Sources/service-deploy/AWSService/CloudWatchLogsService.swift` | Delete |
| `Sources/service-deploy/AWSService/CloudWatchLogsWorkflow.swift` | Create |
| `Sources/app-mac/Models/CloudWatchLogsModel.swift` | Refactor to enum state |
| `Sources/app-mac/RemoteService/CloudWatchLogsSectionView.swift` | Update for new state |
| `Sources/app-mac/RemoteService/RemoteServiceView.swift` | Update model creation |

## Benefits

1. **Impossible invalid states** - Enum guarantees only valid combinations
2. **Clear separation** - SDK is stateless, workflow orchestrates, model holds state
3. **Testable** - Workflow can be tested independently of UI
4. **Consistent** - Follows established patterns in the codebase
5. **Simpler model** - Less logic to maintain and debug
