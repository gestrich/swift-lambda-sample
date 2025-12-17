# Refactor Container Services to SDK Layer

Move PostgreSQLLocalService, MinIOService, and DynamoDBLocalService from `c-service-deploy-local` to `d-sdk-cli-docker`, converting them to Sendable structs and renaming to use "Client" naming.

## Summary of Changes

| Current (c-service-deploy-local) | New (d-sdk-cli-docker) |
|----------------------------------|------------------------|
| `actor PostgreSQLLocalService` | `struct PostgreSQLClient: Sendable` |
| `actor MinIOService` | `struct MinIOClient: Sendable` |
| `actor DynamoDBLocalService` | `struct DynamoDBClient: Sendable` |
| `storageService: LocalStorageService` | `dataDirectory: String` |

## Implementation Steps

### Phase 1: Create New SDK Clients

- [ ] Create `Sources/d-sdk-cli-docker/PostgreSQLClient.swift`
  - Convert from `actor` to `public struct PostgreSQLClient: Sendable`
  - Change init: `storageService: LocalStorageService` → `dataDirectory: String`
  - Remove `import c_service_storage`
  - Remove `storageKeyType` from `PostgreSQLConfig` enum
  - Remove storage key structs
  - Replace `storageService.dataDirectory(for:)` with `dataDirectory`
  - Replace `storageService.ensureDataDirectoryExists(for:)` with inline FileManager code

- [ ] Create `Sources/d-sdk-cli-docker/MinIOClient.swift`
  - Same changes as PostgreSQLClient
  - Keep `networkName` parameter (used for bucket creation)

- [ ] Create `Sources/d-sdk-cli-docker/DynamoDBClient.swift`
  - Same changes as PostgreSQLClient

### Phase 2: Create Storage Keys File

- [ ] Create `Sources/c-service-deploy-local/Containers/StorageKeys.swift`
  - Move all storage key definitions here:
    - `PostgreSQLXcodeStorageKey`, `PostgreSQLLinuxStorageKey`
    - `MinIOXcodeStorageKey`, `MinIOLinuxStorageKey`
    - `DynamoDBLocalXcodeStorageKey`, `DynamoDBLocalLinuxStorageKey`

### Phase 3: Update Callers

- [ ] Update `Sources/c-service-deploy-local/XcodeLocalDevelopmentService.swift`
  - Rename properties: `postgresService` → `postgresClient`, etc.
  - Update instantiation to pass `dataDirectory` string
  - Use storage keys to resolve paths

- [ ] Update `Sources/c-service-deploy-local/LinuxLocalDevelopmentService.swift`
  - Same changes as XcodeLocalDevelopmentService
  - Use Linux storage keys

- [ ] Update `Sources/c-service-deploy-local/EnvironmentVariables.swift`
  - Update parameter names and types to use new client names

### Phase 4: Delete Old Files

- [ ] Delete `Sources/c-service-deploy-local/Containers/PostgreSQLLocalService.swift`
- [ ] Delete `Sources/c-service-deploy-local/Containers/MinIOService.swift`
- [ ] Delete `Sources/c-service-deploy-local/Containers/DynamoDBLocalService.swift`

### Phase 5: Verify

- [ ] Build succeeds: `swift build`
- [ ] Tests pass: `swift test`
- [ ] Local services work: `./tools.sh local xcode start-all`

## Technical Details

### Config Enum Changes

Remove `storageKeyType` property from each config enum:

```swift
// Before
public enum PostgreSQLConfig: Sendable {
    case xcode
    case linux

    var storageKeyType: any StoragePathKey.Type {
        switch self {
        case .xcode: return PostgreSQLXcodeStorageKey.self
        case .linux: return PostgreSQLLinuxStorageKey.self
        }
    }
}

// After
public enum PostgreSQLConfig: Sendable {
    case xcode
    case linux
    // storageKeyType removed - caller provides dataDirectory
}
```

### Directory Creation Logic

Replace LocalStorageService usage with inline FileManager:

```swift
// Before
try storageService.ensureDataDirectoryExists(for: config.storageKeyType)

// After
if !FileManager.default.fileExists(atPath: dataDirectory) {
    try FileManager.default.createDirectory(
        atPath: dataDirectory,
        withIntermediateDirectories: true
    )
}
```

### Caller Instantiation Pattern

```swift
// Before
self.postgresService = PostgreSQLLocalService(
    dockerClient: dockerClient,
    config: .xcode,
    storageService: storageService
)

// After
self.postgresClient = PostgreSQLClient(
    dockerClient: dockerClient,
    config: .xcode,
    dataDirectory: storageService.dataDirectory(for: PostgreSQLXcodeStorageKey.self)
)
```
