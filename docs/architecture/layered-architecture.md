# Layered Architecture

This document defines the layered architecture for organizing Swift targets across the project.

## Overview

The project uses a three-layer architecture where dependencies flow downward:

```
┌─────────────────────────────────────────────────────────────┐
│                          APP                                 │
│          app-lambda  ·  app-mac  ·  app-cli                  │
│                                                              │
│   Entry points, I/O, @Observable models (where needed)       │
└────────────────────────┬────────────────────────────────────┘
                         │ uses
                         ▼
┌─────────────────────────────────────────────────────────────┐
│                       SERVICE                                │
│              service-deploy  ·  service-storage              │
│                                                              │
│   Workflows returning AsyncThrowingStream                    │
└────────────────────────┬────────────────────────────────────┘
                         │ uses
                         ▼
┌─────────────────────────────────────────────────────────────┐
│                         SDK                                  │
│        sdk-aws  ·  sdk-github  ·  sdk-cli  ·  sdk-client     │
│                                                              │
│   Stateless clients and utilities                            │
└─────────────────────────────────────────────────────────────┘
```

## Layer Definitions

### Apps (`app-*`)

Entry points that handle I/O.

- Executable targets (apps, CLI tools, Lambda handlers)
- Platform-specific I/O (SwiftUI views, terminal output, Lambda encoding)
- `@Observable` models live here when needed (e.g., app-mac for SwiftUI)
- CLI commands are parallel to Mac models—both are app-layer constructs
- Minimal business logic; focus on I/O and calling workflows

### Services (`service-*`)

Workflows that orchestrate multi-step operations.

- Workflows are structs returning `AsyncThrowingStream<Progress, Error>`
- Coordinate multiple SDK clients
- App-specific business logic
- **Not** `@Observable`—that belongs in the app layer

### SDKs (`sdk-*`)

Stateless reusable utilities.

- Wrap external tools and services
- **Stateless**—no internal state management
- Operations return `AsyncThrowingStream` for progress or values for one-shot queries
- Can be extracted to separate packages

## Key Principles

### Stateless SDKs

SDK clients don't maintain internal state. Each method call is independent.

```swift
public actor CDKClient {
    // Returns stream—no internal state tracking
    public nonisolated func deployStream(options: DeployOptions) -> AsyncThrowingStream<CDKProgress, Error>

    // Returns value directly
    public func getStackOutputs(stackName: String) async throws -> [String: String]
}
```

### Workflows for Orchestration

Multi-step operations live in workflows that yield progress via streams.

```swift
public struct DeployWorkflow {
    public func run(options: Options) -> AsyncThrowingStream<Progress, Error> {
        AsyncThrowingStream { continuation in
            Task {
                // Coordinate SDK clients, yield progress
                for try await cdkProgress in cdkClient.deployStream(options: opts) {
                    continuation.yield(...)
                }
                continuation.finish()
            }
        }
    }
}
```

### @Observable Only in App Layer

`@Observable` models exist only where UI binding is needed (app-mac). They consume workflow streams.

### Minimal Logic in Models (MV Pattern)

Models should contain minimal logic—their role is to monitor workflow streams and update state for the UI. Business logic belongs in:

- **Services (Workflows)**: Orchestration, multi-step operations, app-specific logic
- **SDKs (Clients)**: Reusable operations, external service interactions

This keeps models thin and testable, with clear separation between state management and business logic.

```swift
// app-mac model consumes workflow
@MainActor @Observable
class DeploymentModel {
    func deploy() {
        Task {
            for try await progress in workflow.run(options: opts) {
                self.activeWorkflow = .deploy(progress)
            }
        }
    }
}

// app-cli uses workflow directly
struct DeployCommand: AsyncParsableCommand {
    func run() async throws {
        for try await progress in workflow.run(options: opts) {
            print(progress)
        }
    }
}
```

## Data Flow

**CLI**: `Workflow stream → print progress`

**Mac App**: `Workflow stream → @Observable model → View`

## Dependency Rules

1. **Apps** depend on Services and SDKs
2. **Services** depend on other Services and SDKs
3. **SDKs** depend only on other SDKs or external packages
4. Never depend upward

## When to Create a New Target

**SDK**: Reusable, no app-specific logic, wraps external tool/service

**Service**: Orchestrates multiple SDKs, app-specific workflow

**App**: Entry point, UI, platform-specific I/O
