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
    var unifiedOutput: UnifiedOutputState { service.unifiedOutput }
    var buildState: BuildState { service.buildState }
    var lambdaState: LambdaState { service.lambdaState }

    var statusPublisher: AnyPublisher<DeploymentStatus, Never> {
        service.statusPublisher
    }

    var isLoadingStatusPublisher: AnyPublisher<Bool, Never> {
        service.isLoadingStatusPublisher
    }

    func build(clean: Bool) async throws {
        try await service.build(clean: clean)
    }

    func isLambdaBuilt() -> Bool {
        service.isLambdaBuilt()
    }

    func deleteBuild() async throws {
        try await service.deleteBuild()
    }

    func refreshBuildStatus() {
        service.refreshBuildStatus()
    }

    func startLambda() async throws {
        try await service.startLambda()
    }

    func stopLambda() async throws {
        try await service.stopLambda()
    }

    func startWithServices() async throws {
        try await service.startWithServices()
    }

    func stopWithServices() async throws {
        try await service.stopWithServices()
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

    func startS3() async throws {
        switch self {
        case .localXcode(let service):
            try await service.startS3()
        case .localLinux(let service):
            try await service.startS3()
        case .remote:
            break
        }
    }

    func stopS3() async throws {
        switch self {
        case .localXcode(let service):
            try await service.stopS3()
        case .localLinux(let service):
            try await service.stopS3()
        case .remote:
            break
        }
    }

    func startDatabase() async throws {
        switch self {
        case .localXcode(let service):
            try await service.startDatabase()
        case .localLinux(let service):
            try await service.startDatabase()
        case .remote:
            break
        }
    }

    func stopDatabase() async throws {
        switch self {
        case .localXcode(let service):
            try await service.stopDatabase()
        case .localLinux(let service):
            try await service.stopDatabase()
        case .remote:
            break
        }
    }

    var s3DataDirectory: String? {
        switch self {
        case .localXcode(let service):
            return service.s3DataDirectory
        case .localLinux(let service):
            return service.s3DataDirectory
        case .remote:
            return nil
        }
    }

    var postgresDataDirectory: String? {
        switch self {
        case .localXcode(let service):
            return service.postgresDataDirectory
        case .localLinux(let service):
            return service.postgresDataDirectory
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

    /// Access to GitHub CI state (only available for remote mode)
    var githubCIState: GitHubCIState? {
        if case .remote(let service) = self {
            return service.githubCIState
        }
        return nil
    }

    /// Access to RemoteService (only available for remote mode)
    var remoteService: RemoteService? {
        if case .remote(let service) = self {
            return service
        }
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

    /// Create a mode with its service from a persistence key
    static func from(key: String, workingDirectory: String) -> ConnectionMode {
        switch key {
        case XcodeLocalService.persistenceKey:
            return .localXcode(XcodeLocalService(workingDirectory: workingDirectory))
        case LinuxLocalService.persistenceKey:
            return .localLinux(LinuxLocalService(workingDirectory: workingDirectory))
        default:
            return .remote(RemoteService(workingDirectory: workingDirectory))
        }
    }
}

/// Main model for the MacApp using MV (Model-View) architecture.
/// Manages connection mode, service state, and build operations.
/// Conforms to LambdaService, delegating to the underlying service based on current mode.
@MainActor
@Observable
class MacAppModel: LambdaService {
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

    // MARK: - Build State

    var buildState: BuildState { mode.buildState }
    var lambdaState: LambdaState { mode.lambdaState }

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

        // Load mode from UserDefaults
        let savedKey = UserDefaults.standard.string(forKey: modeKey) ?? "remote"
        self.mode = ConnectionMode.from(key: savedKey, workingDirectory: projectDirectory)

        // Subscribe to service publishers
        subscribeToService(mode)

        // Set default working directory for CLIService (after init completes)
        Task {
            await CLIService.shared.setDefaultWorkingDirectory(projectDirectory)
        }
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
            if !oldMode.isRemote {
                do {
                    try await oldMode.stopWithServices()
                } catch {
                    print("⚠️ Error stopping old services (may not have been running): \(error)")
                }
            }

            // Now switch subscriptions to new service
            cancellables.removeAll()
            subscribeToService(mode)

            // Start new services if it's a local mode
            if !mode.isRemote {
                await startServices()
            } else {
                // For remote mode, just refresh status
                refreshStatus()
            }
        }
    }

    /// Start services for the current mode and refresh status
    func startServices() async {
        guard !mode.isRemote else {
            refreshStatus()
            return
        }

        do {
            try await mode.startWithServices()
        } catch {
            print("⚠️ Failed to start services: \(error)")
            refreshStatus()
        }
    }

    // MARK: - Build

    /// Build Lambda, updating buildState
    func buildLambda(clean: Bool = false) async throws {
        try await mode.build(clean: clean)
    }

    // MARK: - Docker Service Control

    func startS3() async throws {
        try await mode.startS3()
        refreshStatus()
    }

    func stopS3() async throws {
        try await mode.stopS3()
        refreshStatus()
    }

    func startDatabase() async throws {
        try await mode.startDatabase()
        refreshStatus()
    }

    func stopDatabase() async throws {
        try await mode.stopDatabase()
        refreshStatus()
    }

    var s3DataDirectory: String? {
        mode.s3DataDirectory
    }

    var postgresDataDirectory: String? {
        mode.postgresDataDirectory
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
        mode = .remote(RemoteService(workingDirectory: workingDirectory))
    }

    func setLocalXcode() {
        mode = .localXcode(XcodeLocalService(workingDirectory: workingDirectory))
    }

    func setLocalLinux() {
        mode = .localLinux(LinuxLocalService(workingDirectory: workingDirectory))
    }

    // MARK: - LambdaService Protocol (delegated to mode)

    static let persistenceKey = "macAppModel"

    var port: Int { mode.port }
    var endpoint: String { mode.endpoint }
    var endpointLabel: String { mode.endpointLabel }
    var endpointHelpText: String { mode.endpointHelpText }
    var apiClient: APIClient { mode.apiClient }
    var isConfigured: Bool { mode.isConfigured }

    var statusPublisher: AnyPublisher<DeploymentStatus, Never> {
        statusSubject.eraseToAnyPublisher()
    }

    var isLoadingStatusPublisher: AnyPublisher<Bool, Never> {
        isLoadingStatusSubject.eraseToAnyPublisher()
    }

    func build(clean: Bool) async throws {
        try await mode.build(clean: clean)
    }

    func isLambdaBuilt() -> Bool {
        mode.isLambdaBuilt()
    }

    func deleteBuild() async throws {
        try await mode.deleteBuild()
    }

    func refreshBuildStatus() {
        mode.refreshBuildStatus()
    }

    func startLambda() async throws {
        try await mode.startLambda()
    }

    func stopLambda() async throws {
        try await mode.stopLambda()
    }

    func startWithServices() async throws {
        try await mode.startWithServices()
    }

    func stopWithServices() async throws {
        try await mode.stopWithServices()
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
