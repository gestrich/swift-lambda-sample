# Move DockerService to sdk-cli-docker Layer

## Overview

This document plans the migration of `DockerService` from `service-deploy-remote` to a new `sdk-cli-docker` target, following the project's layered architecture principles.

## Current State

### Files to Move

| File | Location |
|------|----------|
| `DockerService.swift` | `Sources/service-deploy-remote/DockerService/DockerService.swift` |
| `Docker.swift` | `Sources/service-deploy-remote/DockerService/CLI/Docker.swift` |

### Current Dependencies

```
DockerService
├── sdk_cli (CLIClient, CLIOutputStream, CLIOutputParser)
├── Foundation
└── DeployError (service-deploy-remote/Core/Errors)
```

### Current Consumers

- `LinuxLocalDevelopmentService` (service-deploy-remote)
- `XcodeLocalDevelopmentService` (service-deploy-remote)

## Analysis

### What IS Generic (Should Move to SDK)

1. **Docker CLI commands** (`Docker.swift`)
   - All `@CLICommand` structs: `Run`, `Start`, `Stop`, `Rm`, `Ps`, `Build`, `Network.*`
   - Output types: `DockerContainer`, `DockerNetworkContainer`
   - Parsers: `DockerPsNamesParser`, `DockerNetworkContainersParser`

2. **Container operations**
   - `run()`, `start()`, `stop()`, `remove()`
   - `containerExists()`, `containerIsRunning()`

3. **Image operations**
   - `build()`

4. **Network operations**
   - `createNetwork()`, `networkExists()`
   - `connectToNetwork()`, `isConnectedToNetwork()`

5. **Daemon operations**
   - `isDockerRunning()`

6. **System queries**
   - `getCurrentUserId()`, `getCurrentGroupId()`

7. **Options structs**
   - `RunOptions`, `BuildOptions`

### What IS App-Specific (Needs Refactoring)

1. **DeployError dependency**
   - DockerService throws `DeployError.commandFailed` which is service-layer
   - SDK needs its own `DockerError` enum

2. **Print statements for user feedback**
   ```swift
   // In startDockerDesktop()
   print("🐳 Starting Docker Desktop...")
   print("   Waiting for Docker daemon to be ready...")
   print("   Still waiting... (\(attempt)s)")
   print("   ✅ Docker is ready")
   ```
   - SDKs should be silent; app layer handles user feedback

3. **startDockerDesktop() polling logic**
   - Contains 60-second polling with user feedback
   - Option A: Return `AsyncThrowingStream<DockerDaemonProgress, Error>`
   - Option B: Remove from SDK, keep in service layer
   - Option C: Keep as-is but remove prints, return Bool success

4. **ensureDockerRunning() orchestration**
   - Calls `isDockerRunning()` then `startDockerDesktop()`
   - This is orchestration logic that may belong in service layer

## Proposed Changes

### 1. Create `sdk-cli-docker` Target

**Package.swift addition:**
```swift
.target(
    name: "sdk-cli-docker",
    dependencies: [
        .target(name: "sdk-cli"),
    ]
),
```

### 2. Create `DockerError` Enum

**Location:** `Sources/sdk-cli-docker/DockerError.swift`

```swift
import Foundation

public enum DockerError: Error, LocalizedError, Sendable {
    case commandFailed(command: String, exitCode: Int32, output: String)
    case daemonNotRunning
    case daemonStartTimeout(seconds: Int)
    case containerNotFound(name: String)
    case networkNotFound(name: String)

    public var errorDescription: String? {
        switch self {
        case .commandFailed(let command, let exitCode, let output):
            let errorOutput = output.isEmpty ? "No error output" : output.trimmingCharacters(in: .whitespacesAndNewlines)
            return "Docker command '\(command)' failed with exit code \(exitCode): \(errorOutput)"
        case .daemonNotRunning:
            return "Docker daemon is not running"
        case .daemonStartTimeout(let seconds):
            return "Docker daemon did not start within \(seconds) seconds"
        case .containerNotFound(let name):
            return "Container '\(name)' not found"
        case .networkNotFound(let name):
            return "Network '\(name)' not found"
        }
    }
}
```

### 3. Move and Refactor `DockerClient`

**Location:** `Sources/sdk-cli-docker/DockerClient.swift`

Key changes:
- Rename `DockerService` → `DockerClient` (SDK naming convention)
- Replace `DeployError` → `DockerError`
- Remove all `print()` statements
- Remove `startDockerDesktop()` and `ensureDockerRunning()` (move to service layer)

```swift
import sdk_cli
import Foundation

/// Client for interacting with Docker CLI
public struct DockerClient: Sendable {
    private let cliClient: CLIClient

    public init(cliClient: CLIClient) {
        self.cliClient = cliClient
    }

    // MARK: - Docker Daemon

    /// Check if Docker daemon is running
    public func isDockerRunning() async -> Bool {
        do {
            let result = try await cliClient.executeForResult(Docker.Info(), printCommand: false)
            return result.isSuccess
        } catch {
            return false
        }
    }

    // MARK: - Container Management

    public struct RunOptions: Sendable {
        public var detached: Bool
        public var remove: Bool
        public var interactive: Bool
        public var tty: Bool
        public var platform: String?
        public var name: String?
        public var network: String?
        public var ports: [(host: Int, container: Int)]
        public var volumes: [(host: String, container: String)]
        public var environment: [String: String]
        public var user: String?
        public var workingDirectory: String?

        public init(
            detached: Bool = false,
            remove: Bool = false,
            interactive: Bool = false,
            tty: Bool = false,
            platform: String? = nil,
            name: String? = nil,
            network: String? = nil,
            ports: [(host: Int, container: Int)] = [],
            volumes: [(host: String, container: String)] = [],
            environment: [String: String] = [:],
            user: String? = nil,
            workingDirectory: String? = nil
        ) {
            self.detached = detached
            self.remove = remove
            self.interactive = interactive
            self.tty = tty
            self.platform = platform
            self.name = name
            self.network = network
            self.ports = ports
            self.volumes = volumes
            self.environment = environment
            self.user = user
            self.workingDirectory = workingDirectory
        }
    }

    /// Run a Docker container
    public func run(
        image: String,
        command: [String] = [],
        options: RunOptions = RunOptions(),
        output: CLIOutputStream? = nil
    ) async throws {
        // ... (same implementation, replace DeployError with DockerError)
    }

    // ... (all other methods with DeployError → DockerError)
}
```

### 4. Move Docker CLI Commands

**Location:** `Sources/sdk-cli-docker/CLI/Docker.swift`

Move as-is, no changes needed. The `@CLIProgram` and `@CLICommand` definitions are already generic.

### 5. Update Consumers

Update `LinuxLocalDevelopmentService` and `XcodeLocalDevelopmentService`:
- Import `sdk_cli_docker` and use `DockerClient` directly
- Move `ensureDockerRunning()` logic into these services where needed

## File Structure

### Before
```
Sources/
├── service-deploy-remote/
│   └── DockerService/
│       ├── CLI/
│       │   └── Docker.swift
│       └── DockerService.swift
```

### After
```
Sources/
├── sdk-cli-docker/
│   ├── CLI/
│   │   └── Docker.swift
│   ├── DockerClient.swift
│   └── DockerError.swift
```

## Migration Steps

1. **Create sdk-cli-docker target in Package.swift**
   - Add target definition
   - Add dependency: sdk-cli

2. **Create DockerError.swift** in sdk-cli-docker
   - Define error cases
   - Implement LocalizedError

3. **Move Docker.swift** to sdk-cli-docker/CLI/
   - No code changes needed
   - Update import if needed

4. **Create DockerClient.swift** in sdk-cli-docker
   - Copy from DockerService.swift
   - Rename DockerService → DockerClient
   - Change `actor` → `struct`
   - Replace DeployError → DockerError
   - Remove print statements
   - Remove startDockerDesktop() and ensureDockerRunning()

5. **Delete service-deploy-remote/DockerService/** directory

6. **Update Package.swift dependencies**
   - Add sdk-cli-docker dependency to service-deploy-remote

7. **Update consumers**
   - LinuxLocalDevelopmentService
   - XcodeLocalDevelopmentService
   - Update imports and types
   - Move ensureDockerRunning() logic into these services

8. **Run tests and verify**

## Benefits

1. **Better layer separation**: Generic Docker operations in SDK, app-specific orchestration in service
2. **Reusability**: sdk-cli-docker could be extracted to a separate package
3. **Testability**: DockerClient can be tested without app-specific dependencies
4. **Consistent naming**: DockerClient matches other SDK clients (CDKClient, GitClient, etc.)

## Risks

- **Breaking changes**: Consumers need import updates
- **API surface**: Options structs move from DockerService to DockerClient namespace

## Files Changed

| File | Change |
|------|--------|
| `Package.swift` | Add sdk-cli-docker target |
| `Sources/sdk-cli-docker/DockerClient.swift` | New file (from DockerService) |
| `Sources/sdk-cli-docker/DockerError.swift` | New file |
| `Sources/sdk-cli-docker/CLI/Docker.swift` | Moved from service-deploy-remote |
| `Sources/service-deploy-remote/DockerService/` | Delete directory |
| `Sources/service-deploy-remote/LocalDevelopmentService/LinuxLocalDevelopmentService.swift` | Update imports, add ensureDockerRunning logic |
| `Sources/service-deploy-remote/LocalDevelopmentService/XcodeLocalDevelopmentService.swift` | Update imports, add ensureDockerRunning logic |
