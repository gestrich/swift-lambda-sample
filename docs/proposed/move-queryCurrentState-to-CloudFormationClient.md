# Move queryCurrentState Logic to CloudFormationClient

## Overview

This document analyzes moving the `queryCurrentState()` logic from `DeploymentService` to `CloudFormationClient`, aligning with the layered architecture principle that SDKs should handle generic operations.

## Current State

### DeploymentService.queryCurrentState() (service-deploy)

Location: `Sources/service-deploy/DeploymentService.swift:579-628`

```swift
private func queryCurrentState() async throws -> DeploymentState {
    do {
        let stackStatus = try await cloudFormationClient.getStackStatus(name: stackName)

        switch stackStatus {
        case StackStatus.createComplete, StackStatus.updateComplete:
            let config = try await detectConfiguration()
            let outputs = try await getStackOutputs()
            infrastructureConfiguration = config
            stackOutputs = outputs
            return .deployed(outputs: outputs.allOutputs)

        case StackStatus.createInProgress, StackStatus.updateInProgress, ...:
            let startTime = await getOperationStartTime() ?? Date()
            return .deploying(...)

        case StackStatus.deleteInProgress:
            return .destroying(...)

        case StackStatus.createFailed, ...:
            return .failed(reason: stackStatus)

        default:
            // Same as deployed case
        }
    } catch {
        // Error classification (credential, stack-not-found, unknown)
    }
}
```

### CloudFormationClient (sdk-aws)

Location: `Sources/sdk-aws/CloudFormation/CloudFormationClient.swift`

Currently provides low-level operations:
- `getStackStatus(name:)` → `String`
- `getStackOutputs(name:)` → `[String: String]`
- `describeStackResources(name:)` → `[CloudFormationStackResource]`
- `getStackEvents(name:limit:)` → `[CloudFormationStackEvent]`

Has its own `State` enum for tracking query operations (idle, querying, ready, failed).

### DeploymentState (sdk-aws)

Location: `Sources/sdk-aws/CloudFormation/DeploymentState.swift`

Already in the SDK layer! This is the return type of `queryCurrentState()`:
- `.unknown`, `.loading`, `.notDeployed`
- `.deployed(outputs: [String: String])`
- `.deploying(operation:progress:startTime:)`
- `.destroying(progress:startTime:)`
- `.failed(reason:)`, `.credentialExpired(message:)`

## Analysis

### What IS Generic (Can Move to SDK)

1. **Stack status → DeploymentState mapping**
   - The switch statement mapping `StackStatus` strings to `DeploymentState` cases
   - Uses `StackStatus` constants already in sdk-aws

2. **Error classification**
   - `DeploymentError.isCredentialError()` - already in sdk-aws
   - `DeploymentError.isStackNotFoundError()` - already in sdk-aws

3. **Operation start time detection**
   - Parsing stack events to find IN_PROGRESS timestamps
   - Generic CloudFormation pattern, not app-specific

4. **Stack outputs retrieval**
   - Raw `[String: String]` dictionary is already generic

### What IS App-Specific (Must Stay in Service)

1. **CDKInfrastructureConfiguration detection**
   ```swift
   private func detectConfiguration() async throws -> CDKInfrastructureConfiguration?
   private func parseConfiguration(from resources: [CloudFormationStackResource]) -> CDKInfrastructureConfiguration
   ```
   - Looks for specific resource patterns: Database (RDS), NAT Gateway, VPC
   - This is business logic specific to this CDK stack

2. **CDKStackOutputs mapping**
   ```swift
   CDKStackOutputs.from(_ outputs: [String: String])
   ```
   - Maps specific output keys: `ApiGatewayUrl`, `LambdaFunctionName`, `BucketName`
   - These keys are specific to this CDK stack

3. **Service property mutations**
   ```swift
   infrastructureConfiguration = config
   stackOutputs = outputs
   ```
   - Setting `@Observable` properties for UI binding

## Proposed Changes

### 1. Add `queryDeploymentState(stackName:)` to CloudFormationClient

```swift
// sdk-aws/CloudFormation/CloudFormationClient.swift

/// Query the deployment state of a CloudFormation stack
/// - Parameter stackName: The stack name
/// - Returns: DeploymentState based on stack status
public func queryDeploymentState(stackName: String) async throws -> DeploymentState {
    do {
        let stackStatus = try await getStackStatus(name: stackName)
        let outputs = try await getStackOutputs(name: stackName)

        switch stackStatus {
        case StackStatus.createComplete, StackStatus.updateComplete:
            return .deployed(outputs: outputs)

        case StackStatus.createInProgress,
             StackStatus.updateInProgress,
             StackStatus.updateCompleteCleanupInProgress:
            let startTime = try await getOperationStartTime(stackName: stackName)
            return .deploying(
                operation: "Updating",
                progress: DeploymentProgress(),
                startTime: startTime
            )

        case StackStatus.deleteInProgress:
            let startTime = try await getOperationStartTime(stackName: stackName)
            return .destroying(progress: DeploymentProgress(), startTime: startTime)

        case StackStatus.createFailed,
             StackStatus.updateFailed,
             StackStatus.rollbackComplete,
             StackStatus.rollbackFailed,
             StackStatus.deleteFailed:
            return .failed(reason: stackStatus)

        default:
            return .deployed(outputs: outputs)
        }
    } catch {
        let errorMessage = error.localizedDescription

        if DeploymentError.isCredentialError(errorMessage) {
            throw DeploymentError.credentialExpired(message: errorMessage)
        } else if DeploymentError.isStackNotFoundError(errorMessage) {
            return .notDeployed
        } else {
            throw DeploymentError.unknown(message: errorMessage)
        }
    }
}

/// Get the start time of the current in-progress operation
private func getOperationStartTime(stackName: String) async throws -> Date {
    let events = try await getStackEvents(name: stackName, limit: 50)

    return events
        .filter { $0.logicalResourceId == stackName && $0.resourceStatus.contains("IN_PROGRESS") }
        .map { $0.timestamp }
        .min() ?? Date()
}
```

### 2. Simplify DeploymentService.queryCurrentState()

```swift
// service-deploy/DeploymentService.swift

private func queryCurrentState() async throws -> DeploymentState {
    // Get generic deployment state from SDK
    let state = try await cloudFormationClient.queryDeploymentState(stackName: stackName)

    // Handle app-specific concerns based on state
    switch state {
    case .deployed(let outputs):
        // App-specific: detect infrastructure configuration
        let config = try await detectConfiguration()
        infrastructureConfiguration = config

        // App-specific: map to typed outputs
        let typedOutputs = CDKStackOutputs.from(outputs)
        stackOutputs = typedOutputs

        return state

    case .notDeployed:
        infrastructureConfiguration = nil
        stackOutputs = nil
        return state

    default:
        return state
    }
}
```

## Complications

### 1. Dual State Systems

**Problem**: CloudFormationClient already has its own `State` enum (`idle`, `querying`, `ready`, `failed`) which is different from `DeploymentState`.

**Options**:
- **Option A**: Keep both - CloudFormationClient.State tracks query operations, DeploymentState represents stack state
- **Option B**: Consolidate into DeploymentState, remove CloudFormationClient.State
- **Option C**: Rename CloudFormationClient.State to `QueryState` for clarity

**Recommendation**: Option A - keep both. They serve different purposes:
- `CloudFormationClient.State` = "What is the client doing?" (querying, idle)
- `DeploymentState` = "What is the stack's state?" (deployed, deploying)

### 2. getStackOutputs() Error Handling

**Problem**: In the deployed case, we fetch outputs. But what if getStackOutputs() fails?

**Current behavior**: The switch happens after getStackStatus(), outputs are fetched inside each case.

**New behavior**: We'd fetch outputs before the switch for all cases, but only deployed states need them.

**Solution**: Only fetch outputs for terminal states:

```swift
public func queryDeploymentState(stackName: String) async throws -> DeploymentState {
    let stackStatus = try await getStackStatus(name: stackName)

    // Only fetch outputs for deployed states
    if StackStatus.isDeployed(stackStatus) {
        let outputs = try await getStackOutputs(name: stackName)
        return .deployed(outputs: outputs)
    }

    // ... rest of switch
}
```

### 3. Operation Start Time Locality

**Problem**: `getOperationStartTime()` currently uses `stackName` from the service's stored property.

**Solution**: Pass stackName as parameter (shown in proposed code above).

### 4. Progress Object

**Problem**: `queryCurrentState()` returns `DeploymentProgress()` (empty progress). The actual progress is updated separately via CDK output parsing during deploy/destroy operations.

**Implication**: This is fine - the SDK method returns initial progress, service updates it during operations.

### 5. DeploymentError Throwing vs Returning State

**Current behavior**:
- Credential errors → throw
- Stack not found → return `.notDeployed`
- Other errors → throw

**This pattern should be preserved** in the SDK method.

## Migration Steps

1. **Add `getOperationStartTime(stackName:)` to CloudFormationClient** (private helper)

2. **Add `queryDeploymentState(stackName:)` to CloudFormationClient**
   - Implement generic stack status → DeploymentState mapping
   - Handle error classification

3. **Update DeploymentService.queryCurrentState()**
   - Call `cloudFormationClient.queryDeploymentState(stackName:)`
   - Handle app-specific concerns (detectConfiguration, CDKStackOutputs)
   - Set service properties

4. **Test**
   - Verify deployed state returns outputs
   - Verify in-progress states return correct operation type
   - Verify credential errors throw
   - Verify stack-not-found returns .notDeployed

5. **Optional cleanup**
   - Consider if CloudFormationClient.State is still needed
   - Consider renaming for clarity

## Benefits

1. **Better SDK/Service separation**: Generic CloudFormation logic moves to SDK
2. **Reusability**: Other services could query stack deployment state
3. **Testability**: SDK method can be tested independently
4. **Single responsibility**: Service focuses on app-specific orchestration

## Risks

- **Breaking change**: If other code depends on CloudFormationClient's current state publishing behavior
- **Performance**: Now makes 2 calls (status + outputs) for deployed states, but this is the same as before

## Files Changed

| File | Change |
|------|--------|
| `Sources/sdk-aws/CloudFormation/CloudFormationClient.swift` | Add `queryDeploymentState(stackName:)` and `getOperationStartTime(stackName:)` |
| `Sources/service-deploy/DeploymentService.swift` | Simplify `queryCurrentState()` to use SDK method |
