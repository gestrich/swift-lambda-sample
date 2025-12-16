import sdk_client
import sdk_cli
import Foundation
import service_deploy

/// Top-level model that creates and holds all services.
/// Manages mode selection and provides access to individual services.
@MainActor
@Observable
class AppModel {
    // MARK: - Services (Eager Initialization)

    /// All services are created at app startup. The active mode determines which is in use.
    let remoteService: DeploymentService
    let xcodeLocalService: XcodeLocalModel
    let linuxLocalService: LinuxLocalModel

    /// Model for checking dependency installation status
    let dependencyStatusModel: DependencyStatusModel

    /// Observable models for local services (used by LocalServiceView)
    let xcodeLocalModel: LocalServicesModel
    let linuxLocalModel: LocalServicesModel

    /// The current local model based on mode (nil if remote)
    var currentLocalModel: LocalServicesModel? {
        switch mode {
        case .localXcode: return xcodeLocalModel
        case .localLinux: return linuxLocalModel
        case .remote: return nil
        }
    }

    // MARK: - Persisted State

    var mode: ConnectionMode {
        didSet {
            if oldValue.persistenceKey != mode.persistenceKey {
                onModeChanged(oldMode: oldValue)
            }
        }
    }

    // MARK: - Private

    private let modeKey = "macApp.mode"

    // MARK: - Init

    init() {
        let projectDirectory = Self.resolveProjectDirectory()

        // Create all services eagerly at startup
        let remote = DeploymentService(projectRoot: projectDirectory)
        let xcode = XcodeLocalModel(workingDirectory: projectDirectory)
        let linux = LinuxLocalModel(workingDirectory: projectDirectory)

        self.remoteService = remote
        self.xcodeLocalService = xcode
        self.linuxLocalService = linux

        self.dependencyStatusModel = DependencyStatusModel(cliClient: CLIClient(defaultWorkingDirectory: projectDirectory))

        // Create observable models for local services
        self.xcodeLocalModel = LocalServicesModel(service: xcode)
        self.linuxLocalModel = LocalServicesModel(service: linux)

        // Load mode from UserDefaults and use pre-created services
        let savedKey = UserDefaults.standard.string(forKey: modeKey) ?? "remote"
        let initialMode: ConnectionMode
        switch savedKey {
        case XcodeLocalModel.persistenceKey:
            initialMode = .localXcode(xcode)
        case LinuxLocalModel.persistenceKey:
            initialMode = .localLinux(linux)
        default:
            initialMode = .remote(remote)
        }
        self.mode = initialMode

        // Start services if necessary for initial mode
        Task {
            await self.startCurrentServiceIfNecessary()
        }

        // Check dependency installation status
        Task {
            await self.dependencyStatusModel.checkAll()
        }
    }

    /// Start the current service if necessary (used on init and mode change)
    private func startCurrentServiceIfNecessary() async {
        print("🔄 startCurrentServiceIfNecessary called, mode: \(mode.persistenceKey)")
        if let localModel = currentLocalModel {
            print("🔄 Found localModel, calling startIfNecessary")
            await localModel.startIfNecessary()
            print("🔄 startIfNecessary completed")
        } else {
            print("🔄 No localModel (remote mode), calling refresh")
            await remoteService.refresh()
        }
    }

    /// Resolve the project directory automatically using ProjectPathResolver
    private static func resolveProjectDirectory() -> String {
        do {
            let resolver = ProjectPathResolver()
            let projectRoot = try resolver.resolveProjectRoot()
            return projectRoot.path
        } catch {
            print("⚠️ Failed to resolve project directory: \(error.localizedDescription)")
            // Fallback to current directory
            return FileManager.default.currentDirectoryPath
        }
    }

    // MARK: - Mode Changes

    private func onModeChanged(oldMode: ConnectionMode) {
        print("🔄 onModeChanged: \(oldMode.persistenceKey) -> \(mode.persistenceKey)")
        // Save preference
        save()

        // Start services if necessary and refresh status
        Task {
            await startCurrentServiceIfNecessary()
        }
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

    // MARK: - Convenience Properties

    /// Whether the current service is configured and ready to use
    var isConfigured: Bool {
        switch mode {
        case .remote(let service):
            return service.isConfigured
        case .localXcode(let service):
            return service.isConfigured
        case .localLinux(let service):
            return service.isConfigured
        }
    }

    /// Refresh status for the current service
    func refreshStatus() {
        switch mode {
        case .remote(let service):
            Task { await service.refresh() }
        case .localXcode(let service):
            service.refreshStatus()
        case .localLinux(let service):
            service.refreshStatus()
        }
    }

    // MARK: - Persistence

    func save() {
        UserDefaults.standard.set(mode.persistenceKey, forKey: modeKey)
    }
}

/// Connection mode for the API - simple enum holding service references
@MainActor
enum ConnectionMode {
    case remote(DeploymentService)
    case localXcode(XcodeLocalModel)
    case localLinux(LinuxLocalModel)

    /// Persistence key for saving/restoring mode selection
    var persistenceKey: String {
        switch self {
        case .remote: return "remote"
        case .localXcode: return XcodeLocalModel.persistenceKey
        case .localLinux: return LinuxLocalModel.persistenceKey
        }
    }

    /// Local service if applicable (for LambdaService protocol)
    var localService: LambdaService? {
        switch self {
        case .localXcode(let service): return service
        case .localLinux(let service): return service
        case .remote: return nil
        }
    }
}
