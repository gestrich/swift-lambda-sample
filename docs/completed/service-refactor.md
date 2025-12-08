# Service Refactoring Plan: XcodeLocalService and LinuxLocalService

## Date: November 27, 2025

## Executive Summary

**Goal:** Refactor local development services to have clear separation of concerns with a unified protocol interface.

**Current State:** `LocalDevelopmentService` handles both native Xcode builds and Linux container builds, causing confusion about which workflow is being used.

**Proposed Solution:**
1. Create `LocalDeploymentService` protocol defining the interface
2. Split into two concrete implementations:
   - `XcodeLocalService` - Native macOS builds (fast iteration)
   - `LinuxLocalService` - Linux container builds (AWS compatibility)
3. Both services implement the same protocol, enabling polymorphic usage

**Key Benefits:**
- 🎯 **Identical CLI menus** - Same commands (`build`, `start-all`, `test`) work for both `xcode` and `linux`
- 🔀 **MacApp can toggle** - Single picker switches between Xcode/Linux, all UI buttons stay the same
- 🧩 **Protocol-based design** - Services are interchangeable, compiler enforces consistency
- 📝 **Clear naming** - `XcodeLocalService` vs `LinuxLocalService` makes the workflow explicit
- 🚀 **Easy to extend** - New deployment targets just implement the protocol

**Commands (Notice they're IDENTICAL!):**
```bash
# Xcode workflow (fast iteration)
./tools.sh local xcode build        # → XcodeLocalService.buildLambda()
./tools.sh local xcode start-all    # → XcodeLocalService.startWithServices()
./tools.sh local xcode test         # → XcodeLocalService.testLambda()

# Linux workflow (AWS-compatible) - SAME COMMANDS!
./tools.sh local linux build        # → LinuxLocalService.buildLambda()
./tools.sh local linux start-all    # → LinuxLocalService.startWithServices()
./tools.sh local linux test         # → LinuxLocalService.testLambda()
```

**MacApp Toggle:**
```swift
// Single picker, same UI works with both services
Picker("Mode", selection: $localMode) {
    Text("Xcode (Fast)").tag(LocalMode.xcode)
    Text("Linux (AWS)").tag(LocalMode.linux)
}
// All buttons work with both modes - no code changes needed!
```

---

## Problem Statement

The current service architecture is confusing because:

1. **`LocalDevelopmentService`** - Acts as orchestrator for BOTH Xcode (native macOS) builds AND Linux container builds
2. **`LambdaContainerService`** - Manages Linux container lifecycle but is hidden behind LocalDevelopmentService

**Key confusion points:**
- One API (`LocalDevelopmentService`) is the gateway for two fundamentally different workflows
- Clients must call LocalDevelopmentService even when they specifically want Linux container operations
- The naming doesn't reflect the actual separation: "Local Development" could mean either native or container
- LambdaContainerService is a dependency, not a peer service

## Proposed Solution

Create two peer services with clear responsibilities, unified by a common protocol:

```
                    ┌─────────────────────────────┐
                    │  LocalDeploymentService     │
                    │       (Protocol)            │
                    ├─────────────────────────────┤
                    │ • buildLambda()             │
                    │ • startLambda()             │
                    │ • stopLambda()              │
                    │ • startWithServices()       │
                    │ • stopWithServices()        │
                    │ • testLambda()              │
                    │ • isLambdaBuilt()           │
                    └─────────────────────────────┘
                              ▲         ▲
                              │         │
                 implements   │         │   implements
                              │         │
        ┌─────────────────────┘         └─────────────────────┐
        │                                                       │
┌───────────────────────┐                     ┌────────────────────────┐
│  XcodeLocalService    │                     │  LinuxLocalService     │
│  (formerly Local      │                     │  (formerly Lambda      │
│   DevelopmentService) │                     │   ContainerService)    │
├───────────────────────┤                     ├────────────────────────┤
│ • Native macOS build  │                     │ • Linux container build│
│ • swift build         │                     │ • ./build.sh (Docker)  │
│ • Direct execution    │                     │ • Docker execution     │
│ • Port 8080 localhost │                     │ • Network setup        │
│ • Fast iteration      │                     │ • AWS-compatible env   │
└───────────────────────┘                     └────────────────────────┘
         ↓                                              ↓
    Uses Services                                  Uses Services
         ↓                                              ↓
┌──────────────────────────────────────────────────────────────────┐
│                   Shared Infrastructure                           │
│  • PostgreSQLService                                             │
│  • MinIOService                                                  │
│  • DockerService                                                 │
│  • CLIService                                                    │
└──────────────────────────────────────────────────────────────────┘
```

## Protocol Definition

### LocalDeploymentService (Protocol)

A unified interface for local Lambda deployment, regardless of platform:

```swift
/// Protocol for local Lambda deployment services
public protocol LocalDeploymentService {
    /// The port where Lambda listens for requests
    var port: Int { get }

    /// The local endpoint URL for invoking Lambda
    var localEndpoint: String { get }

    // MARK: - Build

    /// Build Lambda for the target platform
    /// - Parameter clean: Whether to clean build artifacts first
    func buildLambda(clean: Bool) async throws

    /// Check if Lambda is already built
    func isLambdaBuilt() -> Bool

    // MARK: - Lifecycle

    /// Start Lambda process/container only
    func startLambda() async throws

    /// Stop Lambda process/container only
    func stopLambda() async throws

    /// Start Lambda with all supporting services (PostgreSQL + MinIO)
    func startWithServices() async throws

    /// Stop Lambda and all supporting services
    func stopWithServices() async throws

    // MARK: - Testing

    /// Test Lambda endpoints
    func testLambda() async throws

    /// Wait for Lambda to be ready (optional, default implementation)
    func waitForReady(maxAttempts: Int) async throws
}

// Default implementations
extension LocalDeploymentService {
    public func waitForReady(maxAttempts: Int = 30) async throws {
        // Check port availability
    }
}
```

**Benefits of Protocol:**
- **Identical CLI menus** - Same commands work for both `xcode` and `linux`, just different implementations
- **MacApp can toggle** - Switch between Xcode and Linux with a single setting, all UI stays the same
- Clients can write code agnostic to the deployment type
- Easy to switch between Xcode and Linux workflows
- Testable with mock implementations
- **Same operations, different platforms** - Protocol guarantees feature parity

---

## Service Responsibilities

### XcodeLocalService (New Name for LocalDevelopmentService)
**Purpose:** Native macOS development workflow using Xcode toolchain

**Conforms to:** `LocalDeploymentService`

**Responsibilities:**
- Build Lambda using native Swift toolchain (`swift build --product SwiftLambda`)
- Run Lambda directly as macOS process (not in container)
- Start/stop Lambda on localhost:8080
- Coordinate with PostgreSQL and MinIO services
- Test local endpoints (native execution)
- **No Docker container management**

**Implementation:**
```swift
public class XcodeLocalService: LocalDeploymentService {
    public var port: Int { 8080 }
    public var localEndpoint: String { "http://localhost:\(port)/invoke" }

    // MARK: - Build

    public func buildLambda(clean: Bool = false) async throws {
        // Native Swift build: swift build --product SwiftLambda
    }

    public func isLambdaBuilt() -> Bool {
        // Check .build/debug/SwiftLambda exists
    }

    // MARK: - Lifecycle

    public func startLambda() async throws {
        // Run .build/debug/SwiftLambda as native process
    }

    public func stopLambda() async throws {
        // Kill process on port 8080
    }

    public func startWithServices() async throws {
        // Start PostgreSQL + MinIO, then startLambda()
    }

    public func stopWithServices() async throws {
        // stopLambda(), then stop PostgreSQL + MinIO
    }

    // MARK: - Testing

    public func testLambda() async throws {
        // Test native Lambda endpoints using Client library
    }

    // MARK: - Additional Methods (not in protocol)

    public func copyConfig() async throws {
        // Copy config files to ~/.swiftSampleDemo/
    }
}
```

**Target Clients:**
- MacApp (for rapid development/testing)
- Developers working on macOS wanting fast iteration
- Unit tests that don't require Linux compatibility

---

### LinuxLocalService (New Name for LambdaContainerService)
**Purpose:** Linux container-based deployment workflow for AWS Lambda compatibility

**Conforms to:** `LocalDeploymentService`

**Responsibilities:**
- Build Lambda for Linux/AMD64 (via build.sh in Docker)
- Run Lambda in Linux container (matches AWS Lambda environment)
- Setup Docker networking between services
- Coordinate with PostgreSQL and MinIO services
- Test containerized endpoints (Linux execution)
- **Full Docker container orchestration**

**Implementation:**
```swift
public class LinuxLocalService: LocalDeploymentService {
    public var port: Int { 8080 }
    public var localEndpoint: String { "http://localhost:\(port)/invoke" }

    // MARK: - Build

    public func buildLambda(clean: Bool = false) async throws {
        // Docker build: ./build.sh SwiftLambda
    }

    public func isLambdaBuilt() -> Bool {
        // Check lambda/ directory and bootstrap exist
    }

    // MARK: - Lifecycle

    public func startLambda() async throws {
        // Start Lambda in Docker container (detached mode)
        // Delegates to internal LambdaContainerService
    }

    public func stopLambda() async throws {
        // Stop Docker container
    }

    public func startWithServices() async throws {
        // Start PostgreSQL + MinIO
        // Setup Docker network
        // Connect services to network
        // Start Lambda container
    }

    public func stopWithServices() async throws {
        // Stop Lambda container
        // Stop PostgreSQL + MinIO
    }

    // MARK: - Testing

    public func testLambda() async throws {
        // Test containerized Lambda endpoints using Client library
    }

    public func waitForReady(maxAttempts: Int = 30) async throws {
        // Check container is running and port is listening
    }

    // MARK: - Additional Methods (not in protocol)

    public func setupDockerNetwork() async throws {
        // Create lambda-local network
        // Connect PostgreSQL and MinIO to network
    }

    public func runInteractive() async throws {
        // Run Lambda in interactive container
    }

    public func printRunCommand() async throws {
        // Print docker run command for manual execution
    }
}
```

**Target Clients:**
- CI/CD pipelines (GitHub Actions)
- Integration tests requiring Linux compatibility
- Pre-deployment validation (test in AWS-like environment)
- Developers debugging Linux-specific issues

---

## Shared Infrastructure (Unchanged)

These services remain independent and are used by BOTH deployment services:

### PostgreSQLService
- Manages PostgreSQL Docker container
- Provides connection info
- Used by both Xcode and Linux workflows

### MinIOService
- Manages MinIO S3 Docker container
- Provides credentials and bucket management
- Used by both Xcode and Linux workflows

### DockerService
- Low-level Docker operations
- Used by PostgreSQL, MinIO, and Linux deployment

### CLIService
- Shell command execution
- Used by all services

---

## Migration Plan

### Phase 1: Create Protocol and Rename Services

**Step 1.1: Create LocalDeploymentService Protocol**
- Create new file: `Sources/SwiftDeploy/Protocols/LocalDeploymentService.swift`
- Define protocol with common interface (see Protocol Definition section above)
- Add default implementations in extension

**Step 1.2: Rename LocalDevelopmentService → XcodeLocalService**
- Rename file: `LocalDevelopmentService.swift` → `XcodeLocalService.swift`
- Rename class: `LocalDevelopmentService` → `XcodeLocalService`
- Add protocol conformance: `: LocalDeploymentService`
- Rename methods to match protocol (e.g., `startLambdaLocally()` → `startLambda()`)
- Keep all existing functionality intact

**Files to update:**
- `Sources/SwiftDeploy/LocalDevelopmentService.swift` → `XcodeLocalService.swift`
- `Sources/SwiftDeployCLI/Commands/LocalCommand.swift`
- `Sources/MacApp/APIConfiguration.swift`
- `Sources/MacApp/SettingsView.swift`
- `Tests/SwiftDeployTests/LinuxDeployTests.swift`
- `docs/REFACTORING_SUMMARY.md`

**Step 1.3: Elevate LambdaContainerService → LinuxLocalService**
- Rename file: `Services/LambdaContainerService.swift` → `LinuxLocalService.swift`
- Rename class: `LambdaContainerService` → `LinuxLocalService`
- Add protocol conformance: `: LocalDeploymentService`
- Change from `actor` to `class` (for protocol conformance)
- **Add new methods to match protocol:**
  - `buildLambda()` - Move build logic from XcodeLocalService
  - `isLambdaBuilt()` - Move from XcodeLocalService
  - `testLambda()` - Move test logic from XcodeLocalService
  - `startWithServices()` - High-level orchestration
  - `stopWithServices()` - High-level teardown
- Keep existing container-specific methods (runInteractive, printRunCommand, etc.)

**Files to create/update:**
- `Sources/SwiftDeploy/Protocols/LocalDeploymentService.swift` (NEW)
- `Sources/SwiftDeploy/Services/LambdaContainerService.swift` → `LinuxLocalService.swift`
- `Sources/SwiftDeploy/XcodeLocalService.swift` (renamed)

---

### Phase 2: Refactor XcodeLocalService (Remove Container Logic)

**Step 2.1: Remove Linux/Container Methods**
Remove these methods from XcodeLocalService (they're now in LinuxLocalService):
- ~~`runLambdaContainer()`~~ → In LinuxLocalService
- ~~`stopLambdaContainerAndServices()`~~ → In LinuxLocalService.stopWithServices()
- ~~`startLambdaContainerDetached()`~~ → In LinuxLocalService (internal)
- ~~`stopLambdaContainer()`~~ → In LinuxLocalService.stopLambda()
- ~~`setupLambdaNetwork()`~~ → In LinuxLocalService.setupDockerNetwork()

**Step 2.2: Remove LambdaContainerService Dependency**
```swift
// OLD (LocalDevelopmentService)
private let lambdaContainerService: LambdaContainerService

// NEW (XcodeLocalService)
// No dependency on Linux service - completely independent
```

**Step 2.3: Standardize Method Names (Protocol Conformance)**
```swift
// OLD
func buildLambda(clean: Bool = false) async throws
func startLambdaLocally() async throws
func stopLambdaLocally() async throws
func startLambdaWithServices() async throws
func stopLambdaWithServices() async throws
func testLocalLambda() async throws

// NEW (conforming to LocalDeploymentService protocol)
func buildLambda(clean: Bool = false) async throws      // Same name
func startLambda() async throws                         // Simplified
func stopLambda() async throws                          // Simplified
func startWithServices() async throws                   // Simplified
func stopWithServices() async throws                    // Simplified
func testLambda() async throws                          // Simplified
```

---

### Phase 3: Update CLI Commands

**Step 3.1: Design Principle - Identical Menus via Protocol**

🎯 **Key Insight:** Because both services implement `LocalDeploymentService` protocol, the CLI commands can be **identical** for both `xcode` and `linux`. The only difference is which service implementation is instantiated!

**Current structure (MIXED/CONFUSING):**
```
local
├── services (PostgreSQL + MinIO)
│   └── ...
├── lambda (MIXED - both Xcode and Linux!)
│   ├── setup-network    [Linux only]
│   ├── build            [Linux only - calls build.sh]
│   ├── start            [Xcode only - native build]
│   ├── stop             [Both - confusing!]
│   ├── run-container    [Linux only]
│   └── test             [Xcode only]
└── copy-config
```

**Proposed structure (PROTOCOL-BASED - IDENTICAL MENUS):**
```
local
├── services (PostgreSQL + MinIO - unchanged)
│   ├── start-all
│   ├── stop-all
│   ├── start-database
│   ├── stop-database
│   ├── start-s3
│   └── stop-s3
│
├── xcode (Native macOS development)
│   ├── build            [protocol: buildLambda()]
│   ├── start            [protocol: startLambda()]
│   ├── stop             [protocol: stopLambda()]
│   ├── start-all        [protocol: startWithServices()]
│   ├── stop-all         [protocol: stopWithServices()]
│   └── test             [protocol: testLambda()]
│
├── linux (Linux container deployment)
│   ├── build            [protocol: buildLambda()]         ← SAME COMMAND!
│   ├── start            [protocol: startLambda()]         ← SAME COMMAND!
│   ├── stop             [protocol: stopLambda()]          ← SAME COMMAND!
│   ├── start-all        [protocol: startWithServices()]   ← SAME COMMAND!
│   ├── stop-all         [protocol: stopWithServices()]    ← SAME COMMAND!
│   └── test             [protocol: testLambda()]          ← SAME COMMAND!
│
│   # Linux-specific extras (not in protocol)
│   ├── setup-network    [LinuxLocalService.setupDockerNetwork()]
│   └── run-interactive  [LinuxLocalService.runInteractive()]
│
└── copy-config (unchanged)
```

**Notice:** The first 6 commands are **IDENTICAL** for both `xcode` and `linux`! They just call different service implementations under the hood.

**Usage examples:**
```bash
# Xcode workflow (fast iteration)
./tools.sh local xcode build        # → XcodeLocalService.buildLambda()
./tools.sh local xcode start-all    # → XcodeLocalService.startWithServices()
./tools.sh local xcode test         # → XcodeLocalService.testLambda()

# Linux workflow (AWS compatibility) - SAME COMMANDS!
./tools.sh local linux build        # → LinuxLocalService.buildLambda()
./tools.sh local linux start-all    # → LinuxLocalService.startWithServices()
./tools.sh local linux test         # → LinuxLocalService.testLambda()

# Linux-specific operations
./tools.sh local linux setup-network    # Docker network setup
./tools.sh local linux run-interactive  # Interactive container shell
```

**Protocol guarantees:**
- Both services support the same core operations
- Commands have identical structure
- Help text is consistent
- Users can easily switch between workflows

**Step 3.2: Implement Commands Using Protocol (DRY Approach)**

Because both services implement the same protocol, we can use **generic command implementations** to avoid duplication!

**File: `Sources/SwiftDeployCLI/Commands/LocalDeploymentCommands.swift`**
```swift
/// Generic command implementations that work with any LocalDeploymentService
enum LocalDeploymentCommands {

    /// Generic build command - works with any service
    struct BuildCommand<Service: LocalDeploymentService>: AsyncParsableCommand {
        static var configuration: CommandConfiguration {
            CommandConfiguration(
                commandName: "build",
                abstract: "Build Lambda for target platform"
            )
        }

        @Flag(name: .long, help: "Clean build artifacts before building")
        var clean: Bool = false

        let serviceFactory: () -> Service

        init(serviceFactory: @escaping () -> Service) {
            self.serviceFactory = serviceFactory
        }

        func run() async throws {
            let service = serviceFactory()
            try await service.buildLambda(clean: clean)
        }
    }

    /// Generic start-all command - works with any service
    struct StartAllCommand<Service: LocalDeploymentService>: AsyncParsableCommand {
        static var configuration: CommandConfiguration {
            CommandConfiguration(
                commandName: "start-all",
                abstract: "Start Lambda with services (PostgreSQL + MinIO)"
            )
        }

        let serviceFactory: () -> Service

        func run() async throws {
            let service = serviceFactory()
            try await service.startWithServices()
        }
    }

    /// Generic test command - works with any service
    struct TestCommand<Service: LocalDeploymentService>: AsyncParsableCommand {
        static var configuration: CommandConfiguration {
            CommandConfiguration(
                commandName: "test",
                abstract: "Test Lambda endpoints"
            )
        }

        let serviceFactory: () -> Service

        func run() async throws {
            let service = serviceFactory()
            try await service.testLambda()
        }
    }

    // ... other generic commands (start, stop, stop-all)
}
```

**File: `Sources/SwiftDeployCLI/Commands/XcodeLocalCommand.swift`**
```swift
/// Commands for native macOS Xcode development
extension LocalCommand {
    struct XcodeCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "xcode",
            abstract: "Native macOS Xcode development workflow (fast iteration)",
            subcommands: [
                BuildCommand.self,
                StartCommand.self,
                StopCommand.self,
                StartAllCommand.self,
                StopAllCommand.self,
                TestCommand.self
            ]
        )
    }
}

extension LocalCommand.XcodeCommand {
    // Just wire up the generic commands with XcodeLocalService
    typealias BuildCommand = LocalDeploymentCommands.BuildCommand<XcodeLocalService>
    typealias StartCommand = LocalDeploymentCommands.StartCommand<XcodeLocalService>
    typealias StopCommand = LocalDeploymentCommands.StopCommand<XcodeLocalService>
    typealias StartAllCommand = LocalDeploymentCommands.StartAllCommand<XcodeLocalService>
    typealias StopAllCommand = LocalDeploymentCommands.StopAllCommand<XcodeLocalService>
    typealias TestCommand = LocalDeploymentCommands.TestCommand<XcodeLocalService>

    // Service factory
    static func createService() -> XcodeLocalService {
        XcodeLocalService(workingDirectory: FileManager.default.currentDirectoryPath)
    }
}
```

**File: `Sources/SwiftDeployCLI/Commands/LinuxLocalCommand.swift`**
```swift
/// Commands for Linux container deployment (AWS Lambda compatibility)
extension LocalCommand {
    struct LinuxCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "linux",
            abstract: "Linux container deployment workflow (AWS Lambda compatible)",
            subcommands: [
                BuildCommand.self,
                StartCommand.self,
                StopCommand.self,
                StartAllCommand.self,
                StopAllCommand.self,
                TestCommand.self,
                // Linux-specific commands
                SetupNetworkCommand.self,
                RunInteractiveCommand.self
            ]
        )
    }
}

extension LocalCommand.LinuxCommand {
    // Wire up the SAME generic commands with LinuxLocalService
    typealias BuildCommand = LocalDeploymentCommands.BuildCommand<LinuxLocalService>
    typealias StartCommand = LocalDeploymentCommands.StartCommand<LinuxLocalService>
    typealias StopCommand = LocalDeploymentCommands.StopCommand<LinuxLocalService>
    typealias StartAllCommand = LocalDeploymentCommands.StartAllCommand<LinuxLocalService>
    typealias StopAllCommand = LocalDeploymentCommands.StopAllCommand<LinuxLocalService>
    typealias TestCommand = LocalDeploymentCommands.TestCommand<LinuxLocalService>

    // Service factory
    static func createService() -> LinuxLocalService {
        LinuxLocalService(workingDirectory: FileManager.default.currentDirectoryPath)
    }

    // Linux-specific commands (not in protocol)
    struct SetupNetworkCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "setup-network",
            abstract: "Setup Docker network for Lambda container"
        )

        func run() async throws {
            let service = LinuxLocalService(workingDirectory: FileManager.default.currentDirectoryPath)
            try await service.setupDockerNetwork()
        }
    }

    struct RunInteractiveCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "run-interactive",
            abstract: "Run Lambda in interactive container shell"
        )

        func run() async throws {
            let service = LinuxLocalService(workingDirectory: FileManager.default.currentDirectoryPath)
            try await service.runInteractive()
        }
    }
}
```

**Benefits of this approach:**
- ✅ **Zero duplication** - Generic commands defined once
- ✅ **Type safety** - Compiler ensures service implements protocol
- ✅ **Identical menus** - Same commands automatically available for both
- ✅ **Easy to extend** - Add new service type by just wiring up the generic commands
- ✅ **Consistent behavior** - Same logic for both xcode and linux

**Step 3.3: Update LocalCommand**
```swift
struct LocalCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "local",
        abstract: "Local development environment management",
        subcommands: [
            ServicesCommand.self,     // Unchanged
            XcodeCommand.self,        // NEW
            LinuxCommand.self,        // NEW (replaces LambdaCommand)
            CopyConfigCommand.self    // Unchanged
        ]
    )
}
```

---

### Phase 4: Update Tests

**Step 4.1: Update Linux Integration Tests**
- `LinuxDeployTests.swift` → Keep name (accurate now!)
- Update to use `LinuxLocalService` directly instead of `LocalDevelopmentService`
- Use protocol-conformant method names

**Step 4.2: Update Test Code**
```swift
// OLD
let localService = LocalDevelopmentService(workingDirectory: root.path)
try await localService.buildLambda()
try await localService.startLambdaContainerDetached(lambdaPath: ...)
try await localService.stopLambdaContainer()
try await localService.testLocalLambda()

// NEW - Using LinuxLocalService directly
let linuxService = LinuxLocalService(workingDirectory: root.path)
try await linuxService.buildLambda()               // Protocol method
try await linuxService.startLambda()               // Protocol method
try await linuxService.waitForReady()              // Protocol method
try await linuxService.testLambda()                // Protocol method
try await linuxService.stopLambda()                // Protocol method
```

**Step 4.3: Add XcodeLocalService Tests**
Create new test file: `XcodeLocalTests.swift`
```swift
@Suite("Native Xcode Local Tests")
struct XcodeLocalTests {
    let xcodeService: XcodeLocalService

    init() {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        self.xcodeService = XcodeLocalService(workingDirectory: root.path)
    }

    @Test("Build and run Lambda natively on macOS")
    func testNativeXcodeBuild() async throws {
        try await xcodeService.buildLambda()         // Protocol method
        try await xcodeService.startWithServices()   // Protocol method
        try await xcodeService.testLambda()          // Protocol method
        try await xcodeService.stopWithServices()    // Protocol method
    }
}
```

**Step 4.4: Add Protocol-Based Tests**
Create new test file: `LocalDeploymentServiceTests.swift`
```swift
@Suite("LocalDeploymentService Protocol Tests")
struct LocalDeploymentServiceProtocolTests {
    // Test that both services conform to protocol

    @Test("XcodeLocalService conforms to LocalDeploymentService")
    func testXcodeServiceConformance() {
        let service: any LocalDeploymentService = XcodeLocalService(workingDirectory: "/tmp")
        #expect(service.port == 8080)
        #expect(service.localEndpoint.contains("localhost"))
    }

    @Test("LinuxLocalService conforms to LocalDeploymentService")
    func testLinuxServiceConformance() {
        let service: any LocalDeploymentService = LinuxLocalService(workingDirectory: "/tmp")
        #expect(service.port == 8080)
        #expect(service.localEndpoint.contains("localhost"))
    }

    @Test("Services can be used polymorphically")
    func testPolymorphicUsage() async throws {
        let services: [any LocalDeploymentService] = [
            XcodeLocalService(workingDirectory: "/tmp"),
            LinuxLocalService(workingDirectory: "/tmp")
        ]

        for service in services {
            // Both services respond to same protocol methods
            let _ = service.port
            let _ = service.localEndpoint
            let _ = service.isLambdaBuilt()
        }
    }
}
```

---

### Phase 5: Update MacApp

**Step 5.1: Update APIConfiguration (Protocol-Based)**

Using the protocol, MacApp can be agnostic to which service is used:

```swift
// OLD
class APIConfiguration {
    private var localEndpoint: String {
        LocalDevelopmentService(workingDirectory: ...).localEndpoint
    }
}

// NEW - Protocol-based design
@MainActor
@Observable
class APIConfiguration {
    enum LocalMode: String, Codable {
        case xcode    // Native macOS build (fast)
        case linux    // Docker container build (AWS-compatible)
    }

    var mode: ConnectionMode
    var localMode: LocalMode = .xcode  // Default to faster Xcode build
    var remoteURL: String?

    // MARK: - Service Factory

    /// Create the appropriate local service based on mode
    private func createLocalService() -> any LocalDeploymentService {
        let workingDir = FileManager.default.currentDirectoryPath

        switch localMode {
        case .xcode:
            return XcodeLocalService(workingDirectory: workingDir)
        case .linux:
            return LinuxLocalService(workingDirectory: workingDir)
        }
    }

    // MARK: - Endpoint

    private var localEndpoint: String {
        createLocalService().localEndpoint
    }

    // MARK: - API Client

    func createAPIClient() -> APIClient? {
        switch mode {
        case .local:
            return APIClient(
                baseURL: "http://localhost:8080",
                mode: .localLambda(endpoint: localEndpoint)
            )
        case .remote:
            guard let url = remoteURL else { return nil }
            return APIClient(
                baseURL: url,
                mode: .apiGateway
            )
        }
    }

    // MARK: - Service Access

    /// Get the current local service (for starting/stopping Lambda)
    func getLocalService() -> any LocalDeploymentService {
        createLocalService()
    }
}
```

**Step 5.2: Update SettingsView (Add Mode Toggle)**

```swift
struct SettingsView: View {
    @Bindable var apiConfig: APIConfiguration

    var body: some View {
        Form {
            Section("Connection") {
                Picker("Mode", selection: $apiConfig.mode) {
                    Text("Local").tag(ConnectionMode.local)
                    Text("Remote (AWS)").tag(ConnectionMode.remote)
                }

                if apiConfig.mode == .local {
                    Picker("Local Mode", selection: $apiConfig.localMode) {
                        Text("Xcode (Fast)").tag(APIConfiguration.LocalMode.xcode)
                        Text("Linux (AWS-compatible)").tag(APIConfiguration.LocalMode.linux)
                    }
                    .help("Xcode: Native build, fast iteration\nLinux: Docker container, matches AWS environment")
                }
            }

            Section("Actions") {
                if apiConfig.mode == .local {
                    Button("Start Local Lambda") {
                        Task {
                            let service = apiConfig.getLocalService()
                            try await service.startWithServices()
                        }
                    }

                    Button("Stop Local Lambda") {
                        Task {
                            let service = apiConfig.getLocalService()
                            try await service.stopWithServices()
                        }
                    }
                }
            }
        }
    }
}
```

**Benefits of Protocol-Based MacApp:**
- 🎯 **Single UI, multiple backends** - Same buttons/actions work with both services
- 🔀 **Easy toggle** - Switch between Xcode and Linux with a single picker, no code changes
- 🧩 **Loosely coupled** - MacApp doesn't depend on specific service implementations
- 🚀 **Easy to extend** - Add new deployment modes (e.g., ARM Linux) by implementing protocol
- 📦 **Logic separation** - Service logic stays in SwiftDeploy, MacApp just calls protocol methods
- ♻️ **No duplication** - Same protocol methods, different implementations

**Example Usage in MacApp:**
```swift
// User toggles between Xcode and Linux
@State var localMode: LocalMode = .xcode

// UI code is identical for both modes!
Button("Start Lambda") {
    let service = apiConfig.getLocalService()  // Returns XcodeLocalService OR LinuxLocalService
    try await service.startWithServices()      // Works with both!
}

Button("Test Lambda") {
    let service = apiConfig.getLocalService()
    try await service.testLambda()             // Works with both!
}

Button("Stop Lambda") {
    let service = apiConfig.getLocalService()
    try await service.stopWithServices()       // Works with both!
}
```

**Result:** MacApp can point to either XcodeLocalService (fast) or LinuxLocalService (AWS-compatible) just by changing a picker value. All UI stays the same!

---

### Phase 6: Update Documentation

**Step 6.1: Update CLAUDE.md**
- Replace all references to `LocalDevelopmentService` with appropriate service
- Update command examples to use new structure (`local xcode` vs `local linux`)
- Add section explaining when to use each service

**Step 6.2: Update REFACTORING_SUMMARY.md**
- Add new entry documenting this refactor
- Explain the XcodeDeploymentService / LinuxDeploymentService split

**Step 6.3: Update README**
- Update quick start examples
- Add section on choosing between Xcode and Linux workflows

---

## Decision Points / Open Questions

### 1. Service Independence: Should services share service management?

**Option A: Fully Independent (Recommended)**
```swift
// Each service manages its own dependencies
class XcodeDeploymentService {
    private let postgresService: PostgreSQLService
    private let minioService: MinIOService
    // No knowledge of LinuxDeploymentService
}

class LinuxDeploymentService {
    private let postgresService: PostgreSQLService
    private let minioService: MinIOService
    // No knowledge of XcodeDeploymentService
}
```

**Option B: Shared Infrastructure Manager**
```swift
class LocalInfrastructureService {
    let postgres: PostgreSQLService
    let minio: MinIOService
}

class XcodeDeploymentService {
    private let infrastructure: LocalInfrastructureService
}

class LinuxDeploymentService {
    private let infrastructure: LocalInfrastructureService
}
```

**Recommendation: Option A (Fully Independent)**
- Simpler dependency graph
- Services can be used independently
- No shared state concerns
- PostgreSQL and MinIO services are already designed to be safe for concurrent use

---

### 2. Build Method Naming

**Option A: Protocol-Based Generic Names (Recommended)**
```swift
// Protocol definition
protocol LocalDeploymentService {
    func buildLambda(clean: Bool) async throws
}

// XcodeLocalService
func buildLambda(clean: Bool = false) async throws  // Builds for macOS

// LinuxLocalService
func buildLambda(clean: Bool = false) async throws  // Builds for Linux
```

**Option B: Platform-Specific Names**
```swift
// XcodeLocalService
func buildLambdaForMacOS(clean: Bool = false) async throws

// LinuxLocalService
func buildLambdaForLinux(clean: Bool = false) async throws
```

**Recommendation: Option A (Protocol-Based)**
- Enables polymorphic usage (services are interchangeable)
- Cleaner API - the service name already indicates the platform
- Clients can be written against the protocol, not specific implementations
- Service name provides context: `XcodeLocalService.buildLambda()` is clear

---

### 3. CLI Command Structure

**Current Proposal:**
```
local
├── services
├── xcode      # Native workflows
├── linux      # Container workflows
└── copy-config
```

**Alternative:**
```
local
├── services
├── native     # Instead of "xcode"
├── container  # Instead of "linux"
└── copy-config
```

**Recommendation: Keep `xcode` and `linux`**
- `xcode` is accurate (uses Xcode toolchain)
- `linux` is clearer than "container" (emphasizes Linux compatibility)
- Matches AWS Lambda terminology (Linux runtime)

---

### 4. Backward Compatibility Strategy

**Option A: Add deprecation warnings, remove after 1 month**
```swift
@available(*, deprecated, renamed: "XcodeDeploymentService")
typealias LocalDevelopmentService = XcodeDeploymentService
```

**Option B: Clean break, no aliases**
- Just rename everything in one PR
- Update all clients immediately

**Recommendation: Option B (Clean Break)**
- This is a development project, not a public library
- No external clients to worry about
- Cleaner outcome without deprecated aliases
- Single PR is easier to review

---

## Success Criteria

### Protocol & Code Organization
- [ ] `LocalDeploymentService` protocol defined with complete interface
- [ ] Both `XcodeLocalService` and `LinuxLocalService` conform to protocol
- [ ] `XcodeLocalService` has no Docker container logic
- [ ] `LinuxLocalService` has no native macOS build logic
- [ ] Both services are independent and can be used without the other
- [ ] Shared services (PostgreSQL, MinIO) remain independent
- [ ] Services are interchangeable via protocol (polymorphic usage works)

### CLI Structure
- [ ] `./tools.sh local xcode build` builds for macOS
- [ ] `./tools.sh local linux build` builds for Linux in Docker
- [ ] Command names clearly indicate which workflow they use
- [ ] All existing workflows still work via new commands

### Tests
- [ ] Linux integration tests use `LinuxLocalService` directly
- [ ] New Xcode integration tests use `XcodeLocalService`
- [ ] Protocol conformance tests verify both services implement interface
- [ ] Polymorphic usage tests demonstrate protocol works
- [ ] All tests pass

### Documentation
- [ ] CLAUDE.md updated with new command structure
- [ ] Protocol explained with benefits and use cases
- [ ] Examples show when to use each service
- [ ] README reflects new workflow options

### MacApp
- [ ] MacApp updated to use protocol-based service factory
- [ ] UI toggle between Xcode (fast) and Linux (AWS-compatible) modes
- [ ] MacApp code is agnostic to specific service implementation

---

## Implementation Order

1. **Phase 1** - Rename files and classes (no logic changes)
   - Ensures everything still works before refactoring logic
   - Easy to revert if issues arise

2. **Phase 2** - Extract container logic to LinuxDeploymentService
   - Moves build, test, orchestration methods
   - Makes LinuxDeploymentService a complete, independent service

3. **Phase 3** - Remove container logic from XcodeDeploymentService
   - Removes Docker dependencies
   - Results in clean separation

4. **Phase 4** - Update CLI commands
   - New command structure reflects service split
   - Users get clearer interface

5. **Phase 5** - Update tests
   - Ensures both services work independently
   - Validates the separation

6. **Phase 6** - Update documentation
   - Final step to ensure everything is documented

---

## Benefits of This Refactor

### 1. **Protocol-Based Design**
- **Polymorphism:** Services can be used interchangeably via protocol
- **Testability:** Easy to create mock implementations for testing
- **Flexibility:** MacApp can switch between services without code changes
- **Extensibility:** New service types just implement the protocol
- **Type Safety:** Compiler ensures all services implement required methods

### 2. **Clarity**
- Service names clearly indicate their purpose (`XcodeLocal` vs `LinuxLocal`)
- No confusion about which build/test workflow is being used
- CLI commands are self-documenting (`local xcode` vs `local linux`)
- Protocol defines the contract explicitly

### 3. **Independence**
- Clients can call the service they need directly
- No gateway service to go through
- Each service has complete functionality
- Protocol enables polymorphic usage when desired

### 4. **Flexibility**
- MacApp can choose between fast (Xcode) and compatible (Linux) testing
- CI/CD can use Linux service directly
- Developers can mix workflows as needed
- Same client code works with different services (protocol-based)

### 5. **Maintainability**
- Each service has focused responsibilities
- Changes to Xcode workflow don't affect Linux workflow
- Easier to test in isolation
- Protocol documents the required interface

### 6. **Scalability**
- Easy to add new deployment targets (e.g., ARM Linux)
- Could add `ARMLocalService` alongside existing services
- Just implement `LocalDeploymentService` protocol
- Pattern is established for specialized deployment services
- New services automatically work with existing protocol-based clients

---

## Risks and Mitigations

### Risk 1: Breaking Changes During Transition
**Mitigation:**
- Phase 1 (rename) has no logic changes
- Test after each phase
- All changes in single feature branch

### Risk 2: Duplicate Code Between Services
**Mitigation:**
- Keep shared services (PostgreSQL, MinIO) independent
- Extract common patterns into shared utilities
- Both services use same infrastructure primitives

### Risk 3: CLI Command Breaking Changes
**Mitigation:**
- Update documentation immediately
- Old commands removed completely (no half-working state)
- Clear error messages for deprecated commands (optional)

---

## Timeline Estimate

- **Phase 1 (Rename):** 1-2 hours
- **Phase 2 (Extract to Linux):** 2-3 hours
- **Phase 3 (Clean Xcode):** 1-2 hours
- **Phase 4 (CLI Commands):** 2-3 hours
- **Phase 5 (Tests):** 2-3 hours
- **Phase 6 (Documentation):** 1-2 hours

**Total:** 9-15 hours of focused work

Can be broken into smaller PRs if desired:
1. PR 1: Phase 1 (rename only)
2. PR 2: Phases 2-3 (logic refactor)
3. PR 3: Phases 4-6 (CLI, tests, docs)

---

## Conclusion

This refactor addresses the core confusion in the current architecture by:

1. **Protocol-Based Design:** `LocalDeploymentService` protocol enables polymorphic usage while maintaining type safety
2. **Creating clear boundaries:** Xcode vs Linux workflows are separate services with unified interface
3. **Enabling direct access:** Clients call the service they need (no gateway), or use protocol for flexibility
4. **Improving naming:** `XcodeLocalService` and `LinuxLocalService` clearly indicate purpose
5. **Simplifying CLI:** Commands clearly indicate workflow (`local xcode` vs `local linux`)
6. **Maximizing flexibility:** Services are interchangeable via protocol when desired

### Key Improvements

**Before:**
```swift
// Confusing - one service does everything
LocalDevelopmentService.buildLambda()           // Native or Linux?
LocalDevelopmentService.startLambdaLocally()    // Native only
LocalDevelopmentService.runLambdaContainer()    // Linux only
```

**After:**
```swift
// Clear - dedicated services with unified protocol
let service: any LocalDeploymentService

// Use specific service when you know what you want
let xcodeService = XcodeLocalService(...)
let linuxService = LinuxLocalService(...)

// Or be polymorphic when you don't care
service.buildLambda()        // Works for both!
service.startWithServices()  // Works for both!
service.testLambda()         // Works for both!

// CLI is also clear
./tools.sh local xcode build    // Native build
./tools.sh local linux build    // Linux build
```

The result is a **more maintainable, understandable, and flexible** codebase where:
- Each service has a clear, focused purpose
- Protocol enables code reuse without coupling
- New deployment targets can be added easily
- MacApp and tests can be agnostic to service implementation

---

## Real-World Usage Examples

### CLI: Identical Commands, Different Platforms

```bash
# Developer using Xcode (fast iteration on macOS)
./tools.sh local xcode build
./tools.sh local xcode start-all
./tools.sh local xcode test
./tools.sh local xcode stop-all

# Same developer testing AWS compatibility before deployment
./tools.sh local linux build        # ← SAME COMMANDS!
./tools.sh local linux start-all    # ← SAME COMMANDS!
./tools.sh local linux test         # ← SAME COMMANDS!
./tools.sh local linux stop-all     # ← SAME COMMANDS!
```

**No need to learn different commands!** The protocol ensures both workflows support the same operations.

### MacApp: Single Toggle, Same UI

```swift
// User opens MacApp settings
Picker("Local Development Mode", selection: $localMode) {
    Text("Xcode (Fast)").tag(LocalMode.xcode)
    Text("Linux (AWS-compatible)").tag(LocalMode.linux)
}

// ALL buttons work with both modes:
// - "Start Lambda" button
// - "Stop Lambda" button
// - "Test Lambda" button
// - "View Logs" button
// - etc.

// Just toggle the picker, same UI works!
```

**User perspective:**
- "I want fast iteration" → Choose Xcode mode, click "Start Lambda"
- "I want AWS compatibility testing" → Choose Linux mode, click "Start Lambda"
- **Same button, same UI, different backend!**

### Tests: Polymorphic Testing

```swift
// Test that works with BOTH services
func testLocalDeploymentWorkflow(service: any LocalDeploymentService) async throws {
    try await service.buildLambda()
    try await service.startWithServices()
    try await service.testLambda()
    try await service.stopWithServices()
}

// Run the same test with both implementations
@Test func testXcodeWorkflow() async throws {
    try await testLocalDeploymentWorkflow(service: XcodeLocalService(...))
}

@Test func testLinuxWorkflow() async throws {
    try await testLocalDeploymentWorkflow(service: LinuxLocalService(...))
}
```

**Same test logic, both platforms verified!**

---

## Summary: The Power of Protocol-Based Design

This refactor transforms a confusing mixed service into a clean, protocol-based architecture where:

1. ✅ **Identical CLI menus** - `xcode` and `linux` commands are the same, just different implementations
2. ✅ **MacApp toggle** - Switch between Xcode/Linux with one picker, all UI stays identical
3. ✅ **Zero duplication** - Generic command implementations work with any service
4. ✅ **Easy to extend** - New platform? Just implement the protocol
5. ✅ **Type safety** - Compiler enforces protocol conformance
6. ✅ **Clear separation** - XcodeLocal = native, LinuxLocal = container

**The protocol is the key!** It enables polymorphism while maintaining type safety and clear service separation.
