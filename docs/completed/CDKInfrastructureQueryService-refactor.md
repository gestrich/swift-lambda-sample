# CDKInfrastructureQueryService Refactoring Proposal

## Problem Summary

`CDKInfrastructureQueryService` violates the layered architecture by duplicating generic AWS monitoring logic. Additionally, `DeploymentMonitor` in `sdk-aws` violates the principle that SDKs should be stateless.

## Architecture Principles (from docs/architecture)

### From layered-architecture.md
- **SDKs**: Stateless, reusable, app-agnostic utilities
- **Services**: Business logic, can be stateful for complex state machines
- **Features**: Own app state via @Observable models

### From MV_Model_Service_State.md
- **Service** owns state as unified enum, exposes via `AsyncStream<State>`
- **Model** observes service, bridges to @MainActor
- Pattern: `View → Model → Service (stateful) → SDK (stateless)`

## Current Violations

### 1. DeploymentMonitor in sdk-aws is Stateful

`sdk-aws/CloudFormation/DeploymentMonitor.swift` has:
- `private var state: DeploymentState`
- `states() -> AsyncStream<DeploymentState>`
- State machine with continuations

**Violates**: "SDKs... Stateless... No app-specific business logic"

### 2. Duplicated State Machines

Both `DeploymentMonitor` (sdk-aws) and `CDKInfrastructureQueryService` (service-deploy) implement the same state machine pattern with nearly identical code.

### 3. Mixed Concerns

`CDKInfrastructureQueryService` mixes:
- Generic CloudFormation monitoring (should be shared)
- App-specific config detection (withPostgres, withNATGateway)

## What's Actually App-Specific

Only these elements are truly specific to this application:

1. **CDKInfrastructureConfiguration** - Detects hasDatabase, hasNATGateway, hasVPC
2. **CDKStackOutputs** - Typed outputs (apiGatewayUrl, lambdaFunctionName)
3. **Deploy Options** - withPostgres, withNATGateway flags
4. **Stack Name** - "SwiftLambdaSampleStack"

## Proposed Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                     feature-mac / feature-cli                        │
│                                                                      │
│  RemoteModel                                                        │
│  └─ Observes RemoteDeploymentService.states()                       │
└──────────────────────────┬──────────────────────────────────────────┘
                           │ depends on
                           ▼
┌─────────────────────────────────────────────────────────────────────┐
│                        service-deploy                                │
│                                                                      │
│  RemoteDeploymentService (STATEFUL - owns AsyncStream<State>)       │
│  ├─ states() → AsyncStream<State>                                   │
│  ├─ deploy(withPostgres:withNATGateway:), destroy(), refresh()      │
│  ├─ Uses CloudFormationClient for queries                           │
│  ├─ Uses CDKClient for deploy/destroy                               │
│  ├─ App-specific: config detection, typed outputs                   │
│  └─ Polling, progress tracking, error handling                      │
│                                                                      │
│  SwiftLambdaInfrastructureService (stateless - keep)                │
│  └─ detectConfiguration() → CDKInfrastructureConfiguration          │
│                                                                      │
│  SwiftLambdaCDKService (stateless - keep)                           │
│  └─ build(), deploy(options:), destroy()                            │
└──────────────────────────┬──────────────────────────────────────────┘
                           │ depends on
                           ▼
┌─────────────────────────────────────────────────────────────────────┐
│                          sdk-aws (STATELESS)                         │
│                                                                      │
│  CloudFormationClient (stateless)                                   │
│  └─ getStackStatus(), getStackOutputs(), getStackEvents()           │
│                                                                      │
│  CDKClient (stateless)                                              │
│  └─ build(), deploy(), destroy(), diff(), synth()                   │
│                                                                      │
│  Types (no state machine):                                          │
│  ├─ DeploymentProgress, ResourceProgress, ResourceStatus            │
│  ├─ StackStatus (enum of status strings)                            │
│  ├─ CloudFormationStackEvent, CloudFormationStackResource           │
│  └─ CDKOutputParser, CDKProgressAccumulator (stateless parsing)     │
└─────────────────────────────────────────────────────────────────────┘
```

## Phased Implementation

### Phase 1: Make sdk-aws Stateless ✅ COMPLETED

- [x] Remove `DeploymentMonitor` actor from sdk-aws (it's stateful)
- [x] Keep `CloudFormationClient` (already stateless)
- [x] Keep `CDKClient` (already stateless)
- [x] Keep types: `DeploymentProgress`, `StackStatus`, `CloudFormationStackEvent`
- [x] Keep `CDKOutputParser`, `CDKProgressAccumulator` (stateless parsing utilities)
- [x] Move `DeploymentState` to sdk-aws as a type (no state machine, just the enum)

**Goal**: sdk-aws contains only stateless clients and types.

**Files Modified**:
- `Sources/sdk-aws/CloudFormation/DeploymentMonitor.swift` → **Deleted** (state machine was not used; CDKInfrastructureQueryService has its own implementation)
- `Sources/sdk-aws/CloudFormation/DeploymentState.swift` → **Kept** (just the enum type)
- `Sources/sdk-aws/CDK/CDKOutputParser.swift` → **Created** (moved CDKOutputParser, CDKResourceEvent, CDKProgressAccumulator, CDKProgressSnapshot from DeploymentMonitor.swift)

**Technical Notes**:
- `DeploymentMonitor` was never actually used in the codebase - only referenced in documentation
- `CDKInfrastructureQueryService` already had its own complete state machine implementation
- The parsing utilities (`CDKOutputParser`, `CDKProgressAccumulator`) were moved to a new file in `sdk-aws/CDK/` since they are stateless and reusable

### Phase 2: Create Clean RemoteDeploymentService in service-deploy ✅ COMPLETED

- [x] Create `RemoteDeploymentService.swift` in service-deploy/CDKService
- [x] Implement state ownership with `AsyncStream<State>` pattern
- [x] Use `CloudFormationClient` for CF queries (via SwiftLambdaInfrastructureService)
- [x] Use `SwiftLambdaCDKService` for deploy/destroy
- [x] Use `SwiftLambdaInfrastructureService` for config detection
- [x] Implement `deploy(withPostgres:withNATGateway:)`, `destroy()`, `refresh()`
- [x] Include progress tracking with `CDKOutputParser` from sdk-aws
- [x] Rename existing stateless `RemoteDeploymentService` to `RemoteDeploymentOrchestrator`
- [x] Update CLI commands to use `RemoteDeploymentOrchestrator`

**Goal**: Single stateful service following MV_Model_Service_State.md pattern.

**Files Created**:
- `Sources/service-deploy/CDKService/RemoteDeploymentService.swift` - New stateful service with AsyncStream<State> pattern

**Files Renamed**:
- `Sources/service-deploy/RemoteDeploymentService/RemoteDeploymentService.swift` → `RemoteDeploymentOrchestrator.swift`

**Files Modified**:
- `Sources/feature-cli/Commands/DeployCommand.swift` - Use RemoteDeploymentOrchestrator
- `Sources/feature-cli/Commands/DeployInitCommand.swift` - Use RemoteDeploymentOrchestrator
- `Sources/feature-cli/Commands/StatusCommand.swift` - Use RemoteDeploymentOrchestrator
- `Sources/feature-cli/Commands/TearDownCommand.swift` - Use RemoteDeploymentOrchestrator
- `Sources/feature-cli/Commands/UpdateLambdaCommand.swift` - Use RemoteDeploymentOrchestrator

**Technical Notes**:
- The existing `RemoteDeploymentService` was a stateless orchestrator used by CLI commands
- Renamed it to `RemoteDeploymentOrchestrator` to avoid naming conflict and clarify its role
- New `RemoteDeploymentService` follows the MV pattern with `AsyncStream<State>`
- Uses `StackStatus` directly from sdk-aws instead of the typealias
- CLI commands continue to work with the orchestrator for simple request/response operations
- Mac app can now use the new stateful `RemoteDeploymentService` for UI state observation

**API Summary**:
```swift
/// Stateful service for remote AWS deployments.
/// Owns deployment state and exposes via AsyncStream per MV architecture.
public actor RemoteDeploymentService {

    // MARK: - State (app-specific, includes typed config)

    public enum State: Sendable, Equatable {
        case unknown
        case loading
        case notDeployed
        case deployed(configuration: CDKInfrastructureConfiguration, outputs: CDKStackOutputs)
        case deploying(operation: String, progress: DeploymentProgress, startTime: Date)
        case destroying(progress: DeploymentProgress, startTime: Date)
        case failed(reason: String)
        case credentialExpired(message: String)
    }

    // MARK: - Dependencies (stateless)

    private let cdkService: SwiftLambdaCDKService
    private let infrastructureService: SwiftLambdaInfrastructureService

    // MARK: - State Machine

    private var state: State = .unknown
    private var continuations: [UUID: AsyncStream<State>.Continuation] = [:]

    public func states() -> AsyncStream<State> {
        // Standard pattern from MV_Model_Service_State.md
    }

    // MARK: - Operations

    public func refresh() async { ... }

    public func deploy(withPostgres: Bool, withNATGateway: Bool, output: CLIOutputStream?) async { ... }

    public func destroy(output: CLIOutputStream?) async { ... }
}
```

### Phase 3: Update RemoteModel to Use RemoteDeploymentService ✅ COMPLETED

- [x] Update `RemoteModel.swift` to observe `RemoteDeploymentService.states()`
- [x] Remove direct sdk-aws observation (via CDKInfrastructureQueryService)
- [x] Keep thin model pattern (delegate to service)
- [x] Update `CDKInfrastructureSectionView` to use `RemoteDeploymentService.State`

**Goal**: Feature layer observes service layer, not SDK layer.

**Pattern**:
```swift
@MainActor @Observable
class RemoteModel {
    private let deploymentService: RemoteDeploymentService

    private(set) var state: RemoteDeploymentService.State = .unknown

    private func startObserving() async {
        for await state in await deploymentService.states() {
            self.state = state
        }
    }

    func deploy(withPostgres: Bool, withNATGateway: Bool) {
        Task { await deploymentService.deploy(withPostgres: withPostgres, withNATGateway: withNATGateway, output: nil) }
    }
}
```

**Files Modified**:
- `Sources/feature-mac/Models/RemoteModel.swift` - Use RemoteDeploymentService instead of CDKInfrastructureQueryService
- `Sources/feature-mac/RemoteService/CDKInfrastructureSectionView.swift` - Use RemoteDeploymentService.State

**Technical Notes**:
- The state enum is identical between `CDKInfrastructureQueryService.State` and `RemoteDeploymentService.State`, making the migration straightforward
- `RemoteModel` now delegates all CDK operations to `RemoteDeploymentService`
- The thin model pattern is preserved - `RemoteModel` just bridges async streams to @Observable for SwiftUI
- `CDKInfrastructureSectionView` continues to work unchanged since the State enums have identical structure

### Phase 4: Update CLI Commands ✅ COMPLETED

- [x] Update CLI commands to use `RemoteDeploymentService`
- [x] CLI can call service directly (no model needed)
- [x] Add convenience initializer to `RemoteDeploymentService` for CLI use (creates its own CLIClient)
- [x] Add `getComprehensiveStatus()` method for StatusCommand
- [x] Add `updateLambdaCode()` method for UpdateLambdaCommand
- [x] Add `deployInit()` method for DeployInitCommand with safety checks

**Goal**: CLI commands use `RemoteDeploymentService` directly, consolidating all deployment logic.

**Files Modified**:
- `Sources/feature-cli/Commands/DeployCommand.swift` - Use RemoteDeploymentService
- `Sources/feature-cli/Commands/DeployInitCommand.swift` - Use RemoteDeploymentService
- `Sources/feature-cli/Commands/StatusCommand.swift` - Use RemoteDeploymentService
- `Sources/feature-cli/Commands/TearDownCommand.swift` - Use RemoteDeploymentService
- `Sources/feature-cli/Commands/UpdateLambdaCommand.swift` - Use RemoteDeploymentService
- `Sources/service-deploy/CDKService/RemoteDeploymentService.swift` - Added CLI-focused methods

**Technical Notes**:
- Removed `sdk_cli` import from CLI commands to avoid macro conflicts with ArgumentParser (`@Flag`/`@Option` collision)
- Added convenience initializer to `RemoteDeploymentService` that creates its own `CLIClient`
- Added `ComprehensiveStatus` struct and `getComprehensiveStatus()` for full git/GitHub/stack status
- Added `updateLambdaCode(skipPush:)` for GitHub Actions integration
- Added `deployInit(withPostgres:withNATGateway:skipPush:)` with safety checks for database deletion
- `RemoteDeploymentOrchestrator` is now legacy - CLI commands use `RemoteDeploymentService` directly

**API Additions to RemoteDeploymentService**:
```swift
// Convenience initializer (creates own CLIClient)
public init(
    projectRoot: String,
    awsConfig: AWSAuthConfiguration,
    cdkDirectory: String = CDKStackConfiguration.defaultCDKDirectory,
    stackName: String = CDKStackConfiguration.defaultStackName
)

// CLI-focused methods
public func deployInit(withPostgres: Bool, withNATGateway: Bool, skipPush: Bool) async throws
public func updateLambdaCode(skipPush: Bool) async throws
public func getComprehensiveStatus() async throws -> ComprehensiveStatus
public func getCurrentState() -> State
public func getAPIGatewayURL() -> String?
public func testEndpoints() async throws
```

### Phase 5: Delete Redundant Code ✅ COMPLETED

- [x] Delete `CDKInfrastructureQueryService.swift`
- [x] Delete `CDKOutputParser.swift` from service-deploy (use sdk-aws version)
- [x] Delete `CloudFormationStackStatusValues.swift` typealias
- [x] Verify build succeeds

**Files Deleted**:
- `Sources/service-deploy/CDKService/CDKInfrastructureQueryService.swift`
- `Sources/service-deploy/CDKService/CDKOutputParser.swift`
- `Sources/service-deploy/CDKService/Models/CloudFormationStackStatusValues.swift`

**Files Modified**:
- `Sources/service-deploy/RemoteDeploymentService/RemoteDeploymentOrchestrator.swift` - Updated comment to reference `RemoteDeploymentService` instead of `CDKInfrastructureQueryService`

**Technical Notes**:
- The service-deploy `CDKOutputParser.swift` was a duplicate of the sdk-aws version and was not being used
- `CloudFormationStackStatusValues` was a typealias only used within `CDKInfrastructureQueryService`
- Build verified successful after deletion
- CLI commands continue to work correctly with `RemoteDeploymentService`

### Phase 6: Update Architecture Documentation ✅ COMPLETED

- [x] Update `MV_Model_Service_State.md` reference implementation section
- [x] Replace `CDKInfrastructureQueryService` reference with `RemoteDeploymentService`
- [x] Verify compliance checklist still accurate

**Files Modified**:
- `docs/architecture/MV_Model_Service_State.md`

**Technical Notes**:
- Updated reference implementation to point to `RemoteDeploymentService` and `RemoteModel`
- Added explicit file locations for easy navigation
- Updated all line numbers in compliance checklist to match current implementation
- Renamed section from "CDKInfrastructureQueryService Compliance" to "RemoteDeploymentService Compliance"
- Changed "Issues Addressed" to "Design Decisions" since these are now intentional features, not fixes
- Build verified successful

### Phase 7: Final Verification ✅ COMPLETED

- [x] Verify sdk-aws is fully stateless (no actors with state)
- [x] Verify service-deploy owns all deployment state
- [x] Verify feature layer only observes services
- [x] Run all tests
- [x] Final build verification

**Verification Results**:

1. **sdk-aws Stateless**: Confirmed. All actors in sdk-aws (`CloudFormationClient`, `LambdaClient`, `S3Client`, `CloudWatchLogsClient`, `CDKClient`, `SecretsManagerClient`) are stateless wrappers. `CloudWatchLogsClient` has a `streamTask` for managing streaming operations, but this is acceptable - it doesn't have a state machine with `AsyncStream<State>` for broadcasting state changes to multiple observers.

2. **service-deploy State Ownership**: Confirmed. `RemoteDeploymentService` is the single owner of deployment state with:
   - `private var state: State`
   - `private var continuations: [UUID: AsyncStream<State>.Continuation]`
   - `func states() -> AsyncStream<State>`

3. **Feature Layer Observes Services**: Confirmed. `RemoteModel` in feature-mac:
   - Observes `RemoteDeploymentService.states()` via `startObservingCDKState()`
   - Stores state in `cdkState: RemoteDeploymentService.State`
   - Delegates all CDK operations to `remoteDeploymentService`
   - `sdk_aws` imports are only for types (e.g., `AWSAuthConfiguration`, `CloudFormationClient`), not for state observation

4. **Tests**: All unit tests pass (357/358). One integration test (`LinuxDeployTests`) has a pre-existing route mismatch (`/api/file` vs `/api/files`) unrelated to this refactoring.

5. **Build**: Verified successful. CLI commands work correctly with `RemoteDeploymentService`.

## Migration Notes

### State Enum Location

The app-specific `State` enum moves from `CDKInfrastructureQueryService` to `RemoteDeploymentService`. Same cases, same pattern.

### What Stays in sdk-aws (Stateless)

- `CloudFormationClient` - stateless queries
- `CDKClient` - stateless CDK operations
- `DeploymentProgress`, `ResourceProgress` - value types
- `StackStatus` - enum of CF status strings
- `CDKOutputParser`, `CDKProgressAccumulator` - stateless parsing
- `CloudFormationStackEvent`, `CloudFormationStackResource` - data types

### What Moves to service-deploy (Stateful)

- State machine (from `DeploymentMonitor`)
- `AsyncStream<State>` pattern
- Polling/monitoring logic
- Progress tracking coordination

### What Gets Deleted

- `CDKInfrastructureQueryService` (replaced by `RemoteDeploymentService`)
- `DeploymentMonitor` actor (state machine moves to service)

## Benefits

1. **Proper Layer Separation**: SDKs are stateless, services own state
2. **Single Source of Truth**: One stateful service for remote deployments
3. **Architecture Compliance**: Follows MV_Model_Service_State.md pattern exactly
4. **Reusable SDKs**: `CloudFormationClient`, `CDKClient` can be used by any project
5. **Testable**: Services can mock SDK clients
6. **Less Duplication**: ~400 lines removed (both DeploymentMonitor and CDKInfrastructureQueryService)

## File Impact Summary

| File | Action | Status |
|------|--------|--------|
| `sdk-aws/CloudFormation/DeploymentMonitor.swift` | **Delete** | ✅ Done |
| `sdk-aws/CloudFormation/DeploymentState.swift` | Keep (type only) | ✅ Done |
| `sdk-aws/CloudFormation/CloudFormationClient.swift` | Keep (stateless) | ✅ Done |
| `sdk-aws/CDK/CDKClient.swift` | Keep (stateless) | ✅ Done |
| `sdk-aws/CDK/CDKOutputParser.swift` | **Create** (parsing utilities) | ✅ Done |
| `service-deploy/CDKService/RemoteDeploymentService.swift` | **Create** | ✅ Done |
| `service-deploy/RemoteDeploymentService/RemoteDeploymentOrchestrator.swift` | **Rename** (from RemoteDeploymentService.swift) | ✅ Done |
| `feature-cli/Commands/*.swift` | **Update** (use RemoteDeploymentService) | ✅ Done |
| `feature-mac/Models/RemoteModel.swift` | **Update** (use RemoteDeploymentService) | ✅ Done |
| `feature-mac/RemoteService/CDKInfrastructureSectionView.swift` | **Update** (use RemoteDeploymentService.State) | ✅ Done |
| `service-deploy/CDKService/CDKInfrastructureQueryService.swift` | **Delete** | ✅ Done |
| `service-deploy/CDKService/CDKOutputParser.swift` | **Delete** | ✅ Done |
| `service-deploy/CDKService/Models/CloudFormationStackStatusValues.swift` | **Delete** | ✅ Done |
| `service-deploy/CDKService/SwiftLambdaInfrastructureService.swift` | Keep | - |
| `service-deploy/CDKService/SwiftLambdaCDKService.swift` | Keep | - |
| `docs/architecture/MV_Model_Service_State.md` | Update reference | ✅ Done |
