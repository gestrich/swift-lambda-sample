# Mac App Architecture

## Overview

The Mac app follows a **Feature-Service-SDK** architecture where services ARE the models.

## Project Structure

```
feature-mac/                             # Feature layer (handles I/O)
├── Views/
│   ├── ContentView.swift                # Main view, switches on mode
│   ├── RemoteView.swift                 # AWS deployment UI
│   ├── XcodeLocalView.swift             # Native macOS local dev UI
│   └── LinuxLocalView.swift             # Linux container local dev UI

Services/                                # Service layer (@Observable)
├── service-deploy/                      # AWS deployment state & orchestration
├── service-local-dev/                   # Local dev (Xcode + Linux)
└── service-settings/                    # App settings

SDKs/                                    # SDK layer (reusable)
├── sdk-cdk/                             # AWS CDK operations
├── sdk-github/                          # GitHub Actions operations
├── sdk-docker/                          # Docker container operations
└── sdk-cli/                             # Process execution utilities
```

## Services ARE Models

In this architecture, there is no separate model layer. Services are `@Observable` and serve as both the business logic layer and the observable state for UI binding.

**Key characteristics**:
- Services use `@Observable` for UI binding
- Services use `@MainActor` when consumed by UI
- Services orchestrate multiple SDKs
- Services hold cross-SDK derived state
- Views observe services directly

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

    // Actions for views
    func deploy() {
        Task {
            await cdkClient.deploy()
            await githubClient.triggerWorkflow()
        }
    }
}
```

## AppService

A top-level `AppService` serves as the root, composing all domain services.

```swift
@MainActor @Observable
class AppService {
    let deploymentService: DeploymentService
    let xcodeLocalDevService: XcodeLocalDevService
    let linuxLocalDevService: LinuxLocalDevService
    let settingsService: SettingsService

    var mode: ConnectionMode  // Current active mode
}
```

## Optional Services

Some services are defined as optional. These represent state that only exists after configuration or user action.

```swift
@MainActor @Observable
class AppService {
    let settingsService: SettingsService
    var syncService: SyncService?  // Only exists after user configures sync
}
```

## SDKs

SDKs are **reusable utilities** that handle external interactions. They are not app-specific.

**Key characteristics**:
- NOT `@Observable`
- Implemented as `actor` for thread safety (when stateful)
- May have state if inherently stateful (CDK, Docker)
- Publish state via `AsyncStream`
- Can be used directly by CLI (no MainActor requirement)

```swift
actor CDKClient {
    enum State: Sendable {
        case idle
        case deploying(progress: Double, startTime: Date)
        case deployed(outputs: StackOutputs)
        case failed(error: String)
    }

    func states() -> AsyncStream<State> { ... }
    func deploy() async throws { ... }
    func destroy() async throws { ... }
}
```

## Data Flow

```
View → Service (@Observable) → SDK (AsyncStream)
```

- **feature-mac**: Views observe services directly. Services call SDKs. SDKs publish state.
- **feature-cli**: Commands call services directly. Services call SDKs.

### State Update Flow

1. SDK performs operation, updates internal state, publishes via `AsyncStream`
2. Service receives state in `for await` loop, updates `@Observable` property
3. View automatically re-renders due to `@Observable` change

```swift
// Service observes SDK
private func observeCDK() async {
    for await state in await cdkClient.states() {
        self.cdkState = state  // @Observable property
    }
}
```

## Service Protocols (Optional)

Services may conform to protocols for testing or when multiple implementations exist:

```swift
protocol LambdaServiceProtocol {
    var endpoint: URL { get }
    var status: DeploymentStatus { get }
    func test() async throws -> TestResult
}

// Both conform to same protocol
class DeploymentService: LambdaServiceProtocol { ... }
class XcodeLocalDevService: LambdaServiceProtocol { ... }
```
