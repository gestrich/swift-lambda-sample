# Mac App Architecture

## Overview

The Mac app follows a **Feature-Service-SDK** architecture where services ARE the models. Views observe `@Observable` services directly—there is no separate model layer.

## Project Structure

```
feature-mac/                             # Feature layer (handles I/O)
├── Views/
│   ├── ContentView.swift                # Main view, switches on mode
│   ├── RemoteServiceView.swift          # AWS deployment UI
│   ├── XcodeLocalView.swift             # Native macOS local dev UI
│   └── LinuxLocalView.swift             # Linux container local dev UI

service-deploy/                          # Service layer (@Observable)
├── DeploymentService.swift              # Main service, orchestrates SDKs
├── Models/                              # App-specific models
├── LocalDevelopmentService/             # Local dev services

sdk-aws/                                 # SDK layer (reusable)
├── CDK/CDKClient.swift                  # CDK operations (actor, AsyncStream)
├── CloudFormation/CloudFormationClient.swift  # Stack queries
├── Lambda/LambdaClient.swift            # Lambda operations
├── S3/S3Client.swift                    # S3 operations
└── CloudWatch/CloudWatchLogsClient.swift

sdk-github/                              # GitHub SDK
├── GitHubActionsClient.swift            # GitHub Actions (actor, AsyncStream)
└── GitClient.swift                      # Git operations
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
// feature-mac: View observes DeploymentService directly
struct RemoteServiceView: View {
    @State var service: DeploymentService

    var body: some View {
        // Read state directly from service
        if service.isOperationInProgress {
            ProgressView()
        }

        // Bind to service properties
        CDKInfrastructureSectionView(service: service)
    }
}
```

## DeploymentService

The main `@Observable` service that orchestrates all AWS/GitHub SDK clients.

```swift
@MainActor @Observable
public class DeploymentService {
    // SDK state observations (updated via AsyncStream)
    private(set) var cdkState: CDKClient.State = .idle
    private(set) var cloudFormationState: CloudFormationClient.State = .idle
    private(set) var githubState: GitHubActionsClient.State = .idle

    // SDK clients
    private let cdkClient: CDKClient
    private let cloudFormationClient: CloudFormationClient
    private let githubClient: GitHubActionsClient

    // Cross-SDK derived state
    var canDeploy: Bool {
        !isOperationInProgress && cloudFormationState.canDeploy
    }

    var canDestroy: Bool {
        !isOperationInProgress && cloudFormationState.canDestroy
    }

    var isOperationInProgress: Bool {
        cdkState.isBusy || cloudFormationState.isBusy || githubState.isBusy
    }

    // App-specific state
    private(set) var infrastructureConfiguration: CDKInfrastructureConfiguration?
    private(set) var stackOutputs: CDKStackOutputs?

    // Actions delegate to SDKs
    func deploy(options: DeployOptions, output: OutputHandler) async { ... }
    func destroy(output: OutputHandler) async { ... }
    func refresh() async { ... }
}
```

## SDKs with AsyncStream State

SDKs are `actor` types that publish state via `AsyncStream`. This allows services to observe SDK state changes reactively.

```swift
actor CDKClient {
    enum State: Sendable, Equatable {
        case idle
        case installing
        case building
        case deploying(startTime: Date)
        case deployed(outputs: [String: String])
        case destroying(startTime: Date)
        case destroyed
        case failed(error: String)

        var isBusy: Bool { ... }
        var canDeploy: Bool { ... }
        var canDestroy: Bool { ... }
    }

    nonisolated func states() -> AsyncStream<State> { ... }
    func deploy(...) async throws { ... }
    func destroy(...) async throws { ... }
}
```

## Data Flow

```
SDK (actor) → AsyncStream → Service (@Observable) → View
```

### State Update Flow

1. SDK performs operation, updates internal state, publishes via `AsyncStream`
2. Service receives state in `for await` loop, updates `@Observable` property
3. View automatically re-renders due to `@Observable` change

```swift
// DeploymentService observes SDK states
private func startObservingSDKStates() async {
    async let cdk: Void = observeCDK()
    async let cf: Void = observeCloudFormation()
    async let gh: Void = observeGitHub()
    _ = await (cdk, cf, gh)
}

private func observeCDK() async {
    for await state in await cdkClient.states() {
        self.cdkState = state  // @Observable property triggers view update
    }
}
```

## Dependency Flow

Features access SDKs **through services only**. SDK types are re-exported from service-deploy for convenience.

```
feature-mac
    │
    └──→ service-deploy (depends on sdk-aws, sdk-github)
              │
              ├──→ sdk-aws (CDKClient, CloudFormationClient, etc.)
              └──→ sdk-github (GitHubActionsClient, GitClient)
```

**Package.swift dependencies:**
```swift
.target(name: "feature-mac", dependencies: [
    "sdk-client", "service-deploy", "service-storage", "sdk-cli"
])
// Note: feature-mac does NOT directly depend on sdk-aws or sdk-github
```

## Auxiliary Models

Some views require auxiliary models for specific functionality. These are created from DeploymentService's exposed configuration:

```swift
// RemoteServiceView creates auxiliary models from DeploymentService
private func initializeAuxiliaryModels() {
    let awsConfig = service.awsConfig
    let projectRoot = service.projectRoot

    self.logsModel = CloudWatchLogsModel(awsConfig: awsConfig, ...)
    self.ciModel = GitHubCIModel(config: service.githubConfig, ...)
    self.buildService = LambdaBuildService(projectRoot: projectRoot, ...)
}
```

## Testing

Services are testable by injecting mock SDK clients. SDKs can be tested in isolation.

```swift
// Test DeploymentService with mock SDKs
let mockCDK = MockCDKClient()
let mockCF = MockCloudFormationClient()
let mockGH = MockGitHubActionsClient()

let service = DeploymentService(
    cdkClient: mockCDK,
    cloudFormationClient: mockCF,
    githubClient: mockGH,
    ...
)
```
