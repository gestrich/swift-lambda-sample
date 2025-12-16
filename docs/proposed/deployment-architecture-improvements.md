# Deployment Architecture Improvements

Evaluation of `DeploymentModel`, CLI commands in `app-cli`, and `service-deploy` against `docs/architecture/layered-architecture.md` and `docs/architecture/code-style.md`.

## Summary

The codebase generally follows the layered architecture, but several areas need refinement:

| Area | Issue | Severity |
|------|-------|----------|
| CLI Commands | Duplicated client setup, business logic in app layer | High |
| DeploymentModel | Too much orchestration logic, should be thinner | Medium |
| Workflows | Inconsistent factory patterns | Medium |
| Code Style | Default values masking missing config | Medium |
| StatusCommand | No workflow, directly queries clients | Low |

---

## Issue 1: CLI Commands Have Duplicated Client Setup

**Violation**: DRY principle, app layer doing SDK orchestration

**Current State**: Each CLI command creates clients identically:

```swift
// DeployCommand.swift:37-50
let projectRoot = FileManager.default.currentDirectoryPath
let cliClient = CLIClient()
let credentialProvider = awsConfig.makeCredentialProvider()
let fullCdkPath = "\(projectRoot)/\(cdkDirectory)"

let cdkClient = CDKClient(
    cdkDirectory: fullCdkPath,
    credentialProvider: credentialProvider,
    cliClient: cliClient
)
let cfClient = CloudFormationClient(
    credentialProvider: credentialProvider,
    cliClient: cliClient
)
```

This pattern is repeated in:
- `DeployCommand.swift:37-50`
- `DeployInitCommand.swift:54-67`
- `TearDownCommand.swift:47-60`
- `StatusCommand.swift:29-41`

**Suggested Fix**: Add factory methods to workflows (like `UpdateLambdaWorkflow.create()`):

```swift
// DeployWorkflow.swift
public static func create(
    projectRoot: String,
    cdkDirectory: String = "cdk",
    awsConfig: AWSAuthConfiguration
) -> DeployWorkflow {
    let cliClient = CLIClient(defaultWorkingDirectory: projectRoot)
    let credentialProvider = awsConfig.makeCredentialProvider()
    let fullCdkPath = "\(projectRoot)/\(cdkDirectory)"

    let cdkClient = CDKClient(
        cdkDirectory: fullCdkPath,
        credentialProvider: credentialProvider,
        cliClient: cliClient
    )
    let cfClient = CloudFormationClient(
        credentialProvider: credentialProvider,
        cliClient: cliClient
    )

    return DeployWorkflow(
        cdkClient: cdkClient,
        cfClient: cfClient,
        stackName: CDKStackConfiguration.defaultStackName
    )
}
```

Then CLI commands become thin:

```swift
// DeployCommand.swift
mutating func run() async throws {
    let awsConfig = try AWSAuthConfiguration.resolve(...)
    let workflow = DeployWorkflow.create(
        projectRoot: FileManager.default.currentDirectoryPath,
        cdkDirectory: cdkDirectory,
        awsConfig: awsConfig
    )

    for try await progress in workflow.run(options: options) {
        print(progress)  // Or switch on progress.step
    }
}
```

---

## Issue 2: Business Logic in CLI Commands (App Layer)

**Violation**: Architecture states "Minimal business logic; focus on I/O and calling workflows"

**Current State**: `DeployInitCommand` contains significant business logic:

```swift
// DeployInitCommand.swift:95-136
private func checkDatabaseSafety(cfClient: CloudFormationClient) async throws { ... }
private func checkExistingConfiguration(cfClient: CloudFormationClient) async throws { ... }
private func initializeDatabase(apiUrl: String, cliClient: CLIClient) async throws { ... }
private func verifyDeployment(apiUrl: String, cliClient: CLIClient) async throws { ... }
```

These are multi-step operations that belong in the **service layer**.

**Suggested Fix**: Create a `DeployInitWorkflow` that encapsulates the full flow:

```swift
// service-deploy/Workflows/DeployInitWorkflow.swift
public struct DeployInitWorkflow: Sendable {
    public struct Progress: Sendable {
        public enum Step: Sendable {
            case checkingSafety
            case checkingConfiguration
            case deployingInfrastructure(DeployWorkflow.Progress)
            case updatingLambda(UpdateLambdaWorkflow.Progress)
            case initializingDatabase
            case verifyingDeployment
            case complete
        }
    }

    public func run(options: Options) -> AsyncThrowingStream<Progress, Error> {
        // Orchestrate: safety check → deploy → update lambda → init db → verify
    }
}
```

CLI becomes:

```swift
// DeployInitCommand.swift
for try await progress in workflow.run(options: options) {
    switch progress.step {
    case .checkingSafety: print("🔒 Checking safety...")
    case .deployingInfrastructure(let p): printDeployProgress(p)
    // etc.
    }
}
```

---

## Issue 3: DeploymentModel Has Too Much Logic

**Violation**: Architecture states "Models should contain minimal logic—their role is to monitor workflow streams and update state for the UI"

**Current State**: `DeploymentModel` does orchestration within its methods:

```swift
// DeploymentModel.swift:262-289
for try await progress in workflow.run(options: options, output: output) {
    activeWorkflow = .deploy(progress)

    // Update state based on workflow progress
    switch progress.step {
    case .building:
        deploymentState = .deploying(operation: .building, ...)
    case .deploying:
        if case .cdk(let deployProgress) = progress.detail {
            deploymentState = .deploying(operation: .deploying, ...)
        }
    // ... more cases
    }
}
```

This mapping logic is business logic, not pure state observation.

**Suggested Fix**: The workflow should yield progress that maps directly to UI state, or use a separate mapper:

```swift
// Option A: Simpler Progress that maps directly
public func deploy(options: DeployWorkflow.Options) async {
    for try await progress in workflow.run(options: options) {
        activeWorkflow = .deploy(progress)
        deploymentState = progress.toDeploymentState(startTime: operationStartTime)
    }
    activeWorkflow = nil
}

// Where toDeploymentState is defined on DeployWorkflow.Progress
extension DeployWorkflow.Progress {
    func toDeploymentState(startTime: Date) -> CloudFormationState { ... }
}
```

---

## Issue 4: Inconsistent Workflow Factory Patterns

**Current State**:
- `UpdateLambdaWorkflow` has `.create()` factory ✅
- `DeployWorkflow` requires manual client setup ❌
- `DestroyWorkflow` requires manual client setup ❌

**Suggested Fix**: Add `.create()` factories to all workflows for consistency:

```swift
// All workflows should support:
let workflow = try DeployWorkflow.create(projectRoot: ..., awsConfig: ...)
let workflow = try DestroyWorkflow.create(projectRoot: ..., awsConfig: ...)
let workflow = try UpdateLambdaWorkflow.create(projectRoot: ..., cliClient: ...)
```

---

## Issue 5: Default Values Masking Missing Config

**Violation**: Code style states "Prefer requiring data explicitly rather than providing defaults or fallbacks"

**Current State**: `DeploymentModel` convenience init masks missing config:

```swift
// DeploymentModel.swift:210
let awsConfig = AWSAuthConfiguration.loadConfig()
    ?? AWSAuthConfiguration(profileName: "default", useAWSVault: false)
```

If config is missing, this silently uses "default" profile which may not exist or be wrong.

**Suggested Fix**: Throw if config is missing:

```swift
public convenience init(projectRoot: String, cliClient: CLIClient? = nil) throws {
    guard let awsConfig = AWSAuthConfiguration.loadConfig() else {
        throw DeployError.configurationMissing(
            file: AWSAuthConfiguration.configPath,
            hint: "Run 'swift run SwiftDeploy local copy-config' to create"
        )
    }
    // ...
}
```

---

## Issue 6: StatusCommand Doesn't Use a Workflow

**Violation**: Architecture states workflows are for "multi-step operations"

**Current State**: `StatusCommand` directly queries multiple clients:

```swift
// StatusCommand.swift:44-103
let hasUncommitted = try await gitClient.hasUncommittedChanges()
let hasCommitsToPush = try await gitClient.hasCommitsToPush()
let currentBranch = try await gitClient.getCurrentBranch()
// ... then GitHub client
// ... then CloudFormation client
```

**Suggested Fix**: Create a `StatusWorkflow`:

```swift
public struct StatusWorkflow: Sendable {
    public struct Progress: Sendable {
        public enum Step: Sendable {
            case checkingGit(GitStatus)
            case checkingGitHub(GitHubStatus?)
            case checkingStack(CloudFormationState)
            case complete(Status)
        }
    }

    public struct Status: Sendable {
        public let git: GitStatus
        public let github: GitHubStatus?
        public let stack: CloudFormationState
    }
}
```

This allows the Mac app to also show real-time status checking progress.

---

## Issue 7: Duplicated Progress Printing

**Current State**: `printDeployProgress` is duplicated:
- `DeployCommand.swift:129-135`
- `DeployInitCommand.swift:277-283`
- `TearDownCommand.swift:115-121`

**Suggested Fix**: Either:

A. Add a `description` property to `DeploymentProgress`:
```swift
extension DeploymentProgress {
    public var progressDescription: String {
        let completed = completedCount
        let total = resources.count
        return total > 0 ? "Deploying resources: \(completed)/\(total)" : ""
    }
}
```

B. Or create a shared CLI utility:
```swift
// app-cli/Utilities/ProgressPrinting.swift
func printDeployProgress(_ progress: DeploymentProgress, emoji: String = "☁️") {
    let completed = progress.completedCount
    let total = progress.resources.count
    if total > 0 {
        print("\(emoji)  Deploying resources: \(completed)/\(total)")
    }
}
```

---

## Issue 8: Hardcoded Stack Name

**Current State**: Stack name is duplicated across commands:

```swift
// DeployCommand.swift:23
private static let stackName = "SwiftLambdaSampleStack"

// TearDownCommand.swift:26
private static let stackName = "SwiftLambdaSampleStack"

// DeployInitCommand.swift:32
private static let stackName = "SwiftLambdaSampleStack"
```

While `CDKStackConfiguration.defaultStackName` exists, it's not used consistently.

**Suggested Fix**: Use `CDKStackConfiguration.defaultStackName` everywhere, or have workflows use it internally.

---

## Implementation Phases

### Phase 1: Workflow Factories (Unblocks other phases) ✅ COMPLETED

- [x] Add `DeployWorkflow.create(cdkDirectory:credentialProvider:cliClient:stackName:)` factory
- [x] Add `DestroyWorkflow.create(cdkDirectory:credentialProvider:cliClient:stackName:)` factory
- [x] Update `DeployCommand` to use `DeployWorkflow.create()`
- [x] Update `TearDownCommand` to use `DestroyWorkflow.create()`
- [x] Update `DeployInitCommand` to use `DeployWorkflow.create()`
- [x] Remove duplicated client setup code from CLI commands

**Technical Notes:**
- Factory methods return a `Components` struct containing `workflow`, `cfClient`, and `stackName`
- This design allows CLI commands to query CloudFormation state before running the workflow
- Stack name defaults to `CDKStackConfiguration.defaultStackName` but can be overridden
- Signature differs from original spec: takes `credentialProvider` directly rather than `awsConfig` since CLI already resolves credentials

### Phase 2: DeployInitWorkflow ✅ COMPLETED

- [x] Create `DeployInitWorkflow` in service-deploy
- [x] Move `checkDatabaseSafety` logic into workflow
- [x] Move `checkExistingConfiguration` logic into workflow
- [x] Move `initializeDatabase` logic into workflow
- [x] Move `verifyDeployment` logic into workflow
- [x] Update `DeployInitCommand` to use workflow (thin command)

**Technical Notes:**
- `DeployInitWorkflow` composes `DeployWorkflow` and `UpdateLambdaWorkflow` internally, yielding nested progress
- Factory method follows Phase 1 pattern: `create()` returns `Components` struct with `workflow`, `cfClient`, `stackName`
- CLI command reduced from ~270 lines to ~200 lines, with all business logic moved to workflow
- Progress enum has six steps: `checkingSafety`, `checkingConfiguration`, `deployingInfrastructure`, `updatingLambda`, `initializingDatabase`, `verifyingDeployment`, `complete`
- `ExistingConfiguration` type exposes detected stack state for UI display
- Verification uses health endpoint (`/api/health`) rather than S3 upload test for faster feedback

### Phase 3: Configuration Validation

- [ ] Remove default fallback in `DeploymentModel` convenience init
- [ ] Make convenience init throwing
- [ ] Update callers to handle missing config explicitly

### Phase 4: StatusWorkflow

- [ ] Create `StatusWorkflow` in service-deploy
- [ ] Define `GitStatus` and `GitHubStatus` types
- [ ] Update `StatusCommand` to use workflow
- [ ] Add status checking to Mac app using same workflow

### Phase 5: Thin DeploymentModel

- [ ] Add `toDeploymentState()` extension on `DeployWorkflow.Progress`
- [ ] Simplify `deploy()` method to just observe stream
- [ ] Add `toDeploymentState()` extension on `DestroyWorkflow.Progress`
- [ ] Simplify `destroy()` method to just observe stream

### Phase 6: Code Cleanup

- [ ] Add `progressDescription` property to `DeploymentProgress`
- [ ] Remove duplicated `printDeployProgress` from CLI commands
- [ ] Replace hardcoded stack names with `CDKStackConfiguration.defaultStackName`
- [ ] Verify all imports are alphabetized

---

## Architecture Compliance Checklist

| Principle | Current | Target |
|-----------|---------|--------|
| CLI commands are thin (I/O only) | ⚠️ Partial | ✅ Full |
| Workflows handle orchestration | ⚠️ Partial | ✅ Full |
| Models observe streams | ⚠️ Partial | ✅ Full |
| No default fallbacks | ❌ | ✅ |
| Consistent factory patterns | ✅ Full (Phase 1) | ✅ Full |
| DRY (no duplicated setup) | ✅ Full (Phase 1) | ✅ Full |
