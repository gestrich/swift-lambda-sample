# Layered Architecture

This document defines the layered architecture and naming conventions for organizing Swift targets across the project.

## Overview

The project uses a three-layer architecture where dependencies flow downward:

```
┌─────────────────────────────────────────────────────────┐
│                     FEATURES                            │
│   feature-mac  ·  feature-cli  ·  feature-lambda        │
│                                                         │
│   Executables, UI, app state                            │
└────────────────────────┬────────────────────────────────┘
                         │ depends on
                         ▼
┌─────────────────────────────────────────────────────────┐
│                     SERVICES                            │
│   service-deploy  ·  service-storage  ·  service-*      │
│                                                         │
│   Business logic, stateless operations                  │
└────────────────────────┬────────────────────────────────┘
                         │ depends on
                         ▼
┌─────────────────────────────────────────────────────────┐
│                       SDKs                              │
│      sdk-cdk  ·  sdk-git  ·  sdk-*                      │
│                                                         │
│   Reusable, app-agnostic utilities                      │
└─────────────────────────────────────────────────────────┘
```

## Layer Definitions

### Features (`feature-*`)

Features are the front-ends of the application—the executables that users interact with.

**Naming**: `feature-mac`, `feature-cli`, `feature-lambda`, `feature-ios`

**Characteristics**:
- Executable targets (apps, command-line tools, Lambda handlers)
- Contain UI code (SwiftUI, AppKit, terminal output)
- Hold application state via observable models
- Minimal business logic—delegate to services
- Platform-specific code lives here

**State Management**:
- Features own the app state
- State is held in `@Observable` models (see [MacAppArchitecture.md](MacAppArchitecture.md))
- Models are thin wrappers that delegate to stateless services

**Example**:
```swift
// feature-mac/Models/AppModel.swift
@Observable
class AppModel {
    let deployService: DeploymentService  // service layer

    // Observable state for UI binding
    var deploymentStatus: DeploymentStatus = .idle
    var isDeploying = false

    func deploy() async throws {
        isDeploying = true
        defer { isDeploying = false }
        deploymentStatus = try await deployService.deploy()
    }
}
```

### Services (`service-*`)

Services contain business logic specific to this application. They are independent of any particular front-end.

**Naming**: `service-deploy`, `service-server`, `service-local-storage`

**Characteristics**:
- Library targets (not executables)
- Implemented as actors, structs, or classes
- Stateless by default—state lives in the feature layer
- Multiple features can depend on the same service
- Contain app-specific business logic
- Return results via method returns or `AsyncSequence` for progress

**State Exceptions**:
When a service manages complex state machines or long-running operations where transactional semantics don't apply, the service may hold internal state. Prefer returning `AsyncSequence` from methods for operations with progress.

**Example**:
```swift
// service-deploy/RemoteDeploymentService.swift
public actor RemoteDeploymentService {
    private let awsService: AWSService       // sdk layer
    private let githubService: GitHubService // sdk layer

    public func deploy() async throws -> DeploymentStatus {
        try await awsService.runCDK()
        try await githubService.triggerWorkflow()
        return .deployed
    }

    // Returns progress as AsyncSequence (preferred over internal state)
    public func deployWithProgress() -> AsyncThrowingStream<DeploymentProgress, Error> {
        // ...
    }
}
```

### SDKs (`sdk-*`)

SDKs are reusable utilities that are not specific to this application. They could be extracted into separate open-source packages.

**Naming**: `sdk-cli`, `sdk-client`, `sdk-docker`

**Characteristics**:
- Library targets
- No app-specific business logic
- Return plain structs/enums (consumed by both service and feature layers)
- Stateless
- Candidates for open-source extraction
- May wrap third-party dependencies

**Example**:
```swift
// sdk-cli/ProcessRunner.swift
public struct ProcessRunner {
    public func run(_ command: String, arguments: [String]) async throws -> ProcessResult {
        // Generic process execution—no app-specific logic
    }
}

public struct ProcessResult {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String
}
```

## Dependency Rules

1. **Features** may depend on **Services** and **SDKs**
2. **Services** may depend on other **Services** and **SDKs**
3. **SDKs** may depend on other **SDKs** or external packages only
4. **Never** depend upward (services cannot depend on features)

```
feature-mac ──→ service-deploy ──→ service-aws ──→ sdk-cli
     │              │                   │
     │              │                   └──→ service-storage
     │              │
     │              └──→ sdk-cli
     │
     └──→ sdk-cli (direct SDK access allowed)
```

## Current Targets Mapping

| Current Target      | Proposed Name           | Layer   |
|---------------------|-------------------------|---------|
| `SwiftLambda`       | `feature-lambda`        | Feature |
| `MacApp`            | `feature-mac`           | Feature |
| `SwiftDeployCLI`    | `feature-cli`           | Feature |
| `SwiftDeploy`       | `service-deploy`        | Service |
| `LocalStorageService` | `service-storage`     | Service |
| `CLIKit`            | `sdk-cli`               | SDK     |
| `CLIMacros`         | `sdk-cli-macros`        | SDK     |
| `Client`            | `sdk-client`            | SDK     |

## Shared Types

Shared types (DTOs, API models, enums) should live in the SDK layer so they can be consumed by any layer without introducing upward dependencies.

```swift
// sdk-api-types/User.swift
public struct User: Codable, Sendable {
    public let id: UUID
    public let email: String
    public let firstName: String
}
```

Both `feature-mac` and `service-server` can import `sdk-api-types` without depending on each other.

## When to Create a New Target

**Create a new SDK when**:
- The code has no app-specific business logic
- It could be useful in unrelated projects
- You're wrapping a third-party dependency

**Create a new Service when**:
- The code contains business logic specific to this app
- Multiple features need the same functionality
- You're orchestrating multiple SDKs for an app-specific workflow

**Keep code in a Feature when**:
- It's UI-specific
- It's platform-specific (macOS-only, Lambda-only)
- It manages app state

## Testing

Each layer has its own test target:
- `feature-*-tests` — UI/integration tests
- `service-*-tests` — Business logic tests (mock SDKs)
- `sdk-*-tests` — Unit tests (minimal mocking)

Services are easily testable because SDKs can be injected as protocols.
