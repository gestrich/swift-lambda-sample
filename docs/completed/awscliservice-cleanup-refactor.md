# Proposal: AWSCLIService Cleanup Refactor

## Overview

This proposal outlines refactoring `AWSCLIService` in `service-deploy` to remove duplication and move remaining generic AWS operations to `sdk-aws`. Despite the previous migration (see `move-aws-to-sdk.md`), `AWSCLIService` still contains:

1. **Duplicated CloudFormation operations** - Already exist in `CloudFormationClient` in sdk-aws
2. **Generic Lambda operations** - Should be in a new `LambdaClient`
3. **Generic S3 operations** - Should be in a new `S3Client`
4. **Generic Secrets Manager operations** - Should be in a new `SecretsManagerClient`
5. **Duplicated command execution infrastructure** - Same pattern as sdk-aws clients

## Current State Analysis

### AWSCLIService Methods (service-deploy)

| Method | Status | Action |
|--------|--------|--------|
| `describeStack(name:)` | DUPLICATE | Remove (use CloudFormationClient) |
| `getStackStatus(name:)` | DUPLICATE | Remove (use CloudFormationClient) |
| `getStackOutputs(name:)` | DUPLICATE | Remove (use CloudFormationClient) |
| `getStackOutput(stackName:outputKey:)` | DUPLICATE | Remove (use CloudFormationClient) |
| `describeStackResources(name:)` | DUPLICATE | Remove (use CloudFormationClient) |
| `getStackEvents(name:limit:)` | DUPLICATE | Remove (use CloudFormationClient) |
| `updateLambdaCode(functionName:zipFile:output:)` | GENERIC | Move to new `LambdaClient` |
| `getLambdaFunction(name:)` | GENERIC | Move to new `LambdaClient` |
| `tailLogs(logGroup:since:format:follow:output:)` | DUPLICATE | Remove (use CloudWatchLogsClient) |
| `s3List(bucket:prefix:)` | GENERIC | Move to new `S3Client` |
| `s3Copy(source:destination:)` | GENERIC | Move to new `S3Client` |
| `getSecretValue(secretId:)` | GENERIC | Move to new `SecretsManagerClient` |
| `listSecrets()` | GENERIC | Move to new `SecretsManagerClient` |

### Existing sdk-aws Clients

Already in sdk-aws:
- `CloudFormationClient` - Stack operations
- `CloudWatchLogsClient` - Log streaming
- `CDKClient` - CDK deployment operations

Missing from sdk-aws:
- `LambdaClient` - Lambda function operations
- `S3Client` - S3 bucket operations
- `SecretsManagerClient` - Secrets operations

---

## Proposed Changes

### New sdk-aws Clients

#### 1. LambdaClient

```swift
// Sources/sdk-aws/Lambda/LambdaClient.swift
public actor LambdaClient {
    private let cliClient: CLIClient
    private let credentialProvider: AWSCredentialProvider

    public init(
        credentialProvider: AWSCredentialProvider,
        cliClient: CLIClient
    )

    /// Update Lambda function code from a zip file
    public func updateFunctionCode(
        functionName: String,
        zipFile: String,
        output: CLIOutputStream? = nil
    ) async throws

    /// Get Lambda function configuration
    public func getFunction(name: String) async throws -> LambdaFunction

    /// Check if a Lambda function exists
    public func functionExists(name: String) async throws -> Bool
}

public struct LambdaFunction: Sendable {
    public let functionName: String
    public let functionArn: String
    public let runtime: String?
    public let handler: String?
    public let codeSize: Int64?
    public let lastModified: String?
}

public enum LambdaError: LocalizedError {
    case commandFailed(command: String, exitCode: Int32, output: String)
    case parseError(String)
    case functionNotFound(String)
}
```

#### 2. S3Client

```swift
// Sources/sdk-aws/S3/S3Client.swift
public actor S3Client {
    private let cliClient: CLIClient
    private let credentialProvider: AWSCredentialProvider

    public init(
        credentialProvider: AWSCredentialProvider,
        cliClient: CLIClient
    )

    /// List objects in an S3 bucket
    public func list(bucket: String, prefix: String = "") async throws -> [S3Object]

    /// Copy a file from S3 to local or stdout
    public func copy(source: String, destination: String) async throws -> String

    /// Check if an object exists
    public func objectExists(bucket: String, key: String) async throws -> Bool
}

public struct S3Object: Sendable {
    public let key: String
    public let size: Int64?
    public let lastModified: Date?
}

public enum S3Error: LocalizedError {
    case commandFailed(command: String, exitCode: Int32, output: String)
    case parseError(String)
    case objectNotFound(bucket: String, key: String)
}
```

#### 3. SecretsManagerClient

```swift
// Sources/sdk-aws/SecretsManager/SecretsManagerClient.swift
public actor SecretsManagerClient {
    private let cliClient: CLIClient
    private let credentialProvider: AWSCredentialProvider

    public init(
        credentialProvider: AWSCredentialProvider,
        cliClient: CLIClient
    )

    /// Get a secret value by ID
    public func getSecretValue(secretId: String) async throws -> String

    /// Get a secret as parsed JSON
    public func getSecretJSON(secretId: String) async throws -> [String: Any]

    /// List all secrets
    public func listSecrets() async throws -> [SecretInfo]
}

public struct SecretInfo: Sendable {
    public let name: String
    public let arn: String
    public let description: String?
    public let lastChangedDate: Date?
}

public enum SecretsManagerError: LocalizedError {
    case commandFailed(command: String, exitCode: Int32, output: String)
    case parseError(String)
    case secretNotFound(String)
}
```

### Updated sdk-aws Structure

```
Sources/sdk-aws/
├── Auth/
│   ├── AWSAuthConfiguration.swift
│   ├── AWSCredentialProvider.swift
│   └── AWSVaultClient.swift
│
├── CLI/
│   ├── AWSCommand.swift              # AWS CLI command definitions
│   ├── CDKCommand.swift
│   └── NpmCommand.swift
│
├── CDK/
│   └── CDKClient.swift
│
├── CloudFormation/
│   ├── CloudFormationClient.swift    # (existing)
│   ├── DeploymentMonitor.swift
│   ├── DeploymentProgress.swift
│   └── DeploymentState.swift
│
├── CloudWatch/
│   └── CloudWatchLogsClient.swift    # (existing)
│
├── Lambda/                            # NEW
│   └── LambdaClient.swift
│
├── S3/                                # NEW
│   └── S3Client.swift
│
└── SecretsManager/                    # NEW
    └── SecretsManagerClient.swift
```

### Refactored AWSCLIService

After moving generic operations to sdk-aws, `AWSCLIService` becomes either:

**Option A: Remove entirely** - Callers use sdk-aws clients directly

**Option B: Thin facade** - Convenience wrapper that composes sdk-aws clients

Recommended: **Option A** - Remove `AWSCLIService` entirely. The sdk-aws clients provide the same functionality with proper separation of concerns.

---

## Migration Steps

### Prerequisites

Before starting implementation:
1. Review existing sdk-aws clients (`CloudFormationClient`, `CloudWatchLogsClient`) for patterns
2. Ensure `swift build` passes before starting
3. Update document with checkboxes indicating phase complete
4. Commit changes

### Build Verification Requirements

**CRITICAL: Build after every step, not just after each phase.**

- After each file creation or modification, run `swift build`
- The build must succeed before moving to the next step
- Do NOT run tests or the application - only verify compilation
- If the build fails, fix the issue before proceeding

This ensures:
- Incremental progress is verifiable
- Errors are caught immediately at the source
- Each commit represents working (compilable) code

### Instructions

**Important: Complete one phase at a time.** Verify the build passes and commit before proceeding.

After completing each phase:

1. **Build all targets** (do NOT run, just compile):
   ```bash
   swift build
   ```
   The build must succeed. Runtime behavior doesn't need to be tested at each step.

2. **Commit the changes**:
   ```bash
   git add -A
   git commit -m "Phase N: <description>"
   ```

3. **Stop and report completion.** Do not proceed to the next phase automatically.

---

### Phase 1: Create LambdaClient ✅

- [x] Create `Sources/sdk-aws/Lambda/` directory
- [x] Create `LambdaClient.swift` with:
  - `updateFunctionCode(functionName:zipFile:output:)`
  - `getFunction(name:)`
  - `functionExists(name:)`
- [x] Create `LambdaError` enum
- [x] Create `LambdaFunction` model struct
- [x] Add Lambda command execution helper methods (follow CloudFormationClient pattern)

### Phase 2: Create S3Client ✅

- [x] Create `Sources/sdk-aws/S3/` directory
- [x] Create `S3Client.swift` with:
  - `list(bucket:prefix:)`
  - `copy(source:destination:)`
  - `objectExists(bucket:key:)`
- [x] Create `S3Error` enum
- [x] Create `S3Object` model struct

### Phase 3: Create SecretsManagerClient ✅

- [x] Create `Sources/sdk-aws/SecretsManager/` directory
- [x] Create `SecretsManagerClient.swift` with:
  - `getSecretValue(secretId:)`
  - `getSecretJSON(secretId:)`
  - `listSecrets()`
- [x] Create `SecretsManagerError` enum
- [x] Create `SecretInfo` model struct

### Phase 4: Update Callers to Use New Clients ✅

- [x] Find all callers of `AWSCLIService.updateLambdaCode` → use `LambdaClient` (no external callers found)
- [x] Find all callers of `AWSCLIService.getLambdaFunction` → use `LambdaClient` (no external callers found)
- [x] Find all callers of `AWSCLIService.s3List` → use `S3Client` (updated AWSTestingService)
- [x] Find all callers of `AWSCLIService.s3Copy` → use `S3Client` (updated AWSTestingService)
- [x] Find all callers of `AWSCLIService.getSecretValue` → use `SecretsManagerClient` (no external callers found)
- [x] Find all callers of `AWSCLIService.listSecrets` → use `SecretsManagerClient` (no external callers found)

### Phase 5: Remove Duplicate CloudFormation Methods ✅

- [x] Find callers of `AWSCLIService.describeStack` → use `CloudFormationClient` (no external callers found)
- [x] Find callers of `AWSCLIService.getStackStatus` → use `CloudFormationClient` (no external callers found)
- [x] Find callers of `AWSCLIService.getStackOutputs` → use `CloudFormationClient` (updated RemoteModel)
- [x] Find callers of `AWSCLIService.getStackOutput` → use `CloudFormationClient` (updated AWSTestingService)
- [x] Find callers of `AWSCLIService.describeStackResources` → use `CloudFormationClient` (no external callers found)
- [x] Find callers of `AWSCLIService.getStackEvents` → use `CloudFormationClient` (no external callers found)
- [x] Remove duplicate methods from `AWSCLIService`

### Phase 6: Remove Duplicate CloudWatch Methods ✅

- [x] Find callers of `AWSCLIService.tailLogs` → use `CloudWatchLogsClient` (updated AWSTestingService)
- [x] Remove `tailLogs` from `AWSCLIService`

### Phase 7: Delete AWSCLIService ✅

- [x] Verify no remaining callers of `AWSCLIService`
- [x] Delete `Sources/service-deploy/AWSService/AWSCLIService.swift`
- [x] Remove any orphaned imports (none found)

---

## Benefits

1. **No duplication** - Each AWS operation defined once in sdk-aws
2. **Consistent patterns** - All clients follow same structure (CloudFormationClient pattern)
3. **Proper layering** - Generic AWS operations in sdk-aws, app-specific logic in service-deploy
4. **Type safety** - Dedicated error types and model structs per service
5. **Testability** - Each client can be mocked independently

---

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Breaking callers during migration | Update callers one phase at a time |
| Missing edge cases in new clients | Copy implementation from AWSCLIService methods |
| Compile errors from import changes | Build after each phase |

---

## Files Affected

### New Files (sdk-aws)
- `Sources/sdk-aws/Lambda/LambdaClient.swift`
- `Sources/sdk-aws/S3/S3Client.swift`
- `Sources/sdk-aws/SecretsManager/SecretsManagerClient.swift`

### Modified Files (service-deploy)
- Callers of AWSCLIService methods (to be identified in each phase)

### Deleted Files
- `Sources/service-deploy/AWSService/AWSCLIService.swift`
