import CLIKit
import Client
import Combine
import Foundation
import SwiftDeploy

/// Connection mode for the API, holding the service as an associated value.
/// Conforms to LambdaService by forwarding all calls to its underlying service.
@MainActor
enum ConnectionMode: LambdaService {
    case remote(RemoteService)
    case localXcode(XcodeLocalService)
    case localLinux(LinuxLocalService)

    /// The underlying service
    var service: any LambdaService {
        switch self {
        case .remote(let service): return service
        case .localXcode(let service): return service
        case .localLinux(let service): return service
        }
    }

    // MARK: - LambdaService Protocol (forwarded to service)

    static var persistenceKey: String {
        fatalError("Use instance persistenceKey instead")
    }

    /// Instance-level persistence key (delegates to service's static property)
    var persistenceKey: String {
        type(of: service).persistenceKey
    }

    var port: Int { service.port }
    var endpoint: String { service.endpoint }
    var endpointLabel: String { service.endpointLabel }
    var endpointHelpText: String { service.endpointHelpText }
    var apiClient: APIClient { service.apiClient }
    var isConfigured: Bool { service.isConfigured }
    var cliService: CLIService { service.cliService }
    var unifiedOutput: UnifiedOutputState { service.unifiedOutput }

    var statusPublisher: AnyPublisher<DeploymentStatus, Never> {
        service.statusPublisher
    }

    var isLoadingStatusPublisher: AnyPublisher<Bool, Never> {
        service.isLoadingStatusPublisher
    }

    func testLambda() async throws {
        try await service.testLambda()
    }

    func waitForReady(maxAttempts: Int) async throws {
        try await service.waitForReady(maxAttempts: maxAttempts)
    }

    func status() async throws -> DeploymentStatus {
        try await service.status()
    }

    func refreshStatus() {
        service.refreshStatus()
    }

    // MARK: - Docker Service Control

    /// Access the LocalDockerServicesProvider if in a local mode (Xcode or Linux)
    /// Returns nil for remote mode since AWS manages the services
    var dockerServicesProvider: LocalDockerServicesProvider? {
        switch self {
        case .localXcode(let service):
            return service
        case .localLinux(let service):
            return service
        case .remote:
            return nil
        }
    }

    // MARK: - Build Provider

    /// Access the LocalBuildProvider if in a local mode (Xcode or Linux)
    /// Returns nil for remote mode since builds are done via CI/CD pipeline
    var buildProvider: LocalBuildProvider? {
        switch self {
        case .localXcode(let service):
            return service
        case .localLinux(let service):
            return service
        case .remote:
            return nil
        }
    }

    // MARK: - Lambda Provider

    /// Access the LocalLambdaProvider if in a local mode (Xcode or Linux)
    /// Returns nil for remote mode since Lambda runs on-demand in AWS
    var lambdaProvider: LocalLambdaProvider? {
        switch self {
        case .localXcode(let service):
            return service
        case .localLinux(let service):
            return service
        case .remote:
            return nil
        }
    }

    // MARK: - Display Properties

    var displayName: String {
        switch self {
        case .remote:
            return "Remote (API Gateway)"
        case .localXcode:
            return "Local Xcode (Native)"
        case .localLinux:
            return "Local Linux (Container)"
        }
    }

    var detailText: String {
        switch self {
        case .remote:
            return "Connect to deployed AWS API Gateway"
        case .localXcode:
            return "Native macOS build - fast iteration, best for development"
        case .localLinux:
            return "Docker container build - matches AWS Lambda environment"
        }
    }

    var isRemote: Bool {
        if case .remote = self { return true }
        return false
    }

    /// Access the RemoteService if in remote mode
    var remoteService: RemoteService? {
        if case .remote(let service) = self { return service }
        return nil
    }

    var isLocalXcode: Bool {
        if case .localXcode = self { return true }
        return false
    }

    var isLocalLinux: Bool {
        if case .localLinux = self { return true }
        return false
    }
}

/// Main model for the MacApp using MV (Model-View) architecture.
/// Manages connection mode, service state, and build operations.
/// Conforms to LambdaService, delegating to the underlying service based on current mode.
@MainActor
@Observable
class MacAppModel: LambdaService {
    // MARK: - Pre-Created Services (Eager Initialization)

    /// All services are created at app startup. The active mode determines which is in use.
    let remoteService: RemoteService
    let xcodeLocalService: XcodeLocalService
    let linuxLocalService: LinuxLocalService

    // MARK: - Persisted State

    var mode: ConnectionMode {
        didSet {
            if oldValue.persistenceKey != mode.persistenceKey {
                onModeChanged(oldMode: oldValue)
            }
        }
    }

    // MARK: - Observable Service State (for SwiftUI)

    private(set) var status: DeploymentStatus = .stopped
    private(set) var isLoadingStatus: Bool = false

    // MARK: - Unified Output

    var unifiedOutput: UnifiedOutputState { mode.unifiedOutput }

    // MARK: - Build Provider (for Local modes only)

    /// Build provider from local service (only available in local modes)
    var buildProvider: LocalBuildProvider? {
        mode.buildProvider
    }

    // MARK: - Lambda Provider (for Local modes only)

    /// Lambda provider from local service (only available in local modes)
    var lambdaProvider: LocalLambdaProvider? {
        mode.lambdaProvider
    }

    // MARK: - GitHub Service (for Remote mode)

    /// GitHub service from RemoteService (always available since RemoteService is eagerly initialized)
    var githubService: GitHubService? {
        remoteService.githubService
    }

    // MARK: - CDK Infrastructure Service (for Remote mode)

    /// CDK Infrastructure service from RemoteService (always available since RemoteService is eagerly initialized)
    var cdkInfrastructureService: CDKInfrastructureService? {
        remoteService.cdkInfrastructureService
    }

    // MARK: - Private

    private var cancellables = Set<AnyCancellable>()
    private let modeKey = "macApp.mode"
    private let workingDirectory: String

    // Own publishers for protocol conformance
    private let statusSubject = CurrentValueSubject<DeploymentStatus, Never>(.stopped)
    private let isLoadingStatusSubject = CurrentValueSubject<Bool, Never>(false)

    // MARK: - Init

    init() {
        let projectDirectory = Self.resolveProjectDirectory()
        self.workingDirectory = projectDirectory

        // Create all services eagerly at startup
        self.remoteService = RemoteService(workingDirectory: projectDirectory)
        self.xcodeLocalService = XcodeLocalService(workingDirectory: projectDirectory)
        self.linuxLocalService = LinuxLocalService(workingDirectory: projectDirectory)

        // Load mode from UserDefaults and use pre-created services
        let savedKey = UserDefaults.standard.string(forKey: modeKey) ?? "remote"
        switch savedKey {
        case XcodeLocalService.persistenceKey:
            self.mode = .localXcode(xcodeLocalService)
        case LinuxLocalService.persistenceKey:
            self.mode = .localLinux(linuxLocalService)
        default:
            self.mode = .remote(remoteService)
        }

        // Subscribe to service publishers
        subscribeToService(mode)
    }

    /// Path to the app config file
    private static var configFilePath: String {
        "\(FileManager.default.homeDirectoryForCurrentUser.path)/.swiftSampleDemo/swiftLambdaDemo.json"
    }

    /// Resolve the project directory from config file or fallback
    private static func resolveProjectDirectory() -> String {
        // Try to read from config file
        if let data = FileManager.default.contents(atPath: configFilePath),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let projectDir = json["projectDirectory"] as? String,
           FileManager.default.fileExists(atPath: "\(projectDir)/Package.swift") {
            return projectDir
        }

        // Fallback: check if current directory has Package.swift
        let currentDir = FileManager.default.currentDirectoryPath
        if FileManager.default.fileExists(atPath: "\(currentDir)/Package.swift") {
            return currentDir
        }

        // Last resort: return current directory anyway
        return currentDir
    }

    // MARK: - Mode Changes

    private func onModeChanged(oldMode: ConnectionMode) {
        // Save preference
        save()

        // Stop old services and start new ones
        Task {
            // Stop old services if it was a local mode (keep old subscription active)
            if let oldLambdaProvider = oldMode.lambdaProvider {
                do {
                    try await oldLambdaProvider.stopWithServices()
                } catch {
                    print("⚠️ Error stopping old services (may not have been running): \(error)")
                }
            }

            // Now switch subscriptions to new service
            cancellables.removeAll()
            subscribeToService(mode)

            // Start new services if it's a local mode
            if lambdaProvider != nil {
                await startServices()
            } else {
                // For remote mode, just refresh status
                refreshStatus()
            }
        }
    }

    /// Start services for the current mode and refresh status
    func startServices() async {
        guard let lambdaProvider = lambdaProvider else {
            refreshStatus()
            return
        }

        do {
            try await lambdaProvider.startWithServices()
        } catch {
            print("⚠️ Failed to start services: \(error)")
            refreshStatus()
        }
    }

    // MARK: - Docker Service Control

    /// Access the LocalDockerServicesProvider if in a local mode
    var dockerServicesProvider: LocalDockerServicesProvider? {
        mode.dockerServicesProvider
    }

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

    /// Unique identifier for current service (for .id() modifier)
    var serviceId: String {
        "\(mode.persistenceKey)-\(endpoint)"
    }

    // MARK: - Mode Setters (for Picker binding)

    func setRemote() {
        mode = .remote(remoteService)
    }

    func setLocalXcode() {
        mode = .localXcode(xcodeLocalService)
    }

    func setLocalLinux() {
        mode = .localLinux(linuxLocalService)
    }

    // MARK: - LambdaService Protocol (delegated to mode)

    static let persistenceKey = "macAppModel"

    var port: Int { mode.port }
    var endpoint: String { mode.endpoint }
    var endpointLabel: String { mode.endpointLabel }
    var endpointHelpText: String { mode.endpointHelpText }
    var apiClient: APIClient { mode.apiClient }
    var isConfigured: Bool { mode.isConfigured }
    var cliService: CLIService { mode.cliService }

    var statusPublisher: AnyPublisher<DeploymentStatus, Never> {
        statusSubject.eraseToAnyPublisher()
    }

    var isLoadingStatusPublisher: AnyPublisher<Bool, Never> {
        isLoadingStatusSubject.eraseToAnyPublisher()
    }

    func testLambda() async throws {
        try await mode.testLambda()
    }

    func waitForReady(maxAttempts: Int) async throws {
        try await mode.waitForReady(maxAttempts: maxAttempts)
    }

    func status() async throws -> DeploymentStatus {
        try await mode.status()
    }

    func refreshStatus() {
        mode.refreshStatus()
    }

    // MARK: - Persistence

    func save() {
        UserDefaults.standard.set(mode.persistenceKey, forKey: modeKey)
    }
}
