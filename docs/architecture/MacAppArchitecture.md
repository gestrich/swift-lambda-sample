# Mac App Architecture

## Overview

The app follows a **Model-View (MV)** architecture pattern with Services.

## Project Structure

```
MacApp/Models/                           # Observable state (UI binding)
├── AppModel.swift                       # Root model, composes all services
├── RemoteModel.swift                    # AWS deployment state
├── XcodeLocalModel.swift                # Native macOS local dev state
├── LinuxLocalModel.swift                # Linux container local dev state
├── DependencyStatusModel.swift          # Dependency checker state
└── LocalServicesModel.swift             # Local services state wrapper

SwiftDeploy/Services/                    # Stateless business logic
├── RemoteDeploymentService.swift        # AWS deployment operations
├── XcodeLocalDevelopmentService.swift   # Native macOS local dev operations
├── LinuxLocalDevelopmentService.swift   # Linux container local dev operations
├── DependencyCheckerService.swift       # Dependency checking operations
└── ... (other services)

SwiftDeploy/LambdaServices/              # Protocols and shared types
├── LambdaService.swift                  # Base protocol + DeploymentStatus
└── LocalService.swift                   # Extended protocol for local services
```

## Models

Models hold app state and serve as the API that views interact with.

- Conform to `@Observable`
- Views observe models directly
- Contain minimal business logic
- Delegate work to services
- Can be composed from other models

### AppModel

A top-level `AppModel` serves as the root, composing all domain models.

```swift
@Observable
class AppModel {
    let remoteService: RemoteModel
    let xcodeLocalService: XcodeLocalModel
    let linuxLocalService: LinuxLocalModel
    let dependencyStatusModel: DependencyStatusModel

    var mode: ConnectionMode  // Current active mode
}
```

### Domain Models

Models are thin wrappers that hold observable state and delegate to stateless services:

```swift
@MainActor
class XcodeLocalModel: LocalService {
    private let developmentService: XcodeLocalDevelopmentService

    // Observable state for UI
    let buildState = BuildState()
    let lambdaState = LambdaState()
    private let statusSubject = CurrentValueSubject<DeploymentStatus, Never>(.stopped)

    // Delegate to service
    func startLambda() async throws {
        lambdaState.startLambda()
        try await developmentService.startLambda()
        lambdaState.markRunning()
    }
}
```

### Optional Models

Some models are defined as optional. These represent state that only exists after configuration or user action.

```swift
@Observable
class AppModel {
    let settingsModel: SettingsModel
    var syncModel: SyncModel?  // Only exists after user configures sync
}
```

## Services

Services are **stateless actors** that handle business logic and external interactions.

- No UI state (no `@Observable`, no Combine publishers)
- Orchestrate sub-services (Docker, CLI, AWS)
- Return results, don't store them
- Can be used directly by CLI (no MainActor requirement)

```swift
public actor XcodeLocalDevelopmentService {
    private let dockerService: DockerService
    private let postgresService: PostgreSQLService
    private let minioService: MinIOService

    public func startWithServices() async throws {
        try await startAllServices()
        try await setupNetworkAndBucket()
        try await startLambda()
    }

    public func status() async throws -> DeploymentStatus {
        // Query actual state, return result
    }
}
```

## Data Flow

```
MacApp View → Model (observable state) → Service (stateless) → External
CLI Command → Service (stateless) → External
```

- **MacApp**: Views observe models. Models call services. Services return data.
- **CLI**: Commands call services directly. Services return data. Commands print results.

## Protocols

### LambdaService

Base protocol for all Lambda services (remote and local). Provides:
- Endpoint configuration
- Status publishing (Combine)
- Testing capabilities

### LocalService

Extended protocol for local services (Xcode and Linux). Adds:
- Docker service management (PostgreSQL, MinIO, DynamoDB)
- Build operations
- Lambda lifecycle management
