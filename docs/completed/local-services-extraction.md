# Local Services Extraction

Extract shared local service management (PostgreSQL, MinIO, DynamoDB) into a dedicated `LocalServicesFeature` with a `LocalServicesModel` that can be used as a child model by both `DeployXcodeModel` and `DeployLinuxModel`.

## Problem

`DeployLinuxModel` and `DeployXcodeModel` both manage local Docker services (PostgreSQL, MinIO, DynamoDB) with nearly identical code. The only difference is configuration (ports, container names, storage paths).

### Current Duplication

**Duplicate Use Cases:**
- `LinuxStartServicesUseCase` ≈ `XcodeStartServicesUseCase`
- `LinuxStopServicesUseCase` ≈ `XcodeStopServicesUseCase`

**Duplicate State Types:**
- `LinuxSnapshot` ≈ `XcodeSnapshot` (identical structure)
- `LinuxUseCaseState.ServicesProgress` ≈ `XcodeUseCaseState.ServicesProgress` (identical)

**Duplicate Model Methods** (in `DeployLinuxModel` and `DeployXcodeModel`):
- `startAllServices()`, `stopAllServices()`
- `startS3()`, `stopS3()`
- `startDatabase()`, `stopDatabase()`
- `startDynamoDB()`, `stopDynamoDB()`
- `createBucket()`
- Data directory accessors (`s3DataDirectory`, `postgresDataDirectory`, `dynamodbDataDirectory`)

### What Actually Differs

Only **configuration** differs between Xcode and Linux workflows:

| Service | Xcode | Linux |
|---------|-------|-------|
| PostgreSQL port | 5432 | 5433 |
| PostgreSQL container | `postgres-xcode` | `postgres-linux` |
| MinIO S3 port | 9000 | 9002 |
| MinIO console port | 9001 | 9003 |
| MinIO container | `minio-xcode` | `minio-linux` |
| DynamoDB port | 8000 | 8001 |
| DynamoDB container | `dynamodb-xcode` | `dynamodb-linux` |
| Storage path prefix | `*/xcode-data` | `*/linux-data` |
| Network name | `lambda-xcode` | from `LinuxContainerConfig` |

## Solution

Create a unified `LocalServicesFeature` with configuration-driven use cases and a `LocalServicesModel` that parent models can own as a child.

### New Architecture

```
DeployXcodeModel                    DeployLinuxModel
       │                                   │
       └──────┬────────────────────────────┘
              │ owns
              ▼
      LocalServicesModel  ←─── new child model
              │ uses
              ▼
      LocalServicesFeature ←─── new feature
       (StartServicesUseCase, StopServicesUseCase, StatusUseCase)
              │ uses
              ▼
    LocalServicesConfiguration ←─── new config type
       (.xcode or .linux presets)
```

### Key Design Decisions

1. **Configuration-Driven**: A single `LocalServicesConfiguration` struct captures all the differences (ports, container names, storage keys, network name).

2. **Child Model Pattern**: `LocalServicesModel` follows the model composition pattern from `layered-architecture.md`. Parent models hold it as a property and delegate service operations.

3. **Unified State Types**: Replace `LinuxUseCaseState.ServicesProgress` and `XcodeUseCaseState.ServicesProgress` with a shared `LocalServicesUseCaseState`.

4. **Parent Models Keep Lambda Logic**: Build and Lambda lifecycle operations remain in `DeployXcodeModel` and `DeployLinuxModel` since those differ significantly (native process vs Docker container).

## Implementation Phases

### Phase 1: Create LocalServicesFeature with Unified Use Cases ✅ COMPLETED

Create `Sources/features/LocalServicesFeature/` with configuration-driven use cases.

**New Files:**

```
Sources/features/LocalServicesFeature/
├── LocalServicesConfiguration.swift    # Configuration type with .xcode/.linux presets
├── usecases/
│   ├── StartServicesUseCase.swift      # Unified start use case
│   ├── StopServicesUseCase.swift       # Unified stop use case
│   └── ServicesStatusUseCase.swift     # Unified status use case
└── services/
    └── Models/
        ├── LocalServicesSnapshot.swift     # Unified snapshot type
        └── LocalServicesUseCaseState.swift # Unified use case state
```

**LocalServicesConfiguration:**

```swift
public struct LocalServicesConfiguration: Sendable {
    public let postgresConfig: PostgreSQLClient.Config
    public let minioConfig: MinIOClient.Config
    public let dynamodbConfig: DynamoDBClient.Config
    public let networkName: String
    public let postgresStorageKey: any StoragePathKey.Type
    public let minioStorageKey: any StoragePathKey.Type
    public let dynamodbStorageKey: any StoragePathKey.Type

    public static let xcode = LocalServicesConfiguration(
        postgresConfig: .xcode,
        minioConfig: .xcode,
        dynamodbConfig: .xcode,
        networkName: "lambda-xcode",
        postgresStorageKey: PostgreSQLXcodeStorageKey.self,
        minioStorageKey: MinIOXcodeStorageKey.self,
        dynamodbStorageKey: DynamoDBLocalXcodeStorageKey.self
    )

    public static func linux(workingDirectory: String) -> LocalServicesConfiguration {
        let config = LinuxContainerConfig.default(workingDirectory: workingDirectory)
        return LocalServicesConfiguration(
            postgresConfig: .linux,
            minioConfig: .linux,
            dynamodbConfig: .linux,
            networkName: config.networkName,
            postgresStorageKey: PostgreSQLLinuxStorageKey.self,
            minioStorageKey: MinIOLinuxStorageKey.self,
            dynamodbStorageKey: DynamoDBLocalLinuxStorageKey.self
        )
    }
}
```

**StartServicesUseCase (unified):**

```swift
public struct StartServicesUseCase: StreamingUseCase {
    private let configuration: LocalServicesConfiguration
    private let postgresClient: PostgreSQLClient
    private let minioClient: MinIOClient
    private let dynamodbClient: DynamoDBClient
    // ... same logic as current implementations, but configuration-driven
}
```

**Phase 1 Technical Notes:**

- Updated `StoragePathKey` protocol to inherit from `Sendable` to eliminate warnings about metatype properties in `LocalServicesConfiguration`
- Created `LocalServicesConfiguration` with both `.xcode` static property and `.linux` static property (plus `linux(networkName:)` factory for custom networks)
- `LocalServicesSnapshot` contains only Docker service states (s3, postgres, dynamodb) - no Lambda state since Lambda management stays in parent models
- `LocalServicesUseCaseState` uses unified `ServicesProgress` and `StatusProgress` types
- Use cases follow the existing pattern with `Components` struct and `create(workingDirectory:configuration:)` factory
- Added `LocalServicesFeature` target to Package.swift with appropriate dependencies

### Phase 2: Create LocalServicesModel ✅ COMPLETED

Create the child model in the app layer.

**New File:** `Sources/apps/MacApp/Models/LocalServicesModel.swift`

```swift
@MainActor
public class LocalServicesModel {
    public private(set) var state: ModelState = .uninitialized
    private let configuration: LocalServicesConfiguration
    private let storageService: LocalStorageService

    public init(configuration: LocalServicesConfiguration) {
        self.configuration = configuration
        self.storageService = LocalStorageService()
        Task { await refresh() }
    }

    // Service management methods
    public func startAllServices() async throws { ... }
    public func stopAllServices() async throws { ... }
    public func startS3() async throws { ... }
    public func stopS3() async throws { ... }
    public func startDatabase() async throws { ... }
    public func stopDatabase() async throws { ... }
    public func startDynamoDB() async throws { ... }
    public func stopDynamoDB() async throws { ... }
    public func createBucket(bucketName: String?) async throws { ... }

    // Data directories
    public var s3DataDirectory: String { ... }
    public var postgresDataDirectory: String { ... }
    public var dynamodbDataDirectory: String { ... }

    // Status
    public func refresh() async { ... }

    public enum ModelState: Equatable {
        case uninitialized
        case loading(prior: LocalServicesSnapshot?)
        case ready(LocalServicesSnapshot)
        case operating(LocalServicesUseCaseState, prior: LocalServicesSnapshot?)
    }
}
```

**Phase 2 Technical Notes:**

- `LocalServicesModel` takes both `workingDirectory` and `configuration` in its initializer (workingDirectory is needed by use case factory methods)
- Added `LocalServicesFeature` as a dependency to `MacApp` in Package.swift
- Model follows the same state machine pattern as `DeployXcodeModel` and `DeployLinuxModel` for consistency
- `ModelState.init(error:preserving:)` falls back to `.stopped` snapshot if prior is nil to avoid unrecoverable states
- Data directory accessors delegate to `LocalStorageService` using the configuration's storage keys
- `createBucket` reuses the `StartServicesUseCase.Components` to access the configured `MinIOClient`

### Phase 3: Integrate LocalServicesModel into Parent Models ✅ COMPLETED

Update `DeployXcodeModel` and `DeployLinuxModel` to own `LocalServicesModel` as a child. Service management methods delegate to the child model.

**Before (DeployXcodeModel):**
```swift
public class DeployXcodeModel: LocalService {
    // Duplicate service management code
    public func startAllServices() async throws { ... }
    public func stopAllServices() async throws { ... }
    public func startS3() async throws { ... }
    public func stopS3() async throws { ... }
    // ... many more duplicate methods
}
```

**After (DeployXcodeModel):**
```swift
public class DeployXcodeModel: LocalService {
    public let servicesModel: LocalServicesModel

    public init(workingDirectory: String) {
        self.servicesModel = LocalServicesModel(
            workingDirectory: workingDirectory,
            configuration: .xcode
        )
        // ...
    }

    // Delegation methods for protocol conformance
    public func startAllServices() async throws {
        try await servicesModel.startAllServices()
    }
    // ... other service methods delegate to servicesModel

    // Parent keeps Lambda-specific logic
    public func startLambda(output: CLIOutputStream?) async throws { ... }
    public func stopLambda(output: CLIOutputStream?) async throws { ... }
    public func build(clean: Bool, output: CLIOutputStream?) async throws { ... }
}
```

**Phase 3 Technical Notes:**

- Both `DeployXcodeModel` and `DeployLinuxModel` now own a `LocalServicesModel` as a public child property
- Service management methods (`startAllServices`, `stopAllServices`, `startS3`, `stopS3`, `startDatabase`, `stopDatabase`, `startDynamoDB`, `stopDynamoDB`, `createBucket`) delegate to the child model
- Data directory accessors (`s3DataDirectory`, `postgresDataDirectory`, `dynamodbDataDirectory`) delegate to the child model
- Parent models continue to conform to `LocalService` protocol for backward compatibility with existing views
- Removed direct SDK client properties (`postgresClient`, `minioClient`, `dynamodbClient`) from `DeployLinuxModel` - now managed by `LocalServicesModel`
- Removed `storageService` property from both parent models - now managed by `LocalServicesModel`
- Lambda-specific operations (build, start/stop Lambda, start/stop with services) remain in parent models since they differ between Xcode (native process) and Linux (Docker container)

### Phase 4: Delete Duplicate Use Cases ✅ COMPLETED

Remove the now-unused duplicate use cases:

**Files Replaced with Backwards-Compatible Wrappers:**
- `Sources/features/DeployLinuxFeature/usecases/LinuxStartServicesUseCase.swift`
- `Sources/features/DeployLinuxFeature/usecases/LinuxStopServicesUseCase.swift`
- `Sources/features/DeployXcodeFeature/usecases/XcodeStartServicesUseCase.swift`
- `Sources/features/DeployXcodeFeature/usecases/XcodeStopServicesUseCase.swift`

Updated references in remaining use cases (`LinuxStartAllUseCase`, `XcodeStartAllUseCase`, etc.) to use the new unified use cases.

**Phase 4 Technical Notes:**

- The "All" use cases (`XcodeStartAllUseCase`, `XcodeStopAllUseCase`, `LinuxStartAllUseCase`, `LinuxStopAllUseCase`) now import `LocalServicesFeature` and use `StartServicesUseCase`/`StopServicesUseCase` directly with the appropriate configuration (`.xcode` or `.linux`)
- Added `LocalServicesFeature` as a dependency to both `DeployXcodeFeature` and `DeployLinuxFeature` in Package.swift
- Added `.creatingBucket` case to `LinuxUseCaseState.ServicesProgress.Step` to match `XcodeUseCaseState.ServicesProgress.Step` for consistency
- Each "All" use case includes a `mapServicesStep()` helper to convert `LocalServicesUseCaseState.ServicesProgress.Step` to the parent's state type
- **Backwards-compatible wrappers**: Rather than deleting the old use case files, they were replaced with thin wrapper structs that:
  - Maintain the old `.create(workingDirectory:)` API signature (without `configuration:` parameter)
  - Delegate to the unified use cases with the appropriate configuration (`.xcode` or `.linux`)
  - Adapt the stream output from `LocalServicesUseCaseState` to `XcodeUseCaseState` or `LinuxUseCaseState`
  - This allows CLI commands to continue working unchanged until Phase 5
- The wrappers include clear deprecation comments noting they will be removed in Phase 5

### Phase 5: Update CLI Commands ✅ COMPLETED

Update CLI commands to use the new unified use cases:

- `LinuxStartServicesCommand` → use `StartServicesUseCase` with `.linux` config
- `XcodeStartServicesCommand` → use `StartServicesUseCase` with `.xcode` config

**Phase 5 Technical Notes:**

- Added `LocalServicesFeature` as a dependency to `CLIApp` in Package.swift
- Updated all Linux service CLI commands (`StartDatabaseCommand`, `StopDatabaseCommand`, `StartDynamoDBCommand`, `StopDynamoDBCommand`, `StartS3Command`, `StopS3Command`) to use `StartServicesUseCase`/`StopServicesUseCase` with `.linux` configuration
- Updated all Xcode service CLI commands (`StartDatabaseCommand`, `StopDatabaseCommand`, `StartDynamoDBCommand`, `StopDynamoDBCommand`, `StartS3Command`, `StopS3Command`) to use `StartServicesUseCase`/`StopServicesUseCase` with `.xcode` configuration
- Added unified progress print functions (`printLocalServicesStartProgress`, `printLocalServicesStopProgress`) to handle `LocalServicesUseCaseState`
- Deleted the backwards-compatible wrapper use cases that were added in Phase 4:
  - `LinuxStartServicesUseCase.swift` (wrapper)
  - `LinuxStopServicesUseCase.swift` (wrapper)
  - `XcodeStartServicesUseCase.swift` (wrapper)
  - `XcodeStopServicesUseCase.swift` (wrapper)
- The "All" use cases (`LinuxStartAllUseCase`, `LinuxStopAllUseCase`, `XcodeStartAllUseCase`, `XcodeStopAllUseCase`) were already updated in Phase 4 to use unified use cases directly

## Benefits

1. **Eliminates ~500 lines of duplicate code** across use cases and models
2. **Single source of truth** for service management logic
3. **Configuration-driven** - easy to add new workflows (e.g., CI/CD)
4. **Follows architecture patterns** - child model composition, use case streaming
5. **Easier maintenance** - bug fixes apply to both workflows automatically

## Files Changed Summary

### New Files (Phase 1-2)
- `Sources/features/LocalServicesFeature/LocalServicesConfiguration.swift`
- `Sources/features/LocalServicesFeature/usecases/StartServicesUseCase.swift`
- `Sources/features/LocalServicesFeature/usecases/StopServicesUseCase.swift`
- `Sources/features/LocalServicesFeature/usecases/ServicesStatusUseCase.swift`
- `Sources/features/LocalServicesFeature/services/Models/LocalServicesSnapshot.swift`
- `Sources/features/LocalServicesFeature/services/Models/LocalServicesUseCaseState.swift`
- `Sources/apps/MacApp/Models/LocalServicesModel.swift`

### Modified Files (Phase 3)
- `Sources/apps/MacApp/Models/DeployXcodeModel.swift` - delegate to child model
- `Sources/apps/MacApp/Models/DeployLinuxModel.swift` - delegate to child model
- `Package.swift` - add `LocalServicesFeature` target

### Deleted Files (Phase 5)
- `Sources/features/DeployLinuxFeature/usecases/LinuxStartServicesUseCase.swift` - replaced by unified `StartServicesUseCase`
- `Sources/features/DeployLinuxFeature/usecases/LinuxStopServicesUseCase.swift` - replaced by unified `StopServicesUseCase`
- `Sources/features/DeployXcodeFeature/usecases/XcodeStartServicesUseCase.swift` - replaced by unified `StartServicesUseCase`
- `Sources/features/DeployXcodeFeature/usecases/XcodeStopServicesUseCase.swift` - replaced by unified `StopServicesUseCase`

### Modified Files (Phase 4)
- `Sources/features/DeployXcodeFeature/usecases/XcodeStartAllUseCase.swift` - uses unified `StartServicesUseCase`
- `Sources/features/DeployXcodeFeature/usecases/XcodeStopAllUseCase.swift` - uses unified `StopServicesUseCase`
- `Sources/features/DeployLinuxFeature/usecases/LinuxStartAllUseCase.swift` - uses unified `StartServicesUseCase`
- `Sources/features/DeployLinuxFeature/usecases/LinuxStopAllUseCase.swift` - uses unified `StopServicesUseCase`
- `Sources/features/DeployLinuxFeature/services/Models/LinuxDeploymentState.swift` - added `.creatingBucket` to `ServicesProgress.Step`
- `Package.swift` - added `LocalServicesFeature` dependency to `DeployXcodeFeature` and `DeployLinuxFeature`

### Modified Files (Phase 5)
- `Sources/apps/CLIApp/Commands/DeployLinux/DeployLinuxCommand.swift` - uses unified use cases with `.linux` configuration
- `Sources/apps/CLIApp/Commands/DeployLinux/DeployLinuxProgressPrinters.swift` - added `printLocalServicesStartProgress` and `printLocalServicesStopProgress`
- `Sources/apps/CLIApp/Commands/DeployXcode/DeployXcodeCommand.swift` - uses unified use cases with `.xcode` configuration
- `Sources/apps/CLIApp/Commands/DeployXcode/DeployXcodeProgressPrinters.swift` - imports `LocalServicesFeature`
- `Package.swift` - added `LocalServicesFeature` dependency to `CLIApp`

## Open Questions

1. **Should `LocalServicesModel` also handle the "start with services" composite operations?** Currently `LinuxStartAllUseCase` and `XcodeStartAllUseCase` start services AND Lambda. Should the child model only handle services, leaving Lambda orchestration to parents?

   **Recommendation:** Yes, keep Lambda orchestration in parent models. The child model should only manage Docker services (PostgreSQL, MinIO, DynamoDB). This maintains clear separation since Lambda startup differs significantly between Xcode (native process) and Linux (Docker container).

2. **Should we create a `LocalServicesService` in `services/` instead of putting config in the feature?** The configuration could live in `DeployLocalService` since storage keys are already there.

   **Recommendation:** Put `LocalServicesConfiguration` in `DeployLocalService` since it's a configuration/model type. Use cases stay in the feature.
