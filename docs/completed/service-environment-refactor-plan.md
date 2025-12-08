# MacApp Service Environment Refactor Plan

## Problem Statement

Currently, `SettingsView` calls `createService(for:)` repeatedly within the view body, creating new service instances on every render. Additionally, status is managed as local `@State` in the view, which doesn't follow good separation of concerns.

```swift
// Current problematic code in SettingsView
@State private var serviceStatus = DeploymentStatus(...)
@State private var isLoadingStatus = false

if config.mode != .remote, let service = createService(for: config.mode) {
    // Service is recreated on every view render
}
```

## Goals

1. **Single source of truth**: `APIConfiguration` owns service lifecycle
2. **Observable status**: Service status is observable, not view-local state
3. **Proper separation**: Views observe, services manage state
4. **Protocol flexibility**: Keep `LambdaService` protocol for concrete implementations

## Architecture Overview

```
Concrete Services (XcodeLocalService, LinuxLocalService, RemoteService)
        ↓ conform to
    LambdaService protocol (includes Combine publishers)
        ↓ held by
    ObservableService (@Observable, conforms to LambdaService)
        ↓ subscribes to publishers, updates @Observable properties
    Views observe ObservableService properties
```

### Key Insight

We need an `@Observable` layer that SwiftUI can bind to, but concrete services aren't `@Observable`. The solution:

- **`LambdaService` protocol**: Defines Combine publishers for status changes
- **Concrete services**: Publish status updates via Combine
- **`ObservableService`**: An `@Observable` class that:
  - Conforms to `LambdaService` protocol
  - Holds a concrete `LambdaService` instance
  - Subscribes to the underlying service's publishers
  - Exposes observable `status` and `isLoadingStatus` properties
  - Relays publisher updates to its `@Observable` properties

## Proposed Architecture

```
MacAppMain (App Root)
├── @State config: APIConfiguration
│   └── observableService: ObservableService  ← Owns the observable service
│       └── underlyingService: any LambdaService  ← Holds concrete service
│
└── WindowGroup
    └── ContentView
        ├── .environment(config)
        ├── .id(config.serviceId)
        │
        └── TabView
            ├── FileView
            │   └── Uses config.apiClient
            ├── UserListView
            │   └── Uses config.apiClient
            └── SettingsView
                └── Observes config.observableService.status
                └── Observes config.observableService.isLoadingStatus
```

## Implementation Steps

### Step 1: Update LambdaService Protocol with Combine Publishers

Add Combine publishers to the protocol so concrete services can publish status changes:

```swift
// Sources/SwiftDeploy/Protocols/LambdaService.swift

import Combine
import Foundation

// MARK: - Service State

public enum ServiceState: String, Sendable, CustomStringConvertible {
    case running
    case stopped

    public var description: String {
        rawValue
    }
}

public struct DeploymentStatus: Sendable {
    public let lambdaState: ServiceState
    public let s3State: ServiceState
    public let postgresState: ServiceState

    public init(lambdaState: ServiceState, s3State: ServiceState, postgresState: ServiceState) {
        self.lambdaState = lambdaState
        self.s3State = s3State
        self.postgresState = postgresState
    }
}

// MARK: - Protocol

public protocol LambdaService {
    var port: Int { get }
    var endpoint: String { get }

    // MARK: - Build
    func buildLambda(clean: Bool) async throws
    func isLambdaBuilt() -> Bool

    // MARK: - Lifecycle
    func startLambda() async throws
    func stopLambda() async throws
    func startWithServices() async throws
    func stopWithServices() async throws

    // MARK: - Testing
    func testLambda() async throws
    func waitForReady(maxAttempts: Int) async throws

    // MARK: - Status
    func status() async throws -> DeploymentStatus

    // MARK: - Combine Publishers
    var statusPublisher: AnyPublisher<DeploymentStatus, Never> { get }
    var isLoadingStatusPublisher: AnyPublisher<Bool, Never> { get }

    /// Trigger a status refresh (results published via statusPublisher)
    func refreshStatus()
}
```

### Step 2: Update Concrete Services with Publishers

Each concrete service needs to implement the Combine publishers. Here's the pattern for `XcodeLocalService` (same pattern applies to `LinuxLocalService` and `RemoteService`):

```swift
// Sources/SwiftDeploy/XcodeLocalService.swift

import Combine
import Client
import Foundation

public class XcodeLocalService: LambdaService {
    // ... existing properties ...

    // MARK: - Combine Publishers

    private let statusSubject = CurrentValueSubject<DeploymentStatus, Never>(
        DeploymentStatus(lambdaState: .stopped, s3State: .stopped, postgresState: .stopped)
    )
    private let isLoadingStatusSubject = CurrentValueSubject<Bool, Never>(false)

    public var statusPublisher: AnyPublisher<DeploymentStatus, Never> {
        statusSubject.eraseToAnyPublisher()
    }

    public var isLoadingStatusPublisher: AnyPublisher<Bool, Never> {
        isLoadingStatusSubject.eraseToAnyPublisher()
    }

    // ... existing init and methods ...

    // MARK: - Status

    public func status() async throws -> DeploymentStatus {
        // ... existing implementation ...
    }

    /// Refresh status and publish results
    public func refreshStatus() {
        isLoadingStatusSubject.send(true)
        Task {
            do {
                let newStatus = try await status()
                statusSubject.send(newStatus)
            } catch {
                statusSubject.send(DeploymentStatus(
                    lambdaState: .stopped,
                    s3State: .stopped,
                    postgresState: .stopped
                ))
            }
            isLoadingStatusSubject.send(false)
        }
    }
}
```

Apply the same pattern to:
- `LinuxLocalService.swift`
- `RemoteService.swift`

### Step 3: Create ObservableService

The `ObservableService` subscribes to the underlying service's Combine publishers and relays updates to its `@Observable` properties:

```swift
// Sources/MacApp/ObservableService.swift

import Combine
import Client
import Foundation
import SwiftDeploy

/// Observable wrapper around a LambdaService that publishes status changes
/// This allows SwiftUI views to observe service status reactively.
///
/// Subscribes to the underlying service's Combine publishers and relays
/// updates to @Observable properties for SwiftUI consumption.
@MainActor
@Observable
class ObservableService: LambdaService {
    // MARK: - Observable State (for SwiftUI)

    private(set) var status: DeploymentStatus = DeploymentStatus(
        lambdaState: .stopped,
        s3State: .stopped,
        postgresState: .stopped
    )
    private(set) var isLoadingStatus: Bool = false

    // MARK: - Underlying Service

    private var underlyingService: any LambdaService
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Own Publishers (for protocol conformance)

    private let statusSubject = CurrentValueSubject<DeploymentStatus, Never>(
        DeploymentStatus(lambdaState: .stopped, s3State: .stopped, postgresState: .stopped)
    )
    private let isLoadingStatusSubject = CurrentValueSubject<Bool, Never>(false)

    var statusPublisher: AnyPublisher<DeploymentStatus, Never> {
        statusSubject.eraseToAnyPublisher()
    }

    var isLoadingStatusPublisher: AnyPublisher<Bool, Never> {
        isLoadingStatusSubject.eraseToAnyPublisher()
    }

    // MARK: - Init

    init(service: any LambdaService) {
        self.underlyingService = service
        subscribeToService(service)
    }

    /// Replace the underlying service (called when mode changes)
    func setService(_ service: any LambdaService) {
        // Cancel existing subscriptions
        cancellables.removeAll()

        self.underlyingService = service

        // Reset status when service changes
        let defaultStatus = DeploymentStatus(
            lambdaState: .stopped,
            s3State: .stopped,
            postgresState: .stopped
        )
        self.status = defaultStatus
        self.statusSubject.send(defaultStatus)

        // Subscribe to new service's publishers
        subscribeToService(service)
    }

    /// Subscribe to the underlying service's Combine publishers
    private func subscribeToService(_ service: any LambdaService) {
        // Relay status updates to @Observable property and own publisher
        service.statusPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newStatus in
                self?.status = newStatus
                self?.statusSubject.send(newStatus)
            }
            .store(in: &cancellables)

        // Relay loading state updates
        service.isLoadingStatusPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isLoading in
                self?.isLoadingStatus = isLoading
                self?.isLoadingStatusSubject.send(isLoading)
            }
            .store(in: &cancellables)
    }

    // MARK: - LambdaService Protocol (delegated)

    var port: Int { underlyingService.port }
    var endpoint: String { underlyingService.endpoint }

    func buildLambda(clean: Bool) async throws {
        try await underlyingService.buildLambda(clean: clean)
    }

    func isLambdaBuilt() -> Bool {
        underlyingService.isLambdaBuilt()
    }

    func startLambda() async throws {
        try await underlyingService.startLambda()
    }

    func stopLambda() async throws {
        try await underlyingService.stopLambda()
    }

    func startWithServices() async throws {
        try await underlyingService.startWithServices()
    }

    func stopWithServices() async throws {
        try await underlyingService.stopWithServices()
    }

    func testLambda() async throws {
        try await underlyingService.testLambda()
    }

    func waitForReady(maxAttempts: Int) async throws {
        try await underlyingService.waitForReady(maxAttempts: maxAttempts)
    }

    // MARK: - Status

    func status() async throws -> DeploymentStatus {
        try await underlyingService.status()
    }

    /// Trigger a status refresh on the underlying service
    /// Results will be published via the subscribed publishers
    func refreshStatus() {
        underlyingService.refreshStatus()
    }
}
```

### Step 4: Update APIConfiguration

```swift
// Sources/MacApp/APIConfiguration.swift

import Client
import Foundation
import SwiftDeploy

enum ConnectionMode: String, Codable {
    case remote
    case localXcode
    case localLinux

    var displayName: String { ... }
    var detailText: String { ... }
}

@MainActor
@Observable
class APIConfiguration {
    // MARK: - Persisted State
    var remoteURL: String?
    var mode: ConnectionMode {
        didSet {
            if oldValue != mode {
                updateService()
                save()
            }
        }
    }

    // MARK: - Derived State
    private(set) var observableService: ObservableService
    private(set) var apiClient: APIClient?
    var isLoadingRemoteURL: Bool = false

    // MARK: - Private
    private let modeKey = "macApp.mode"
    private let workingDirectory: String

    init() {
        self.workingDirectory = FileManager.default.currentDirectoryPath

        // Load mode from UserDefaults
        let initialMode: ConnectionMode
        if let modeString = UserDefaults.standard.string(forKey: modeKey),
           let savedMode = ConnectionMode(rawValue: modeString) {
            initialMode = savedMode
        } else {
            initialMode = .remote
        }
        self.mode = initialMode

        // Create initial service
        let initialService = Self.createService(for: initialMode, workingDirectory: workingDirectory)
        self.observableService = ObservableService(service: initialService)
        self.apiClient = Self.createAPIClient(for: initialMode, service: initialService, remoteURL: nil)
    }

    // MARK: - Service Management

    private func updateService() {
        let newService = Self.createService(for: mode, workingDirectory: workingDirectory)
        observableService.setService(newService)
        apiClient = Self.createAPIClient(for: mode, service: newService, remoteURL: remoteURL)

        // Auto-refresh status when service changes
        observableService.refreshStatus()
    }

    private static func createService(for mode: ConnectionMode, workingDirectory: String) -> any LambdaService {
        switch mode {
        case .localXcode:
            return XcodeLocalService(workingDirectory: workingDirectory)
        case .localLinux:
            return LinuxLocalService(workingDirectory: workingDirectory)
        case .remote:
            return RemoteService(workingDirectory: workingDirectory)
        }
    }

    private static func createAPIClient(
        for mode: ConnectionMode,
        service: any LambdaService,
        remoteURL: String?
    ) -> APIClient? {
        switch mode {
        case .localXcode, .localLinux:
            return APIClient(localPort: service.port)
        case .remote:
            guard let url = remoteURL else { return nil }
            return APIClient(baseURL: url)
        }
    }

    /// Unique identifier for current service (for .id() modifier)
    /// Includes endpoint so views rebuild when URL changes
    var serviceId: String {
        "\(type(of: observableService))-\(observableService.endpoint)"
    }

    // MARK: - Remote URL

    func fetchRemoteURLFromCDK() async {
        isLoadingRemoteURL = true
        defer { isLoadingRemoteURL = false }

        guard let awsConfig = AWSAuthConfiguration.loadConfig() else {
            print("Warning: No AWS config found")
            return
        }

        if awsConfig.useAWSVault {
            print("Error: aws-vault not supported in MacApp")
            return
        }

        do {
            let deploymentService = DeploymentService(
                projectRoot: workingDirectory,
                awsConfig: awsConfig
            )

            if let apiURL = try await deploymentService.getAPIGatewayURL() {
                self.remoteURL = apiURL
                // Update apiClient with new URL
                if mode == .remote {
                    apiClient = APIClient(baseURL: apiURL)
                }
            }
        } catch {
            print("Error fetching API Gateway URL: \(error)")
        }
    }

    // MARK: - Persistence

    func save() {
        UserDefaults.standard.set(mode.rawValue, forKey: modeKey)
    }

    func clear() {
        remoteURL = nil
        mode = .remote  // This triggers updateService() via didSet
        UserDefaults.standard.removeObject(forKey: modeKey)
    }

    var isConfigured: Bool {
        switch mode {
        case .localXcode, .localLinux:
            return true
        case .remote:
            return remoteURL != nil
        }
    }
}
```

### Step 5: Simplify main.swift

```swift
// Sources/MacApp/main.swift

import AppKit
import SwiftUI

@main
struct MacAppMain: App {
    @State private var config = APIConfiguration()

    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(config)
                .id(config.serviceId)
                .task {
                    if config.mode == .remote {
                        await config.fetchRemoteURLFromCDK()
                    }
                }
        }
        .defaultSize(width: 700, height: 600)
    }
}
```

### Step 6: Simplify ContentView

```swift
// Sources/MacApp/ContentView.swift

import Client
import SwiftDeploy
import SwiftUI

struct ContentView: View {
    @Environment(APIConfiguration.self) var config

    var body: some View {
        TabView {
            if let apiClient = config.apiClient {
                FileView()
                    .tabItem {
                        Label("Files", systemImage: "doc.fill")
                    }
                    .environment(apiClient)

                UserListView()
                    .tabItem {
                        Label("Users", systemImage: "person.3.fill")
                    }
                    .environment(apiClient)
            }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
    }
}
```

### Step 7: Simplify SettingsView

Now `SettingsView` observes status from `config.observableService` instead of managing its own state:

```swift
// Sources/MacApp/SettingsView.swift

import Client
import SwiftUI
import SwiftDeploy

struct SettingsView: View {
    @Environment(APIConfiguration.self) var config

    // No more @State for serviceStatus or isLoadingStatus!
    // These are now observed from config.observableService

    var body: some View {
        @Bindable var config = config
        let service = config.observableService

        VStack(spacing: 20) {
            Text("Settings")
                .font(.title)
                .padding(.top)

            Divider()

            VStack(alignment: .leading, spacing: 15) {
                Text("API Configuration")
                    .font(.headline)

                // Mode Picker
                VStack(alignment: .leading, spacing: 5) {
                    Text("Lambda Mode")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Picker("Mode", selection: $config.mode) {
                        Text("Remote").tag(ConnectionMode.remote)
                        Text("Local Xcode").tag(ConnectionMode.localXcode)
                        Text("Local Linux").tag(ConnectionMode.localLinux)
                    }
                    .pickerStyle(.segmented)

                    Text(config.mode.detailText)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                // Remote URL section
                if config.mode == .remote {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("API Gateway URL")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack {
                            TextField("Fetched from CDK", text: .constant(config.remoteURL ?? "Not fetched yet"))
                                .textFieldStyle(.roundedBorder)
                                .disabled(true)

                            Button(config.isLoadingRemoteURL ? "Fetching..." : "Fetch from CDK") {
                                Task {
                                    await config.fetchRemoteURLFromCDK()
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(config.isLoadingRemoteURL)
                        }

                        Text("URL is automatically fetched from deployed CDK stack")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                // Local Lambda endpoint
                if config.mode != .remote {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Local Lambda Endpoint")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        TextField("Local endpoint", text: .constant(service.endpoint))
                            .textFieldStyle(.roundedBorder)
                            .disabled(true)

                        Text("Make sure local Lambda is running on port \(service.port)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                // Service Status Section - observes service.status and service.isLoadingStatus
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Service Status")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Spacer()

                        Button(action: { service.refreshStatus() }) {
                            if service.isLoadingStatus {
                                ProgressView()
                                    .scaleEffect(0.7)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                        }
                        .buttonStyle(.borderless)
                        .disabled(service.isLoadingStatus)
                    }

                    HStack(spacing: 20) {
                        StatusIndicator(label: "Lambda", state: service.status.lambdaState)
                        StatusIndicator(label: "S3", state: service.status.s3State)
                        StatusIndicator(label: "PostgreSQL", state: service.status.postgresState)
                    }
                    .padding(.vertical, 4)
                }

                Button("Reset All to Defaults") {
                    config.clear()
                }
                .buttonStyle(.bordered)

                Divider()
                    .padding(.top)

                // Current Configuration
                VStack(alignment: .leading, spacing: 10) {
                    Text("Current Configuration")
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text("Mode:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(config.mode.displayName)
                                .font(.caption)
                                .textSelection(.enabled)
                        }
                        HStack {
                            Text("Configured:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(config.isConfigured ? "Yes" : "No")
                                .font(.caption)
                                .foregroundColor(config.isConfigured ? .green : .red)
                        }
                        HStack {
                            Text("Endpoint:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(service.endpoint)
                                .font(.caption)
                                .textSelection(.enabled)
                        }
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                }
                .onAppear {
                    service.refreshStatus()
                }

                // ... About section ...
            }
            .padding(.horizontal, 20)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

**Key changes in SettingsView**:
- Removed `@State private var serviceStatus`
- Removed `@State private var isLoadingStatus`
- Removed `createService(for:)` method
- Removed `onModeChanged(_:)` method
- Removed `refreshStatus()` method
- Now uses `service.status`, `service.isLoadingStatus`, `service.refreshStatus()`

## Files Summary

| File | Change |
|------|--------|
| `LambdaService.swift` | Add Combine publishers: `statusPublisher`, `isLoadingStatusPublisher`, `refreshStatus()` |
| `XcodeLocalService.swift` | Add `CurrentValueSubject`s, implement publishers and `refreshStatus()` |
| `LinuxLocalService.swift` | Add `CurrentValueSubject`s, implement publishers and `refreshStatus()` |
| `RemoteService.swift` | Add `CurrentValueSubject`s, implement publishers and `refreshStatus()` |
| **New: `ObservableService.swift`** | Observable wrapper that subscribes to service publishers, exposes `@Observable` properties |
| `APIConfiguration.swift` | Add `observableService`, `apiClient`, `serviceId`, `updateService()` |
| `main.swift` | Add `.id(config.serviceId)`, simplify |
| `ContentView.swift` | Remove all service creation logic |
| `SettingsView.swift` | Remove status state, observe from `config.observableService` |

## Files Unchanged

- `FileView.swift` - Already uses APIClient from environment
- `UserListView.swift` - Already uses APIClient from environment
- `UserFormView.swift` - Already uses APIClient from environment

## Data Flow

### Mode Change Flow

```
User changes mode in SettingsView
        ↓
config.mode = newValue (via @Bindable)
        ↓
mode.didSet triggers updateService():
  1. Creates new concrete service (XcodeLocalService, LinuxLocalService, or RemoteService)
  2. Calls observableService.setService(newService)
     → Cancels old subscriptions
     → Subscribes to new service's Combine publishers
  3. Updates apiClient
  4. Calls observableService.refreshStatus()
        ↓
Concrete service publishes via Combine
        ↓
ObservableService receives via subscription, updates @Observable properties
        ↓
SettingsView automatically re-renders with new status
```

### Status Refresh Flow (Combine)

```
User taps refresh button
        ↓
service.refreshStatus() called
        ↓
ObservableService.refreshStatus()
        ↓
underlyingService.refreshStatus()
        ↓
Concrete service:
  1. isLoadingStatusSubject.send(true)
  2. Fetches status async
  3. statusSubject.send(newStatus)
  4. isLoadingStatusSubject.send(false)
        ↓
ObservableService subscriptions receive updates:
  → self.isLoadingStatus = true   (triggers SwiftUI update)
  → self.status = newStatus       (triggers SwiftUI update)
  → self.isLoadingStatus = false  (triggers SwiftUI update)
        ↓
SettingsView automatically re-renders
```

## Benefits

1. **Single source of truth**: `APIConfiguration` owns everything
2. **Observable status**: Views observe `observableService.status` reactively
3. **No view-local state for status**: Status lives in `ObservableService`
4. **Protocol preserved**: Concrete services still conform to `LambdaService`
5. **Clean separation**: Views observe, services manage
6. **Auto-refresh**: Status refreshes automatically when service changes

## Testing Plan

1. Switch between all three modes (Remote, Local Xcode, Local Linux)
2. Verify status updates automatically after mode change
3. Verify manual refresh button works
4. Verify loading indicator shows during status fetch
5. Verify endpoint displays correct value for each mode
6. Verify Files/Users tabs work correctly
7. Verify mode persists across app restart
8. Verify remote URL fetch works and updates apiClient
