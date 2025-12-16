# Type Harmonization: DeployOptions, Progress, and Infrastructure Configuration

## Goal

Clean up type duplication and string-based enums in the deployment architecture:

1. **Remove duplicate DeployOptions** - App layer should use workflow types directly
2. **Unify infrastructure shape types** - Single type for desired and detected state
3. **Replace string operations with enums** - Type-safe operation names
4. **Clarify progress type roles** - Document why each exists

## Current Problems

### Problem 1: DeployOptions Duplication

Three nearly-identical types form a conversion chain:

```
DeploymentModel.DeployOptions (app-mac)
        ↓ toWorkflowOptions()
DeployWorkflow.Options (service-deploy)
        ↓ toCDKOptions()
CDKClient.DeployOptions (sdk-aws)
```

**Issues:**
- `DeploymentModel.DeployOptions` duplicates `DeployWorkflow.Options` verbatim
- App layer redefines service layer types unnecessarily
- Violates architecture: app layer should consume service types, not duplicate them

### Problem 2: String-Based Operation Names

```swift
// CloudFormationState.swift (sdk-aws)
case deploying(operation: String, progress: DeploymentProgress, startTime: Date)

// DeploymentModel.swift (app-mac)
deploymentState = .deploying(operation: "Building", progress: ..., startTime: ...)
deploymentState = .deploying(operation: "Deploying", progress: ..., startTime: ...)
deploymentState = .deploying(operation: "Monitoring", progress: ..., startTime: ...)
```

**Issues:**
- Magic strings prone to typos
- `DeployWorkflow.Progress.Step` already defines these as enum cases
- No compile-time safety

### Problem 3: Overlapping Infrastructure Types

```swift
// DeployWorkflow.Options (service-deploy) - DESIRED state
struct Options {
    let withPostgres: Bool
    let withNATGateway: Bool
}

// CDKInfrastructureConfiguration (service-deploy) - DETECTED state
struct CDKInfrastructureConfiguration {
    let hasDatabase: Bool
    let hasNATGateway: Bool
    let hasVPC: Bool
}
```

**Issues:**
- Same concept with different field names (`withPostgres` vs `hasDatabase`)
- Conversion between them is implicit in `updateInfrastructure()`
- Could share a common shape type

### Problem 4: Progress Type Proliferation (Justified but Undocumented)

Four progress-related types exist across layers:

| Type | Layer | Purpose |
|------|-------|---------|
| `DeploymentProgress` | sdk-aws | CloudFormation resource-level tracking |
| `CloudFormationState` | sdk-aws | High-level CF state machine |
| `DeployWorkflow.Progress` | service-deploy | Workflow step tracking |
| `ActiveWorkflow` | app-mac | Which workflow is running |

These are architecturally correct but the relationships aren't documented.

---

## Phase 1: Delete DeploymentModel.DeployOptions

**Goal:** App layer uses `DeployWorkflow.Options` directly.

**Files:**
- Modify: `Sources/app-mac/Models/DeploymentModel.swift`

**Changes:**

Remove the nested `DeployOptions` struct entirely:

```swift
// DELETE this entire struct
public struct DeployOptions: Sendable {
    public let withPostgres: Bool
    public let withNATGateway: Bool
    public let requireApproval: Bool
    // ...
}
```

Update method signatures to use workflow options:

```swift
// Before
public func deploy(options: DeployOptions, output: CLIOutputStream? = nil) async

// After
public func deploy(options: DeployWorkflow.Options, output: CLIOutputStream? = nil) async
```

Update `updateInfrastructure()`:

```swift
// Before
let options = DeployOptions(withPostgres: hasDatabase, withNATGateway: hasNATGateway)
await deploy(options: options, output: output)

// After
let options = DeployWorkflow.Options(withPostgres: hasDatabase, withNATGateway: hasNATGateway)
await deploy(options: options, output: output)
```

**Verification:** Build succeeds. No behavioral change.

---

## Phase 2: Add Operation Enum to CloudFormationState

**Goal:** Replace string-based operation names with enum.

**Files:**
- Modify: `Sources/sdk-aws/CloudFormation/CloudFormationState.swift`
- Modify: `Sources/app-mac/Models/DeploymentModel.swift`

**Changes:**

Add `DeployOperation` enum to CloudFormationState:

```swift
public enum CloudFormationState: Sendable, Equatable {
    /// Operations that can occur during deployment
    public enum DeployOperation: String, Sendable, Equatable {
        case building = "Building"
        case deploying = "Deploying"
        case monitoring = "Monitoring"
    }

    case deploying(operation: DeployOperation, progress: DeploymentProgress, startTime: Date)
    // ... other cases unchanged
}
```

Update DeploymentModel to use enum:

```swift
// Before
deploymentState = .deploying(operation: "Building", progress: DeploymentProgress(), startTime: ...)

// After
deploymentState = .deploying(operation: .building, progress: DeploymentProgress(), startTime: ...)
```

Update `operationName` computed property:

```swift
// Before
public var operationName: String? {
    if case .deploying(let operation, _, _) = self {
        return operation
    }
    return nil
}

// After
public var operationName: String? {
    if case .deploying(let operation, _, _) = self {
        return operation.rawValue
    }
    return nil
}
```

**Verification:** Build succeeds. UI displays same strings via `rawValue`.

---

## Phase 3: Create Unified InfrastructureShape Type

**Goal:** Single type for both desired and detected infrastructure configuration.

**Files:**
- Create: `Sources/service-deploy/Models/InfrastructureShape.swift`
- Modify: `Sources/service-deploy/Models/CDKInfrastructureConfiguration.swift`
- Modify: `Sources/service-deploy/Workflows/DeployWorkflow.swift`
- Modify: `Sources/app-mac/Models/DeploymentModel.swift`

**Changes:**

Create new unified type:

```swift
// Sources/service-deploy/Models/InfrastructureShape.swift
import Foundation

/// Represents infrastructure configuration shape.
/// Used for both desired state (what to deploy) and detected state (what's deployed).
public struct InfrastructureShape: Sendable, Equatable {
    public let hasDatabase: Bool
    public let hasNATGateway: Bool

    public init(hasDatabase: Bool = false, hasNATGateway: Bool = false) {
        self.hasDatabase = hasDatabase
        self.hasNATGateway = hasNATGateway
    }

    public static var minimal: InfrastructureShape {
        InfrastructureShape(hasDatabase: false, hasNATGateway: false)
    }

    public static var full: InfrastructureShape {
        InfrastructureShape(hasDatabase: true, hasNATGateway: true)
    }
}
```

Update `DeployWorkflow.Options` to use it:

```swift
public struct Options: Sendable {
    public let infrastructure: InfrastructureShape
    public let requireApproval: Bool

    public init(
        infrastructure: InfrastructureShape = .minimal,
        requireApproval: Bool = false
    ) {
        self.infrastructure = infrastructure
        self.requireApproval = requireApproval
    }

    // Convenience initializers for backward compatibility
    public init(
        withPostgres: Bool = false,
        withNATGateway: Bool = false,
        requireApproval: Bool = false
    ) {
        self.infrastructure = InfrastructureShape(
            hasDatabase: withPostgres,
            hasNATGateway: withNATGateway
        )
        self.requireApproval = requireApproval
    }

    func toCDKOptions() -> CDKClient.DeployOptions {
        var context: [String: String] = [:]
        if !infrastructure.hasDatabase {
            context["skipPostgres"] = "true"
        }
        if !infrastructure.hasNATGateway {
            context["skipNATGateway"] = "true"
        }
        return CDKClient.DeployOptions(
            stackName: nil,
            context: context,
            requireApproval: requireApproval,
            outputsFile: nil
        )
    }
}
```

Simplify `CDKInfrastructureConfiguration` to extend `InfrastructureShape`:

```swift
// Sources/service-deploy/Models/CDKInfrastructureConfiguration.swift
import Foundation

/// Detected infrastructure configuration from CloudFormation.
/// Extends InfrastructureShape with additional detected properties.
public struct CDKInfrastructureConfiguration: Equatable, Sendable {
    /// Core infrastructure shape (matches desired state type)
    public let shape: InfrastructureShape

    /// Whether VPC was detected (detection-only, not a deployment option)
    public let hasVPC: Bool

    // Convenience accessors
    public var hasDatabase: Bool { shape.hasDatabase }
    public var hasNATGateway: Bool { shape.hasNATGateway }

    public init(hasDatabase: Bool = false, hasNATGateway: Bool = false, hasVPC: Bool = false) {
        self.shape = InfrastructureShape(hasDatabase: hasDatabase, hasNATGateway: hasNATGateway)
        self.hasVPC = hasVPC
    }
}
```

Update `DeploymentModel.updateInfrastructure()`:

```swift
// Before
public func updateInfrastructure(output: CLIOutputStream? = nil) async {
    let hasDatabase = infrastructureConfiguration?.hasDatabase ?? false
    let hasNATGateway = infrastructureConfiguration?.hasNATGateway ?? false
    let options = DeployWorkflow.Options(withPostgres: hasDatabase, withNATGateway: hasNATGateway)
    await deploy(options: options, output: output)
}

// After
public func updateInfrastructure(output: CLIOutputStream? = nil) async {
    let shape = infrastructureConfiguration?.shape ?? .minimal
    let options = DeployWorkflow.Options(infrastructure: shape)
    await deploy(options: options, output: output)
}
```

**Verification:** Build succeeds. No behavioral change.

---

## Phase 4: Document Progress Type Hierarchy

**Goal:** Add documentation explaining why each progress type exists.

**Files:**
- Modify: `Sources/sdk-aws/CloudFormation/DeploymentProgress.swift`
- Modify: `Sources/sdk-aws/CloudFormation/CloudFormationState.swift`
- Modify: `Sources/service-deploy/Workflows/DeployWorkflow.swift`

**Changes:**

Add header documentation to each file:

```swift
// DeploymentProgress.swift
/// Resource-level progress during CloudFormation operations.
///
/// This is the SDK-layer progress type that tracks individual AWS resource
/// creation/update/deletion. It's used by:
/// - `CloudFormationState.deploying` and `.destroying` cases
/// - `DeployWorkflow.Progress.Detail.cdk` for detailed resource status
///
/// Hierarchy:
/// ```
/// DeploymentProgress (sdk) - individual resources
///     └── embedded in CloudFormationState (sdk) - stack lifecycle
///         └── consumed by DeployWorkflow.Progress (service) - workflow steps
///             └── consumed by ActiveWorkflow (app) - UI state
/// ```

// CloudFormationState.swift
/// High-level state machine for CloudFormation stack lifecycle.
///
/// This is the SDK-layer state type representing the overall stack status.
/// It embeds `DeploymentProgress` for resource-level details during operations.
///
/// Used by:
/// - `CloudFormationClient.queryState()` return type
/// - `CloudFormationClient.monitorStream()` yields
/// - `DeploymentModel.deploymentState` for stable state display

// DeployWorkflow.swift (Progress struct)
/// Progress updates from the deploy workflow.
///
/// This is the service-layer progress type that tracks workflow phases:
/// building → deploying → monitoring → complete
///
/// The `Detail` enum wraps SDK-layer progress (`DeploymentProgress`) and
/// adds workflow-specific context like final outputs and configuration.
///
/// Consumed by:
/// - CLI commands (print progress directly)
/// - `DeploymentModel.activeWorkflow` (UI binding)
```

**Verification:** Documentation renders correctly.

---

## Summary of Changes

| Phase | Change | Breaking? |
|-------|--------|-----------|
| 1 | Delete `DeploymentModel.DeployOptions` | No (internal) |
| 2 | Add `CloudFormationState.DeployOperation` enum | No |
| 3 | Create `InfrastructureShape`, refactor Options | No |
| 4 | Add documentation | No |

## Execution Order

Phases are independent and can be done in any order. Recommended:
1. Phase 2 first (quick win, improves type safety)
2. Phase 1 second (removes dead code)
3. Phase 3 third (largest change, most value)
4. Phase 4 last (documentation)

## Files Affected

| File | Phases |
|------|--------|
| `Sources/sdk-aws/CloudFormation/CloudFormationState.swift` | 2, 4 |
| `Sources/sdk-aws/CloudFormation/DeploymentProgress.swift` | 4 |
| `Sources/service-deploy/Models/InfrastructureShape.swift` | 3 (new) |
| `Sources/service-deploy/Models/CDKInfrastructureConfiguration.swift` | 3 |
| `Sources/service-deploy/Workflows/DeployWorkflow.swift` | 3, 4 |
| `Sources/app-mac/Models/DeploymentModel.swift` | 1, 2, 3 |
