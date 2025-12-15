# Proposal: Extract Generic AWS/CDK Code to sdk-aws

## Overview

This proposal outlines extracting generic AWS and CDK functionality from `service-deploy` into a new `sdk-aws` layer. The goal is to create a reusable SDK that could work for any CDK project, while keeping app-specific configuration (like `withNATGateway`, `withPostgres`) in the service layer.

## Guiding Principle

**sdk-aws** should contain:
- Generic AWS CLI wrappers (parameterized, no hardcoded values)
- Generic CDK CLI wrappers (deploy, destroy, diff, etc.)
- Generic state machines for tracking deployments
- Generic CloudFormation querying
- AWS authentication/credential management

**service-deploy** should retain:
- App-specific configuration flags (`withPostgres`, `withNATGateway`)
- App-specific stack names and output key parsing
- App-specific infrastructure detection logic
- App-specific testing endpoints
- Business logic that orchestrates the SDK

## Current State Analysis

### Files to Move (Generic)

| Current Location | Proposed sdk-aws Location | Notes |
|------------------|---------------------------|-------|
| `CDKService/CLI/Cdk.swift` | `sdk-aws/CDK/CLI/CDKCommand.swift` | CDK CLI command builder |
| `CDKService/CLI/Npm.swift` | `sdk-aws/CDK/CLI/NpmCommand.swift` | npm CLI command builder |
| `CDKService/CDKService.swift` | `sdk-aws/CDK/CDKService.swift` | Core CDK operations (needs refactor) |
| `AWSService/CLI/Aws.swift` | `sdk-aws/AWS/CLI/AWSCommand.swift` | AWS CLI command builder |
| `AWSService/AWSCLIService.swift` | `sdk-aws/AWS/AWSCLIService.swift` | AWS CLI wrapper (needs refactor) |
| `AWSService/AWSAuthConfiguration.swift` | `sdk-aws/Auth/AWSAuthConfiguration.swift` | Profile configuration |
| `AWSService/AWSVaultService.swift` | `sdk-aws/Auth/AWSVaultService.swift` | aws-vault integration |
| `AWSService/CloudWatchLogsService.swift` | `sdk-aws/CloudWatch/CloudWatchLogsService.swift` | Log streaming (remove default Lambda name) |

### Files to Keep in service-deploy (App-Specific)

| File | Reason |
|------|--------|
| `CDKService/Models/CDKStackOutputs.swift` | Hardcoded output keys (ApiGatewayUrl, LambdaFunctionName, etc.) |
| `CDKService/Models/CDKStackConfiguration.swift` | App-specific stack configuration |
| `CDKService/CDKInfrastructureQueryService.swift` | Detection logic for Postgres/NAT is app-specific |
| `CDKService/CDKOutputParser.swift` | Parses app-specific CDK output format |
| `AWSService/AWSTestingService.swift` | Hardcoded endpoint paths and stack names |
| `RemoteDeploymentService/` | Orchestrates app-specific deployment workflow |

### Files That Need Splitting

| File | Generic Part → sdk-aws | App-Specific Part → stays |
|------|------------------------|---------------------------|
| `CDKService/CDKService.swift` | `deploy()`, `destroy()`, `diff()`, `build()` methods | Context configuration, stack name handling |
| `CDKInfrastructureQueryService.swift` | State machine, event polling | Resource detection (hasDatabase, hasNATGateway) |
| `CDKService/Models/DeploymentConfiguration.swift` | AWS profile, CDK directory | `skipPostgres`, `skipNATGateway` flags |

---

## Proposed sdk-aws Structure

```
Sources/sdk-aws/
├── Auth/
│   ├── AWSAuthConfiguration.swift      # Profile configuration model
│   ├── AWSVaultService.swift           # aws-vault credential wrapper
│   └── AWSCredentialProvider.swift     # Protocol for credential strategies
│
├── CLI/
│   ├── AWSCommand.swift                # AWS CLI command builder
│   ├── CDKCommand.swift                # CDK CLI command builder
│   └── NpmCommand.swift                # npm CLI command builder
│
├── Services/
│   ├── AWSCLIService.swift             # Generic AWS CLI operations
│   ├── CDKService.swift                # Generic CDK operations
│   └── CloudWatchLogsService.swift     # Generic log streaming
│
├── CloudFormation/
│   ├── CloudFormationService.swift     # Stack operations
│   ├── StackStatus.swift               # Status enum
│   ├── StackEvent.swift                # Event model
│   └── StackOutput.swift               # Generic output model
│
├── State/
│   ├── DeploymentState.swift           # Generic deployment state enum
│   ├── DeploymentProgress.swift        # Progress tracking model
│   └── DeploymentMonitor.swift         # State machine for tracking deployments
│
└── Models/
    ├── AWSRegion.swift                 # Region enum
    └── AWSError.swift                  # Error types
```

---

## Detailed Changes

### 1. Generic CDK Service (sdk-aws)

```swift
// sdk-aws/Services/CDKService.swift
public actor CDKService {
    private let cliService: CLIService
    private let credentialProvider: AWSCredentialProvider
    private let workingDirectory: String

    public struct DeployOptions: Sendable {
        public let stackName: String?
        public let context: [String: String]
        public let requireApproval: Bool
        public let outputsFile: String?

        public init(
            stackName: String? = nil,
            context: [String: String] = [:],
            requireApproval: Bool = false,
            outputsFile: String? = nil
        ) { ... }
    }

    public func deploy(options: DeployOptions = .init()) async throws -> CDKDeployResult
    public func destroy(stackName: String?, force: Bool) async throws
    public func diff(stackName: String?) async throws -> String
    public func build() async throws
    public func bootstrap(region: AWSRegion) async throws
}
```

### 2. App-Specific CDK Configuration (service-deploy)

```swift
// service-deploy/CDKService/SwiftLambdaCDKService.swift
public actor SwiftLambdaCDKService {
    private let cdkService: CDKService  // From sdk-aws

    public struct AppDeployOptions: Sendable {
        public let withPostgres: Bool
        public let withNATGateway: Bool
        public let awsProfile: String

        public init(
            withPostgres: Bool = false,
            withNATGateway: Bool = false,
            awsProfile: String
        ) { ... }
    }

    public func deploy(options: AppDeployOptions) async throws -> SwiftLambdaStackOutputs {
        // Build CDK context from app-specific options
        var context: [String: String] = [:]
        context["skipPostgres"] = String(!options.withPostgres)
        context["skipNATGateway"] = String(!options.withNATGateway)

        // Delegate to generic CDK service
        let result = try await cdkService.deploy(
            options: .init(
                stackName: "SwiftLambdaSampleStack",
                context: context
            )
        )

        // Parse app-specific outputs
        return SwiftLambdaStackOutputs(from: result.outputs)
    }
}
```

### 3. Generic Deployment Monitor (sdk-aws)

```swift
// sdk-aws/State/DeploymentMonitor.swift
public actor DeploymentMonitor {
    public enum State: Sendable {
        case unknown
        case loading
        case notDeployed
        case deploying(progress: DeploymentProgress)
        case deployed(outputs: [String: String])
        case destroying(progress: DeploymentProgress)
        case failed(reason: String)
    }

    private let cloudFormationService: CloudFormationService
    private let stackName: String

    public func states() -> AsyncStream<State>
    public func refresh() async

    // Generic event parsing - no app-specific detection
    private func queryCurrentState() async throws -> State
}
```

### 4. App-Specific Infrastructure Detection (service-deploy)

```swift
// service-deploy/CDKService/SwiftLambdaInfrastructureService.swift
public actor SwiftLambdaInfrastructureService {
    private let monitor: DeploymentMonitor  // From sdk-aws
    private let cloudFormation: CloudFormationService  // From sdk-aws

    public struct InfrastructureConfiguration: Sendable {
        public let hasDatabase: Bool
        public let hasNATGateway: Bool
        public let hasVPC: Bool
    }

    // App-specific detection logic stays here
    public func detectConfiguration() async throws -> InfrastructureConfiguration {
        let resources = try await cloudFormation.describeStackResources(
            stackName: "SwiftLambdaSampleStack"
        )

        return InfrastructureConfiguration(
            hasDatabase: resources.contains {
                $0.logicalId.contains("Database") && $0.type.contains("RDS")
            },
            hasNATGateway: resources.contains {
                $0.type == "AWS::EC2::NatGateway"
            },
            hasVPC: resources.contains {
                $0.type == "AWS::EC2::VPC"
            }
        )
    }
}
```

### 5. Generic CloudFormation Service (sdk-aws)

```swift
// sdk-aws/CloudFormation/CloudFormationService.swift
public actor CloudFormationService {
    private let awsCLI: AWSCLIService

    public func describeStack(name: String) async throws -> StackDescription?
    public func getStackStatus(name: String) async throws -> StackStatus?
    public func getStackOutputs(name: String) async throws -> [String: String]
    public func describeStackResources(name: String) async throws -> [StackResource]
    public func getStackEvents(name: String, limit: Int?) async throws -> [StackEvent]
}

public struct StackResource: Sendable {
    public let logicalId: String
    public let physicalId: String?
    public let type: String
    public let status: String
}

public struct StackEvent: Sendable {
    public let timestamp: Date
    public let logicalId: String
    public let type: String
    public let status: String
    public let reason: String?
}
```

### 6. Generic AWS CLI Service (sdk-aws)

```swift
// sdk-aws/Services/AWSCLIService.swift
public actor AWSCLIService {
    private let cliService: CLIService
    private let credentialProvider: AWSCredentialProvider

    // Generic operations - no hardcoded stack/function names
    public func cloudformation(_ subcommand: String, arguments: [String]) async throws -> String
    public func lambda(_ subcommand: String, arguments: [String]) async throws -> String
    public func s3(_ subcommand: String, arguments: [String]) async throws -> String
    public func secretsmanager(_ subcommand: String, arguments: [String]) async throws -> String
    public func logs(_ subcommand: String, arguments: [String]) async throws -> String
}
```

---

## Dependency Graph After Migration

```
feature-cli ──────────────────┐
feature-mac ──────────────────┼──→ service-deploy ──→ sdk-aws ──→ sdk-cli
feature-lambda ───────────────┘         │
                                        │
                                        ├── SwiftLambdaCDKService
                                        ├── SwiftLambdaInfrastructureService
                                        ├── SwiftLambdaStackOutputs
                                        └── AWSTestingService
```

---

## What Stays App-Specific

### Configuration Flags
```swift
// These stay in service-deploy
withPostgres: Bool
withNATGateway: Bool
```

### Stack Names & Output Keys
```swift
// These stay in service-deploy
let stackName = "SwiftLambdaSampleStack"
let outputKeys = ["ApiGatewayUrl", "LambdaFunctionName", "BucketName"]
```

### Infrastructure Detection Logic
```swift
// This logic stays in service-deploy
hasDatabase = resources.contains { $0.logicalId.contains("Database") }
hasNATGateway = resources.contains { $0.type == "AWS::EC2::NatGateway" }
```

### Testing Endpoints
```swift
// These stay in service-deploy
"/api/files"
"/api/users"
"/api/database"
```

---

## Benefits

1. **Reusability**: `sdk-aws` can be used by other Swift projects that use CDK
2. **Testability**: Generic services are easier to mock
3. **Separation of Concerns**: Clear boundary between infrastructure tooling and app-specific logic
4. **Maintainability**: Changes to AWS CLI/CDK interfaces isolated to sdk-aws
5. **Potential Open Source**: sdk-aws could be extracted as a separate package

---

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Breaking changes during migration | Incremental phases, maintain backwards compatibility |
| Over-abstraction | Keep sdk-aws focused on CLI wrappers, don't abstract business logic |
| Testing complexity | Create integration tests that verify end-to-end deployment still works |
| Circular dependencies | Strict layering: sdk-aws cannot depend on service-deploy |

---

## Open Questions

1. Should `sdk-aws` include models for common AWS resources (Lambda, S3, RDS)?
2. Should `CloudWatchLogsService` support multiple log groups simultaneously?
3. Should the credential provider support IAM roles in addition to profiles and aws-vault?
4. Should there be a separate `sdk-cloudformation` or keep it within `sdk-aws`?

---

## Migration Steps

### Prerequisites

Before starting implementation, review the architecture documentation in `docs/architecture/` for context on the architecture goals in this project:

- `PRINCIPLES.md` - Server development principles
- `layered-architecture.md` - Three-layer architecture (Features → Services → SDKs)
- `MacAppArchitecture.md` - Model-View architecture with services
- `MV_Model_Service_State.md` - State management patterns

### Instructions

**Important: Do one phase at a time.** Complete the phase, verify the build passes, commit, then stop. Do not continue to the next phase until explicitly asked.

After completing each phase:

1. **Build all targets** to ensure nothing is broken:
   ```bash
   swift build
   ```
   The build must succeed (runtime behavior doesn't need to be tested at each step).

2. **Commit the changes** for that phase with a descriptive message:
   ```bash
   git add -A
   git commit -m "Phase N: <description>"
   ```

3. **Stop and report completion.** Do not proceed to the next phase automatically.

This ensures incremental progress is preserved and any issues can be easily bisected.

---

### Phase 1: Create sdk-aws Target ✅

- [x] Create `Sources/sdk-aws/` directory structure
- [x] Add `sdk-aws` target to `Package.swift`
- [x] Add `sdk-cli` as dependency (for CLIService)

### Phase 2: Move Generic CLI Builders ✅

- [x] Move `Cdk.swift` → `sdk-aws/CLI/CDKCommand.swift`
- [x] Move `Npm.swift` → `sdk-aws/CLI/NpmCommand.swift`
- [x] Move `Aws.swift` → `sdk-aws/CLI/AWSCommand.swift`
- [x] Update imports in moved files

### Phase 3: Move Auth Services ✅

- [x] Move `AWSAuthConfiguration.swift` → `sdk-aws/Auth/`
- [x] Move `AWSVaultService.swift` → `sdk-aws/Auth/`
- [x] Create `AWSCredentialProvider` protocol

### Phase 4: Extract Generic Services ✅

- [x] Create `sdk-aws/CloudFormation/CloudFormationService.swift` (extract from AWSCLIService)
- [x] Create `sdk-aws/Services/CDKService.swift` (generic version)
- [x] Move `CloudWatchLogsService.swift` → `sdk-aws/CloudWatch/` (remove default Lambda name)

### Phase 5: Create Generic State Machine ✅

- [x] Create `sdk-aws/State/DeploymentState.swift`
- [x] Create `sdk-aws/State/DeploymentProgress.swift`
- [x] Create `sdk-aws/State/DeploymentMonitor.swift`
- [x] Extract generic state machine from `CDKInfrastructureQueryService`
- [x] Update service-deploy to use typealiases for generic types

### Phase 6: Refactor service-deploy

- [ ] Create `SwiftLambdaCDKService.swift` (app-specific wrapper)
- [ ] Create `SwiftLambdaInfrastructureService.swift` (app-specific detection)
- [ ] Update `RemoteDeploymentService` to use new services
- [ ] Keep `CDKStackOutputs.swift` and `AWSTestingService.swift` as-is

### Phase 7: Update Imports

- [ ] Update `service-deploy` to import `sdk-aws`
- [ ] Update `feature-cli` imports if needed
- [ ] Update `feature-mac` imports if needed
