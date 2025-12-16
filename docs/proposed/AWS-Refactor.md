# AWS/CDK Architecture Refactor Plan

This document outlines a phased plan to refactor the current AWS/CDK architecture to align with the principles defined in [layered-architecture.md](../architecture/layered-architecture.md).

## Current State Analysis

### Current Structure

```
feature-mac/
├── Models/
│   └── RemoteModel.swift          # @Observable, wraps RemoteDeploymentService

feature-cli/
├── Commands/
│   └── AWS commands...            # CLI entry points

service-deploy/
├── CDKService/
│   ├── RemoteDeploymentService.swift      # actor with AsyncStream state
│   ├── SwiftLambdaCDKService.swift        # App-specific CDK wrapper
│   ├── SwiftLambdaInfrastructureService.swift  # CloudFormation queries
│   └── Models/...
├── RemoteDeploymentService/
│   └── RemoteDeploymentOrchestrator.swift # Stateless CLI orchestrator
├── GitHubService/
│   ├── GitHubActionsService.swift
│   └── GitService.swift
└── AWSService/...

sdk-aws/
├── CDK/CDKClient.swift
├── CloudFormation/CloudFormationClient.swift
├── Lambda/LambdaClient.swift
├── S3/S3Client.swift
├── CloudWatch/CloudWatchLogsClient.swift
├── SecretsManager/SecretsManagerClient.swift
└── Auth/...
```

### Issues with Current Architecture

1. **Redundant Model Layer**: `RemoteModel` in feature-mac wraps `RemoteDeploymentService`. Per layered-architecture.md, services ARE models—no separate model layer needed.

2. **Service is an Actor**: `RemoteDeploymentService` is an `actor` using `AsyncStream`. Per the new architecture, SDKs should use actors/AsyncStream, services should be `@Observable`.

3. **GitHub in service-deploy**: `GitHubActionsService` is in service-deploy but it's reusable and should be an SDK.

4. **App-Specific Wrappers**: `SwiftLambdaCDKService` and `SwiftLambdaInfrastructureService` are thin wrappers that belong in the service layer but mix concerns.

### Target Architecture

```
feature-mac/
├── Views/                         # SwiftUI views only
│   └── RemoteView.swift           # Observes DeploymentService directly

feature-cli/
├── Commands/                      # CLI entry points only

service-deploy/
├── DeploymentService.swift        # @Observable, orchestrates SDKs
└── Models/                        # App-specific types (DeploymentConfiguration, etc.)

sdk-aws/
├── CDK/CDKClient.swift            # actor, AsyncStream state
├── CloudFormation/CloudFormationClient.swift
├── Lambda/LambdaClient.swift
├── S3/S3Client.swift
├── CloudWatch/CloudWatchLogsClient.swift
├── SecretsManager/SecretsManagerClient.swift
└── Auth/...

sdk-github/
├── GitHubActionsClient.swift      # Move from service-deploy
└── GitClient.swift
```

---

## Refactoring Phases

### [ ] Phase 1: Move GitHub to SDK Layer

**Goal**: Move `GitHubActionsService` and `GitService` from service-deploy to a new `sdk-github` target.

**Tasks**:
- [ ] Create `sdk-github` target in Package.swift
- [ ] Move `GitHubActionsService.swift` → `sdk-github/GitHubActionsClient.swift`
- [ ] Move `GitService.swift` → `sdk-github/GitClient.swift`
- [ ] Rename classes to use `*Client` suffix
- [ ] Update imports in service-deploy
- [ ] Update Package.swift dependencies

**Files to Create/Move**:
```
sdk-github/
├── GitHubActionsClient.swift       # from service-deploy/GitHubService/
├── GitClient.swift                 # from service-deploy/GitHubService/
└── Models/
    └── GitHubWorkflowRun.swift
```

---

### [ ] Phase 2: Add AsyncStream State to SDK Clients

**Goal**: Stateful SDKs should publish state via `AsyncStream` per layered-architecture.md.

**Tasks**:
- [ ] Add `State` enum to `CDKClient` in sdk-aws (idle, building, deploying, deployed, failed)
- [ ] Add `states() -> AsyncStream<State>` to `CDKClient`
- [ ] Add `State` enum to `CloudFormationClient` in sdk-aws (idle, querying, ready, failed)
- [ ] Add `states() -> AsyncStream<State>` to `CloudFormationClient`
- [ ] Add `State` enum to `GitHubActionsClient` in sdk-github (idle, triggering, monitoring, completed, failed)
- [ ] Add `states() -> AsyncStream<State>` to `GitHubActionsClient`
- [ ] Implement continuation management and cleanup in each
- [ ] Add concurrency guards to prevent concurrent operations

**Example CDKClient State**:
```swift
actor CDKClient {
    enum State: Sendable {
        case idle
        case building
        case deploying(progress: Double, startTime: Date)
        case deployed(outputs: [String: String])
        case destroying(progress: Double, startTime: Date)
        case destroyed
        case failed(error: String)

        var isBusy: Bool { ... }
        var canDeploy: Bool { ... }
    }

    func states() -> AsyncStream<State> { ... }
    private func publish(_ state: State) { ... }
}
```

---

### [ ] Phase 3: Create @Observable DeploymentService

**Goal**: Create a proper `@Observable` service that orchestrates SDKs, replacing the current actor-based `RemoteDeploymentService`.

**Tasks**:
- [ ] Create `DeploymentService` as `@MainActor @Observable class`
- [ ] Inject SDK clients: `CDKClient`, `CloudFormationClient`, `GitHubActionsClient`
- [ ] Observe SDK states via `for await` loops
- [ ] Expose cross-SDK derived state (e.g., `canDeploy`, `overallState`)
- [ ] Implement action methods that delegate to SDKs
- [ ] Move app-specific configuration logic from `SwiftLambdaCDKService`
- [ ] Move infrastructure detection logic from `SwiftLambdaInfrastructureService`
- [ ] Keep `RemoteDeploymentOrchestrator` for CLI-only stateless operations (or merge)

**DeploymentService Structure**:
```swift
@MainActor @Observable
public class DeploymentService {
    // SDK state observations
    private(set) var cdkState: CDKClient.State = .idle
    private(set) var cloudFormationState: CloudFormationClient.State = .idle
    private(set) var githubState: GitHubActionsClient.State = .idle

    // SDK clients
    private let cdkClient: CDKClient
    private let cloudFormationClient: CloudFormationClient
    private let githubClient: GitHubActionsClient

    // Cross-SDK derived state
    var canDeploy: Bool { ... }
    var canDestroy: Bool { ... }
    var isOperationInProgress: Bool { ... }

    // App-specific state
    private(set) var infrastructureConfiguration: CDKInfrastructureConfiguration?
    private(set) var stackOutputs: CDKStackOutputs?

    // Actions
    func refresh() async { ... }
    func deploy(withPostgres: Bool, withNATGateway: Bool) async { ... }
    func deployInit(...) async { ... }
    func updateLambdaCode() async { ... }
    func destroy() async { ... }
}
```

---

### [ ] Phase 4: Remove RemoteModel from feature-mac

**Goal**: Views should observe `DeploymentService` directly—no separate model layer.

**Tasks**:
- [ ] Update `RemoteView` to use `@Bindable var service: DeploymentService`
- [ ] Move any view-specific logic from `RemoteModel` to the view or service
- [ ] Delete `RemoteModel.swift`
- [ ] Update `AppModel` to hold `DeploymentService` instead of `RemoteModel`
- [ ] Update view hierarchy to pass `DeploymentService`

**Before**:
```swift
// RemoteModel.swift (DELETE)
@Observable class RemoteModel {
    private var remoteDeploymentService: RemoteDeploymentService?
    var cdkState: RemoteDeploymentService.State
}

// RemoteView.swift
struct RemoteView: View {
    @Bindable var model: RemoteModel
}
```

**After**:
```swift
// RemoteView.swift
struct RemoteView: View {
    @Bindable var service: DeploymentService

    var body: some View {
        switch service.cdkState {
        case .idle: ...
        case .deploying: ...
        }
    }
}
```

---

### [ ] Phase 5: Clean Up service-deploy

**Goal**: Remove redundant wrappers and consolidate service-deploy to contain only `DeploymentService` and app-specific models.

**Tasks**:
- [ ] Delete `SwiftLambdaCDKService.swift` (logic moved to DeploymentService)
- [ ] Delete `SwiftLambdaInfrastructureService.swift` (logic moved to DeploymentService)
- [ ] Delete `RemoteDeploymentService.swift` (replaced by DeploymentService)
- [ ] Evaluate `RemoteDeploymentOrchestrator` - merge into DeploymentService or keep for CLI
- [ ] Consolidate models into `service-deploy/Models/`
- [ ] Remove empty directories

**Final service-deploy Structure**:
```
service-deploy/
├── DeploymentService.swift         # @Observable, main service
├── DeploymentOrchestrator.swift    # Optional: stateless CLI helper
└── Models/
    ├── DeploymentConfiguration.swift
    ├── CDKInfrastructureConfiguration.swift
    └── CDKStackOutputs.swift
```

---

### [ ] Phase 6: Update feature-cli Commands

**Goal**: CLI commands should use `DeploymentService` or SDK clients directly.

**Tasks**:
- [ ] Update `DeployCommand` to use `DeploymentService`
- [ ] Update `DeployInitCommand` to use `DeploymentService`
- [ ] Update `TearDownCommand` to use `DeploymentService`
- [ ] Update `StatusCommand` to use `DeploymentService`
- [ ] Update `UpdateLambdaCommand` to use `DeploymentService`
- [ ] Update `LogsCommand` to use `sdk-cloudwatch` directly
- [ ] Update `TestCommand` to use appropriate SDKs
- [ ] Remove any direct usage of deleted services

---

### [ ] Phase 7: Update Package.swift and Dependencies

**Goal**: Ensure all target dependencies are correct and minimal.

**Tasks**:
- [ ] Define all new SDK targets in Package.swift
- [ ] Update `service-deploy` dependencies to use new SDKs
- [ ] Update `feature-mac` dependencies
- [ ] Update `feature-cli` dependencies
- [ ] Remove `sdk-aws` target
- [ ] Verify no circular dependencies
- [ ] Run `swift build` to verify compilation
- [ ] Run tests to verify functionality

**Final Package.swift Targets**:
```swift
.target(name: "sdk-cli", ...),
.target(name: "sdk-aws", dependencies: ["sdk-cli"]),
.target(name: "sdk-github", dependencies: ["sdk-cli"]),
.target(name: "service-deploy", dependencies: ["sdk-aws", "sdk-github"]),
.target(name: "feature-mac", dependencies: ["service-deploy"]),
.target(name: "feature-cli", dependencies: ["service-deploy"]),
```

---

### [ ] Phase 8: Documentation and Verification

**Goal**: Update documentation and verify the refactor is complete.

**Tasks**:
- [ ] Update CLAUDE.md with new target structure
- [ ] Update MacAppArchitecture.md to reflect changes
- [ ] Delete or archive old proposed refactor docs that are now complete
- [ ] Run full test suite
- [ ] Test Mac app functionality
- [ ] Test CLI functionality
- [ ] Verify deployment flow works end-to-end

---

## Migration Notes

### Breaking Changes

1. **RemoteModel removed**: Any code referencing `RemoteModel` must switch to `DeploymentService`
2. **sdk-github created**: GitHub-related imports move from service-deploy to sdk-github
3. **RemoteDeploymentService removed**: Use `DeploymentService` instead

### Compatibility Strategy

- Each phase should be completable independently
- Run tests after each phase
- Keep old code until new code is verified working
- Use feature flags if needed for gradual rollout

---

## Success Criteria

After refactoring is complete:

- [ ] No separate "Model" classes in feature-mac (services ARE models)
- [ ] All SDK clients are `actor` with `AsyncStream<State>`
- [ ] `DeploymentService` is `@Observable` and orchestrates SDKs
- [ ] Views observe services directly
- [ ] CLI commands use services or SDKs directly
- [ ] GitHub code moved to sdk-github
- [ ] All tests pass
- [ ] Mac app works correctly
- [ ] CLI works correctly
- [ ] Deployment flow works end-to-end
