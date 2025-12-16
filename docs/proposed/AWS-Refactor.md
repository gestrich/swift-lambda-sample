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

### [x] Phase 1: Move GitHub to SDK Layer ✅

**Goal**: Move `GitHubActionsService` and `GitService` from service-deploy to a new `sdk-github` target.

**Status**: COMPLETED

**Tasks**:
- [x] Create `sdk-github` target in Package.swift
- [x] Move `GitHubActionsService.swift` → `sdk-github/GitHubActionsClient.swift`
- [x] Move `GitService.swift` → `sdk-github/GitClient.swift`
- [x] Rename classes to use `*Client` suffix
- [x] Update imports in service-deploy
- [x] Update Package.swift dependencies

**Files Created**:
```
sdk-github/
├── CLI/
│   └── Gh.swift                    # GitHub CLI command definitions + models
├── GitHubActionsClient.swift       # High-level GitHub Actions orchestration
├── GitHubCLIClient.swift           # Low-level gh CLI wrapper
├── GitClient.swift                 # Git operations client
├── GitHubClientError.swift         # SDK-specific errors
└── (models inline in Gh.swift)     # GitHubWorkflowRun, GitHubRunDetail, etc.
```

**Technical Notes**:
- Created `GitHubActionsConfiguration` in sdk-github for SDK use
- Kept `GitHubConfiguration` in service-deploy for file persistence (extends SDK config with `toSDKConfiguration()`)
- Added `makeGitHubActionsClient()` factory function for creating clients from service-layer config
- Re-exported SDK types from service-deploy for backwards compatibility using `@_exported import`
- Type aliases (`GitHubActionsService = GitHubActionsClient`) maintain API compatibility

---

### [x] Phase 2: Add AsyncStream State to SDK Clients ✅

**Goal**: Stateful SDKs should publish state via `AsyncStream` per layered-architecture.md.

**Status**: COMPLETED

**Tasks**:
- [x] Add `State` enum to `CDKClient` in sdk-aws (idle, installing, building, deploying, deployed, destroying, destroyed, failed)
- [x] Add `states() -> AsyncStream<State>` to `CDKClient`
- [x] Add `State` enum to `CloudFormationClient` in sdk-aws (idle, querying, ready, failed)
- [x] Add `states() -> AsyncStream<State>` to `CloudFormationClient`
- [x] Add `State` enum to `GitHubActionsClient` in sdk-github (idle, triggering, monitoring, completed, failed)
- [x] Add `states() -> AsyncStream<State>` to `GitHubActionsClient`
- [x] Implement continuation management and cleanup in each
- [x] Add concurrency guards to prevent concurrent operations

**Technical Notes**:
- Each SDK client now manages a `currentState` property and a `continuations` dictionary for multiple subscribers
- The `states()` method is `nonisolated` to allow creation outside actor context, with async continuation registration
- State changes are published via a `publish(_:)` method that updates all subscribers
- Each state enum includes computed properties: `isBusy`, `canDeploy`/`canDestroy`/`canTrigger`, and `description`
- Concurrency guards added via state checks before starting operations (throws `CDKError.operationInProgress` if busy)
- Error states are published before throwing, ensuring observers see failure state
- `CDKClient.State` includes: `.idle`, `.installing`, `.building`, `.deploying(startTime:)`, `.deployed(outputs:)`, `.destroying(startTime:)`, `.destroyed`, `.failed(error:)`
- `CloudFormationClient.State` includes: `.idle`, `.querying(operation:)`, `.ready(stackExists:)`, `.failed(error:)`
- `GitHubActionsClient.State` includes: `.idle`, `.triggering(workflow:)`, `.monitoring(runId:startTime:)`, `.completed(runId:)`, `.failed(error:)`

**Example CDKClient State**:
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
        var description: String { ... }
    }

    nonisolated func states() -> AsyncStream<State> { ... }
    func getState() -> State { ... }
    private func publish(_ state: State) { ... }
}
```

---

### [x] Phase 3: Create @Observable DeploymentService ✅

**Goal**: Create a proper `@Observable` service that orchestrates SDKs, replacing the current actor-based `RemoteDeploymentService`.

**Status**: COMPLETED

**Tasks**:
- [x] Create `DeploymentService` as `@MainActor @Observable class`
- [x] Inject SDK clients: `CDKClient`, `CloudFormationClient`, `GitHubActionsClient`
- [x] Observe SDK states via `for await` loops
- [x] Expose cross-SDK derived state (e.g., `canDeploy`, `overallState`)
- [x] Implement action methods that delegate to SDKs
- [x] Move app-specific configuration logic from `SwiftLambdaCDKService`
- [x] Move infrastructure detection logic from `SwiftLambdaInfrastructureService`
- [x] Keep `RemoteDeploymentOrchestrator` for CLI-only stateless operations (or merge)

**File Created**:
```
service-deploy/
└── DeploymentService.swift    # @MainActor @Observable service
```

**Technical Notes**:
- `DeploymentService` is `@MainActor @Observable` class per layered-architecture.md
- Observes SDK states via `async let` parallel observation tasks:
  ```swift
  private func startObservingSDKStates() async {
      async let cdk: Void = observeCDK()
      async let cf: Void = observeCloudFormation()
      async let gh: Void = observeGitHub()
      _ = await (cdk, cf, gh)
  }
  ```
- Each SDK observation uses `for await` loop to update `@Observable` properties
- App-specific `DeployOptions` with postgres/NAT Gateway flags (from `SwiftLambdaCDKService`)
- Infrastructure detection logic (from `SwiftLambdaInfrastructureService`) now inline
- Cross-SDK derived state: `canDeploy`, `canDestroy`, `canUpdateLambda`, `isOperationInProgress`
- Convenience properties: `apiGatewayUrl`, `lambdaFunctionName`, `bucketName`, `isDeployed`, `errorMessage`
- Two initializers: full (explicit config) and convenience (loads config from disk)
- Progress tracking via `CDKOutputParser` and `CDKProgressAccumulator`
- Existing `RemoteDeploymentService` (actor) and `RemoteDeploymentOrchestrator` kept for backwards compatibility
- Phase 4 will update feature-mac to use `DeploymentService` directly, eliminating `RemoteModel`

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

### [x] Phase 4: Remove RemoteModel from feature-mac ✅

**Goal**: Views should observe `DeploymentService` directly—no separate model layer.

**Status**: COMPLETED

**Tasks**:
- [x] Update `RemoteServiceView` to use `@State var service: DeploymentService`
- [x] Update `CDKInfrastructureSectionView` to use `@Bindable var service: DeploymentService`
- [x] Update `LambdaUpdateView` to accept auxiliary models directly (GitHubCIModel, LambdaBuildService)
- [x] Move auxiliary model creation (GitHubCIModel, CloudWatchLogsModel, LambdaBuildService) to view init
- [x] Update `AppModel` to hold `DeploymentService` instead of `RemoteModel`
- [x] Update `ConnectionMode` enum to use `DeploymentService` for remote case
- [x] Delete `RemoteModel.swift`
- [x] Add exposed properties to `DeploymentService` (cliClient, projectRoot, awsConfig, githubConfig, apiClient)

**Technical Notes**:
- `DeploymentService` now exposes configuration properties needed by auxiliary models:
  - `cliClient: CLIClient` - for CLI operations
  - `projectRoot: String` - working directory
  - `awsConfig: AWSAuthConfiguration` - AWS credentials
  - `githubConfig: GitHubActionsConfiguration?` - GitHub settings
  - `apiClient: APIClient` - for API requests (computed from endpoint)
  - `endpoint: String` - API Gateway URL
  - `isConfigured: Bool` - whether endpoint is available
- Auxiliary models (`GitHubCIModel`, `CloudWatchLogsModel`, `LambdaBuildService`) are created in `RemoteServiceView.initializeAuxiliaryModels()` using DeploymentService's exposed config
- `ConnectionMode.service` property removed - remote services have different semantics than local services and don't need polymorphic access
- `ConnectionMode.localService` added to access local services via `LambdaService` protocol when needed
- State mapping: `DeploymentService.deploymentState: DeploymentState` replaces `RemoteModel.cdkState: RemoteDeploymentService.State`
- Configuration access: `service.infrastructureConfiguration?.hasDatabase` instead of `state.configuration.hasDatabase`
- Output access: `service.stackOutputs?.allOutputs` instead of `state.outputs.allOutputs`
- Action methods now async: `service.deploy(options:output:)`, `service.destroy(output:)`, `service.refresh()`

**Files Changed**:
```
feature-mac/
├── Models/
│   ├── RemoteModel.swift           # DELETED
│   └── AppModel.swift              # Updated to use DeploymentService
├── RemoteService/
│   ├── RemoteServiceView.swift     # Updated to use DeploymentService
│   ├── CDKInfrastructureSectionView.swift  # Updated to use DeploymentService
│   └── LambdaUpdateView.swift      # Updated to take auxiliary models directly

service-deploy/
├── DeploymentService.swift         # Added exposed properties
├── LambdaService/Protocols/
│   └── LambdaService.swift         # Updated comments
└── LocalDevelopmentService/Protocols/
    └── LocalService.swift          # Updated comments
```

---

### [x] Phase 5: Clean Up service-deploy ✅

**Goal**: Remove redundant wrappers and consolidate service-deploy to contain only `DeploymentService` and app-specific models.

**Status**: COMPLETED

**Tasks**:
- [x] Delete `SwiftLambdaCDKService.swift` (logic moved to DeploymentService)
- [x] Delete `SwiftLambdaInfrastructureService.swift` (logic moved to DeploymentService)
- [x] Delete `RemoteDeploymentService.swift` (replaced by DeploymentService)
- [x] Delete `RemoteDeploymentOrchestrator.swift` (merged into DeploymentService)
- [x] Consolidate models into `service-deploy/Models/`
- [x] Remove empty directories (`CDKService/`, `RemoteDeploymentService/`)
- [x] Update CLI commands to use `DeploymentService` (merged Phase 6 into this)

**Final service-deploy Structure**:
```
service-deploy/
├── DeploymentService.swift         # @Observable, main service
├── Models/
│   ├── DeploymentConfiguration.swift
│   ├── CDKInfrastructureConfiguration.swift
│   ├── CDKStackConfiguration.swift
│   └── CDKStackOutputs.swift
├── AWSService/                     # AWS-specific service utilities
├── DockerService/                  # Docker operations
├── GitHubService/                  # GitHub configuration persistence
├── LambdaService/                  # Lambda build service
├── LocalDevelopmentService/        # Local dev services
├── ToolsService/                   # CLI tool wrappers (Homebrew, etc.)
└── Core/                           # Shared errors
```

**Technical Notes**:
- `RemoteDeploymentOrchestrator` was deleted rather than kept—`DeploymentService` now serves both Mac app and CLI
- CLI commands use `@MainActor` helper methods to invoke `DeploymentService`
- Models moved from `CDKService/Models/` to top-level `Models/`
- `GitHubService/` retained for `GitHubConfiguration` (file persistence) and type re-exports for backwards compatibility
- `AWSService/`, `DockerService/`, `LambdaService/`, `LocalDevelopmentService/`, `ToolsService/`, `Core/` retained—these are not redundant wrappers

---

### [x] Phase 6: Update feature-cli Commands ✅

**Goal**: CLI commands should use `DeploymentService` or SDK clients directly.

**Status**: COMPLETED (merged into Phase 5)

**Tasks**:
- [x] Update `DeployCommand` to use `DeploymentService`
- [x] Update `DeployInitCommand` to use `DeploymentService`
- [x] Update `TearDownCommand` to use `DeploymentService`
- [x] Update `StatusCommand` to use `DeploymentService`
- [x] Update `UpdateLambdaCommand` to use `DeploymentService`
- [ ] Update `LogsCommand` to use `sdk-cloudwatch` directly (future work—not critical)
- [ ] Update `TestCommand` to use appropriate SDKs (future work—not critical)
- [x] Remove any direct usage of deleted services

**Technical Notes**:
- CLI commands now use `@MainActor` helper methods to bridge async operations with `DeploymentService`
- Pattern: `mutating func run() async throws` calls `try await runX()` which is `@MainActor`
- This pattern allows CLI commands to work with `@MainActor @Observable` DeploymentService

---

### [x] Phase 7: Update Package.swift and Dependencies ✅

**Goal**: Ensure all target dependencies are correct and minimal.

**Status**: COMPLETED

**Tasks**:
- [x] Update `feature-mac` dependencies to remove direct SDK dependencies
- [x] Update `feature-cli` dependencies to remove direct SDK dependencies
- [x] Add re-exports in `service-deploy` for SDK types needed by consumers
- [x] Verify no circular dependencies
- [x] Run `swift build` to verify compilation

**Note**: The original plan mentioned "Remove `sdk-aws` target" - this was incorrect. `sdk-aws` is still needed as a dependency of `service-deploy`. The goal was to remove **direct** dependencies from feature layers, not remove the target entirely.

**Technical Notes**:
- Added re-exports in `service-deploy/AWSService/AWSAuthConfiguration+Persistence.swift` for SDK types needed by feature-mac:
  - `AWSAuthConfiguration`, `CloudWatchLogEntry`, `CloudWatchLogsProgress` (from sdk-aws)
  - `DeploymentState`, `DeploymentProgress`, `ResourceProgress`, `ResourceStatus` (from sdk-aws)
- GitHub types were already re-exported in `service-deploy/GitHubService/GitHubActionsService.swift`
- Removed `import sdk_aws` from all feature-mac and feature-cli files
- Removed `import sdk_github` from feature-mac files
- Updated Package.swift to remove `sdk-aws` and `sdk-github` from feature-mac dependencies
- Updated Package.swift to remove `sdk-aws` from feature-cli dependencies

**Final Package.swift Dependencies**:
```swift
.target(name: "sdk-cli", dependencies: ["sdk-cli-macros"]),
.target(name: "sdk-aws", dependencies: ["sdk-cli"]),
.target(name: "sdk-github", dependencies: ["sdk-cli"]),
.target(name: "service-deploy", dependencies: ["sdk-client", "service-storage", "sdk-cli", "sdk-aws", "sdk-github"]),
.target(name: "feature-mac", dependencies: ["sdk-client", "service-deploy", "service-storage", "sdk-cli"]),
.target(name: "feature-cli", dependencies: ["ArgumentParser", "service-deploy"]),
```

**Key Benefit**: feature-mac and feature-cli now depend only on service-deploy for SDK functionality. SDK types are re-exported, maintaining a clean layered architecture where features access SDKs through the service layer.

---

### [x] Phase 8: Documentation and Verification ✅

**Goal**: Update documentation and verify the refactor is complete.

**Status**: COMPLETED

**Tasks**:
- [x] Update CLAUDE.md with new target structure
- [x] Update MacAppArchitecture.md to reflect changes
- [x] Move completed proposed refactor docs to completed folder
- [x] Run full test suite
- [x] Verify build succeeds
- [ ] Test Mac app functionality (manual testing by Bill)
- [ ] Test CLI functionality (manual testing by Bill)
- [ ] Verify deployment flow works end-to-end (manual testing by Bill)

**Technical Notes**:
- Updated CLAUDE.md to document the Feature-Service-SDK layered architecture with current target structure
- Updated MacAppArchitecture.md to reflect DeploymentService as the main @Observable service, direct view observation pattern, and SDK AsyncStream state flow
- Moved completed refactor docs to `docs/completed/`:
  - `CDKInfrastructureQueryService-refactor.md` - All 7 phases completed
  - `move-aws-to-sdk.md` - All 7 phases completed
- Added `sdk-github` dependency to test target for GitHubCLITests
- Added public init to `Gh.Auth.Status` for test accessibility
- All 357 unit tests pass; 1 pre-existing integration test failure (route mismatch in LinuxDeployTests: `/api/file` vs `/api/files`) is unrelated to this refactor

**Files Changed**:
```
CLAUDE.md                                      # Updated project structure docs
docs/architecture/MacAppArchitecture.md        # Updated to reflect new architecture
docs/proposed/AWS-Refactor.md                  # Marked Phase 8 complete
Package.swift                                  # Added sdk-github to test dependencies
Sources/sdk-github/CLI/Gh.swift                # Added public init to Gh.Auth.Status
Tests/service-deploy-tests/GitHubCLITests.swift # Added sdk_github import
```

**Docs Moved**:
```
docs/proposed/CDKInfrastructureQueryService-refactor.md → docs/completed/
docs/proposed/move-aws-to-sdk.md → docs/completed/
```

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

- [x] No separate "Model" classes in feature-mac (services ARE models)
- [x] All SDK clients are `actor` with `AsyncStream<State>`
- [x] `DeploymentService` is `@Observable` and orchestrates SDKs
- [x] Views observe services directly
- [x] CLI commands use services or SDKs directly
- [x] GitHub code moved to sdk-github
- [x] All tests pass (357/358, 1 pre-existing integration test issue)
- [ ] Mac app works correctly (manual verification pending)
- [ ] CLI works correctly (manual verification pending)
- [ ] Deployment flow works end-to-end (manual verification pending)
