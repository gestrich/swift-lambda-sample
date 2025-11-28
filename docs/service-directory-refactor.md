# Service Directory Refactor Plan

## Goal

Consolidate all local development service data into `~/.swiftSampleDemo/` for better organization and easier cleanup.

## Current State

### MinIO (S3)
- **Location**: Host directories
  - `~/minio/xcode-data`
  - `~/minio/linux-data`
- **How it works**: MinIO initializes its data structure on first run into whatever directory is mounted

### PostgreSQL
- **Location**: Named Docker volumes
  - `postgres-xcode-data`
  - `postgres-linux-data`
- **How it works**: Custom `PostgresDockerfile` initializes database during image build. Named volumes preserve this data because Docker copies initialized data from the image into empty named volumes on first run.
- **Why host directories failed**: Mounting an empty host directory over `/var/lib/postgresql` hides the initialized data from the image, causing PostgreSQL to fail.

## Proposed State

All data in `~/.swiftSampleDemo/`:

```
~/.swiftSampleDemo/
├── swiftLambdaDemo.json      # (existing) Runtime app config
├── aws-config.json           # (existing) AWS profile config
├── minio/
│   ├── xcode-data/           # MinIO data for Xcode mode
│   └── linux-data/           # MinIO data for Linux mode
└── postgres/
    ├── xcode-data/           # PostgreSQL data for Xcode mode
    └── linux-data/           # PostgreSQL data for Linux mode
```

## Implementation Plan

### 1. Switch PostgreSQL to Official Docker Image

Replace custom `PostgresDockerfile` with the official `postgres` image.

**Why**: The official postgres image handles initialization into empty host directories automatically using its entrypoint scripts. It detects if the data directory is empty and runs `initdb` on first start.

**Changes to `PostgreSQLService.swift`**:

```swift
// Before: Build custom image
buildOptions.tag = config.imageName
buildOptions.file = "PostgresDockerfile"
try await dockerService.build(context: ".", options: buildOptions)

// After: Use official image directly (no build step)
let imageName = "postgres:11"  // or postgres:15 for newer version
```

**Changes to `PostgreSQLConfig`**:

```swift
var imageName: String { "postgres:11" }  // Use official image for all modes

var dataDirectory: String {
    let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
    switch self {
    case .xcode: return "\(homeDir)/.swiftSampleDemo/postgres/xcode-data"
    case .linux: return "\(homeDir)/.swiftSampleDemo/postgres/linux-data"
    }
}
```

**Container run options**:

```swift
runOptions.volumes = [(config.dataDirectory, "/var/lib/postgresql/data")]
runOptions.environment = [
    "POSTGRES_USER": config.username,
    "POSTGRES_PASSWORD": config.password,
    "POSTGRES_DB": config.database
]
```

### 2. Update MinIO Data Directory

**Changes to `MinIOConfig`**:

```swift
var dataDirectory: String {
    let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
    switch self {
    case .xcode: return "\(homeDir)/.swiftSampleDemo/minio/xcode-data"
    case .linux: return "\(homeDir)/.swiftSampleDemo/minio/linux-data"
    }
}
```

**Changes to `MinIOService.swift`**:

```swift
// Update dataDirectory initialization
self.dataDirectory = config.dataDirectory
```

### 3. Update TLS Configuration

The `PostgresModelStore.swift` has a hardcoded list of local hosts to disable TLS. This should continue to work since we're still using the same container names (`postgres-xcode`, `postgres-linux`).

No changes needed - the fix from commit `afab432` already includes these container names.

### 4. Clean Up

After implementation:

1. Remove old data directories:
   ```bash
   rm -rf ~/minio
   ```

2. Remove old Docker volumes:
   ```bash
   docker volume rm postgres-xcode-data postgres-linux-data
   ```

3. Optionally remove `PostgresDockerfile` if no longer needed for other purposes

### 5. Directory Creation

Ensure `~/.swiftSampleDemo/` subdirectories are created on first run:

```swift
// In PostgreSQLService.start() and MinIOService.start()
let dataDir = config.dataDirectory
if !FileManager.default.fileExists(atPath: dataDir) {
    try FileManager.default.createDirectory(
        atPath: dataDir,
        withIntermediateDirectories: true,
        attributes: nil
    )
}
```

## Testing Plan

1. Stop all services and remove existing containers/volumes
2. Start Xcode mode - verify PostgreSQL and MinIO initialize correctly
3. Add test data to both services
4. Switch to Linux mode - verify separate data
5. Add different test data
6. Switch back to Xcode - verify original data persists
7. Verify `./tools.sh local xcode test` passes
8. Verify `./tools.sh local linux test` passes

## Benefits

1. **Single location**: All local dev data in `~/.swiftSampleDemo/`
2. **Easy cleanup**: `rm -rf ~/.swiftSampleDemo/` removes everything
3. **Visibility**: Users can easily see/backup their local data
4. **Consistency**: Both services use the same pattern (host directories)
5. **Simpler PostgreSQL**: No custom Dockerfile to maintain

## Risks

1. **Data migration**: Existing data in named volumes will be lost (users must reinitialize)
2. **Postgres version**: Need to pick appropriate postgres image version (11 matches current Dockerfile)
3. **Permissions**: Host directory permissions must allow Docker to write (usually not an issue on macOS)
