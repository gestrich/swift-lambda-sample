# Dependency Workflows: service-setup Target

## Status: Proposed

**Created:** 2025-12-17

## Goal

Refactor `DependencyStatusModel` to use the workflow pattern, following the layered architecture principles:
- Create a new `service-setup` target for dependency management workflows
- Create workflows for checking dependency statuses and installing dependencies
- Replace 6 individual status properties with enum-based state in the model

## Background

Currently, `DependencyStatusModel` in `app-mac`:
- Has 6 individual status properties (`homebrewStatus`, `nodejsStatus`, etc.)
- Uses SDK clients directly (BrewClient, NodeClient, DockerClient, etc.)
- Uses `DependencyUIState` enum with cases: `unknown`, `checking`, `installed`, `notInstalled`

This violates the layered architecture principle that workflows should orchestrate SDK clients, not models. The model should consume workflow streams and update state.

## Target Architecture

```
app-mac
├── DependencyStatusModel (@Observable)
│   └── state: ModelState enum (uses workflows)
└── Views (SetupViews, ServicesView)

         ↓ uses

service-setup
├── DependencyStatusWorkflow  → AsyncThrowingStream<Progress, Error>
├── DependencyInstallWorkflow → AsyncThrowingStream<Progress, Error>
├── CLITool enum
├── CLIToolStatus
└── DependencySnapshot

         ↓ uses

sdk-cli-brew, sdk-cli-node, sdk-cli-docker, sdk-aws, sdk-github
├── BrewClient, NodeClient, DockerClient
├── AWSCLIClient, CDKClient
└── GitHubCLIClient
```

---

## Phase 1: Create service-setup Target

**Status:** Completed

**Goal:** Create new service-layer target with basic types.

**Files:**
- Modify: `Package.swift`
- Create: `Sources/service-setup/CLITool.swift`
- Create: `Sources/service-setup/CLIToolStatus.swift`
- Create: `Sources/service-setup/DependencySnapshot.swift`

**Changes:**

1. Add `service-setup` target to Package.swift:
```swift
.target(
    name: "service-setup",
    dependencies: [
        "sdk-cli",
        "sdk-cli-brew",
        "sdk-cli-node",
        "sdk-cli-docker",
        "sdk-aws",
        "sdk-github",
    ]
),
```

2. Create `CLITool` enum:
```swift
public enum CLITool: String, CaseIterable, Sendable {
    case homebrew
    case nodejs
    case docker
    case awsCLI
    case cdk
    case githubCLI
}
```

3. Create `CLIToolStatus` struct:
```swift
public struct CLIToolStatus: Sendable, Equatable {
    public let tool: CLITool
    public let isInstalled: Bool
    public let version: String?

    public init(tool: CLITool, isInstalled: Bool, version: String? = nil) {
        self.tool = tool
        self.isInstalled = isInstalled
        self.version = version
    }
}
```

4. Create `DependencySnapshot` struct:
```swift
public struct DependencySnapshot: Sendable, Equatable {
    public let statuses: [CLITool: CLIToolStatus]

    public init(statuses: [CLITool: CLIToolStatus]) {
        self.statuses = statuses
    }

    public func status(for tool: CLITool) -> CLIToolStatus? {
        statuses[tool]
    }

    public var allInstalled: Bool {
        CLITool.allCases.allSatisfy { statuses[$0]?.isInstalled == true }
    }
}
```

**Verification:** `swift build` succeeds.

**Implementation Notes:**
- Added `displayName` computed property to `CLITool` for UI usage
- Target has dependencies on all SDK clients: sdk-cli, sdk-cli-brew, sdk-cli-node, sdk-cli-docker, sdk-aws, sdk-github

---

## Phase 2: Create DependencyStatusWorkflow

**Status:** Completed

**Goal:** Workflow that checks all dependency statuses and yields progress.

**Files:**
- Create: `Sources/service-setup/DependencyStatusWorkflow.swift`

**Design:**
```swift
public struct DependencyStatusWorkflow: Sendable {
    private let cliClient: CLIClient
    private let brewClient: BrewClient
    private let nodeClient: NodeClient
    private let dockerClient: DockerClient
    private let awsCLIClient: AWSCLIClient

    public init(cliClient: CLIClient) {
        self.cliClient = cliClient
        self.brewClient = BrewClient(cliClient: cliClient)
        self.nodeClient = NodeClient(cliClient: cliClient)
        self.dockerClient = DockerClient(cliClient: cliClient)
        self.awsCLIClient = AWSCLIClient(cliClient: cliClient)
    }

    public struct Progress: Sendable {
        public let step: Step
        public let detail: Detail?

        public enum Step: Sendable, Equatable {
            case checking(CLITool)
            case complete
        }

        public enum Detail: Sendable {
            case status(CLIToolStatus)
            case snapshot(DependencySnapshot)
        }

        public init(step: Step, detail: Detail? = nil) {
            self.step = step
            self.detail = detail
        }
    }

    public func run() -> AsyncThrowingStream<Progress, Error> {
        run(tools: CLITool.allCases)
    }

    public func run(tools: [CLITool]) -> AsyncThrowingStream<Progress, Error> {
        AsyncThrowingStream { continuation in
            Task {
                var statuses: [CLITool: CLIToolStatus] = [:]

                for tool in tools {
                    continuation.yield(Progress(step: .checking(tool)))
                    let status = await checkTool(tool)
                    statuses[tool] = status
                    continuation.yield(Progress(step: .checking(tool), detail: .status(status)))
                }

                let snapshot = DependencySnapshot(statuses: statuses)
                continuation.yield(Progress(step: .complete, detail: .snapshot(snapshot)))
                continuation.finish()
            }
        }
    }

    private func checkTool(_ tool: CLITool) async -> CLIToolStatus {
        switch tool {
        case .homebrew:
            let installed = await brewClient.isInstalled()
            let version = installed ? await brewClient.version() : nil
            return CLIToolStatus(tool: tool, isInstalled: installed, version: version)
        case .nodejs:
            let installed = await nodeClient.isInstalled()
            let version = installed ? await nodeClient.version() : nil
            return CLIToolStatus(tool: tool, isInstalled: installed, version: version)
        case .docker:
            let installed = await dockerClient.isInstalled()
            return CLIToolStatus(tool: tool, isInstalled: installed, version: nil)
        case .awsCLI:
            let installed = await awsCLIClient.isInstalled()
            let version = installed ? await awsCLIClient.version() : nil
            return CLIToolStatus(tool: tool, isInstalled: installed, version: version)
        case .cdk:
            let installed = await CDKClient.isInstalled(cliClient: cliClient)
            return CLIToolStatus(tool: tool, isInstalled: installed, version: nil)
        case .githubCLI:
            let installed = await GitHubCLIClient.isInstalled(cliClient: cliClient)
            return CLIToolStatus(tool: tool, isInstalled: installed, version: nil)
        }
    }
}
```

**Technical Notes:**
- Uses existing SDK clients for installation checks
- CDKClient and GitHubCLIClient use static `isInstalled(cliClient:)` methods
- Other clients use instance methods
- Yields progress for each tool being checked, then final snapshot

**Verification:** `swift build` succeeds.

**Implementation Notes:**
- `checkTool` is internal (no `public` modifier) to allow `DependencyInstallWorkflow` in the same module to verify installations
- DockerClient does not expose a `version()` method, so version is nil for Docker
- Progress yields twice per tool: once when starting to check, once with the status result

---

## Phase 3: Create DependencyInstallWorkflow

**Status:** Completed

**Goal:** Workflow that installs a specific dependency.

**Files:**
- Create: `Sources/service-setup/DependencyInstallWorkflow.swift`

**Design:**
```swift
public struct DependencyInstallWorkflow: Sendable {
    private let cliClient: CLIClient
    private let brewClient: BrewClient

    public init(cliClient: CLIClient) {
        self.cliClient = cliClient
        self.brewClient = BrewClient(cliClient: cliClient)
    }

    public struct Progress: Sendable {
        public let step: Step
        public let detail: Detail?

        public enum Step: Sendable, Equatable {
            case preparing
            case installing
            case verifying
            case complete
        }

        public enum Detail: Sendable {
            case output(String)
            case installed(CLIToolStatus)
            case failed(String)
        }

        public init(step: Step, detail: Detail? = nil) {
            self.step = step
            self.detail = detail
        }
    }

    public func run(tool: CLITool) -> AsyncThrowingStream<Progress, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    continuation.yield(Progress(step: .preparing))

                    continuation.yield(Progress(step: .installing))
                    try await install(tool)

                    continuation.yield(Progress(step: .verifying))
                    let status = await verify(tool)

                    continuation.yield(Progress(step: .complete, detail: .installed(status)))
                    continuation.finish()
                } catch {
                    continuation.yield(Progress(step: .complete, detail: .failed(error.localizedDescription)))
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func install(_ tool: CLITool) async throws {
        switch tool {
        case .homebrew:
            // Homebrew installation via shell script
            throw DependencyInstallError.manualInstallRequired(tool)
        case .nodejs:
            try await brewClient.install("node")
        case .docker:
            try await brewClient.install("docker", cask: true)
        case .awsCLI:
            try await brewClient.install("awscli")
        case .cdk:
            // npm install -g aws-cdk
            throw DependencyInstallError.manualInstallRequired(tool)
        case .githubCLI:
            try await brewClient.install("gh")
        }
    }

    private func verify(_ tool: CLITool) async -> CLIToolStatus {
        // Reuse status workflow check logic
        let statusWorkflow = DependencyStatusWorkflow(cliClient: cliClient)
        return await statusWorkflow.checkTool(tool)
    }
}

public enum DependencyInstallError: Error, LocalizedError {
    case manualInstallRequired(CLITool)

    public var errorDescription: String? {
        switch self {
        case .manualInstallRequired(let tool):
            return "\(tool.rawValue) requires manual installation"
        }
    }
}
```

**Technical Notes:**
- Uses Homebrew for most installations
- Some tools (Homebrew itself, CDK) require manual installation
- Verifies installation after completion
- Reuses `checkTool` from `DependencyStatusWorkflow` (internal method exposed for same-module access)

**Verification:** `swift build` succeeds.

**Implementation Notes:**
- Required `import Foundation` for `LocalizedError` protocol
- Error message uses `tool.displayName` instead of `tool.rawValue` for better user-facing messages
- Workflow yields progress at each step: preparing → installing → verifying → complete
- On error, yields `.failed` detail before throwing

---

## Phase 4: Update DependencyStatusModel

**Status:** Completed

**Goal:** Refactor model to use workflows and enum-based state.

**Files:**
- Modify: `Sources/app-mac/Models/DependencyStatusModel.swift`
- Modify: `Package.swift` (add service-setup dependency to app-mac)

**Changes:**

Model now uses workflows with enum-based state and backward-compatible properties:
```swift
import sdk_cli
import service_setup
import Foundation
import Observation

@MainActor
@Observable
public final class DependencyStatusModel {
    // MARK: - State

    public enum ModelState: Sendable {
        case uninitialized
        case checking(prior: DependencySnapshot?)
        case ready(DependencySnapshot)
        case installing(CLITool, prior: DependencySnapshot?)
    }

    public private(set) var state: ModelState = .uninitialized

    // MARK: - Dependencies

    public let cliClient: CLIClient
    private let statusWorkflow: DependencyStatusWorkflow
    private let installWorkflow: DependencyInstallWorkflow

    // MARK: - Init

    public init(cliClient: CLIClient) {
        self.cliClient = cliClient
        self.statusWorkflow = DependencyStatusWorkflow(cliClient: cliClient)
        self.installWorkflow = DependencyInstallWorkflow(cliClient: cliClient)
    }

    // MARK: - Public API

    public func checkAll() async { ... }
    public func install(_ tool: CLITool) async { ... }

    // MARK: - Convenience Accessors

    public func status(for tool: CLITool) -> CLIToolStatus? { ... }
    public var isChecking: Bool { ... }
    public func isInstalling(_ tool: CLITool) -> Bool { ... }

    // MARK: - Backward-Compatible Properties

    public var homebrewStatus: DependencyUIState { ... }
    public var nodejsStatus: DependencyUIState { ... }
    public var dockerStatus: DependencyUIState { ... }
    public var awsCLIStatus: DependencyUIState { ... }
    public var cdkStatus: DependencyUIState { ... }
    public var githubCLIStatus: DependencyUIState { ... }

    // MARK: - Backward-Compatible Methods

    public func checkHomebrew() async { ... }
    public func checkNodeJS() async { ... }
    public func checkDocker() async { ... }
    public func checkAWSCLI() async { ... }
    public func checkCDK() async { ... }
    public func checkGitHubCLI() async { ... }
}
```

**Technical Notes:**
- Single `state` property with enum cases
- Prior snapshot preserved during operations
- `DependencyUIState` enum retained for backward compatibility with views
- Backward-compatible computed properties map from new state to old `DependencyUIState`
- Backward-compatible methods use workflow to check single tools
- `cliClient` property kept public (required by existing `DependencyView`)
- Phase 6 (app-mac dependency) completed as part of this phase since it was required

**Verification:** `swift build` succeeds.

**Implementation Notes:**
- Backward-compatible properties compute `DependencyUIState` from the new `ModelState`
- When checking or installing, returns `.checking` state appropriately
- `checkSingleTool` method merges new results with existing snapshot

---

## Phase 5: Update Views

**Status:** Not Started

**Goal:** Update SetupViews and ServicesView to use new state pattern.

**Files:**
- Modify: `Sources/app-mac/UI/SetupViews.swift`
- Modify: `Sources/app-mac/UI/LocalService/ServicesView.swift`

**Changes:**

1. Add helper computed properties to `DependencyStatusModel`:
```swift
extension DependencyStatusModel {
    public func status(for tool: CLITool) -> CLIToolStatus? {
        state.snapshot?.status(for: tool)
    }

    public var isChecking: Bool {
        if case .checking = state { return true }
        return false
    }

    public func isInstalling(_ tool: CLITool) -> Bool {
        if case .installing(let t, _) = state { return t == tool }
        return false
    }
}
```

2. Update `ServicesView` status badge:
```swift
// Old:
// model.dependencyStatusModel.dockerStatus

// New:
let status = model.dependencyStatusModel.status(for: .docker)
// status?.isInstalled, model.dependencyStatusModel.isChecking, etc.
```

3. Update `DependencyView` in SetupViews:
```swift
// Map CLITool to the view's Dependency enum
// Or update Dependency enum to use CLITool cases
```

**Technical Notes:**
- Need to map between UI `Dependency` enum and service layer `CLITool`
- Consider consolidating enums or adding bridging
- Status badge logic changes from individual properties to snapshot lookup

**Verification:** `swift build` succeeds. Mac app shows correct status.

---

## Phase 6: Add app-mac Dependency on service-setup

**Status:** Completed (as part of Phase 4)

**Goal:** Update Package.swift to wire up the dependency.

**Files:**
- Modify: `Package.swift`

**Changes:**
Added `service-setup` dependency to `app-mac` target in Package.swift.

**Verification:** `swift build` succeeds.

**Implementation Notes:**
- Completed as part of Phase 4 since it was required for the model to import service-setup types

---

## Critical Files

| File | Changes |
|------|---------|
| `Package.swift` | Add service-setup target and dependency |
| `Sources/service-setup/CLITool.swift` | New - enum for CLI tools |
| `Sources/service-setup/CLIToolStatus.swift` | New - status struct |
| `Sources/service-setup/DependencySnapshot.swift` | New - snapshot type |
| `Sources/service-setup/DependencyStatusWorkflow.swift` | New - status checking workflow |
| `Sources/service-setup/DependencyInstallWorkflow.swift` | New - installation workflow |
| `Sources/app-mac/Models/DependencyStatusModel.swift` | Major refactor - use workflows |
| `Sources/app-mac/UI/SetupViews.swift` | Update to use new state pattern |
| `Sources/app-mac/UI/LocalService/ServicesView.swift` | Update status access |

---

## Dependencies

```
service-setup
  ├── sdk-cli
  ├── sdk-cli-brew
  ├── sdk-cli-node
  ├── sdk-cli-docker
  ├── sdk-aws (for CDKClient, AWSCLIClient)
  └── sdk-github (for GitHubCLIClient)

app-mac
  └── service-setup (new dependency)
```

---

## Testing Considerations

1. **DependencyStatusWorkflow**: Test that it yields progress for each tool
2. **DependencyInstallWorkflow**: Test success and failure cases
3. **DependencyStatusModel**: Test state transitions
4. **Views**: Manual testing to verify status display

---

## Success Criteria

1. `swift build` succeeds
2. Mac app shows dependency statuses correctly
3. Model uses enum-based state (no more 6 individual properties)
4. Workflows can be reused by CLI if needed
5. Architecture follows layered pattern: App → Service → SDK
