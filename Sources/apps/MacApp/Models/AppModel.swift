import Foundation
import CLISDK
import ClientService
import DeployRemoteFeature
import DeployCoreService
import GitHubSDK
import StorageService

/// Top-level model that creates and holds all services.
/// Manages mode selection and provides access to individual services.
@MainActor
@Observable
class AppModel {
    // MARK: - Services

    /// Remote service is optional - nil if AWS config is missing
    let remoteModel: DeployRemoteModel?

    /// Error from failed remote service initialization (nil if service was created successfully)
    let remoteServiceError: Error?

    /// GitHub CI model is optional - nil if GitHub config is missing
    private(set) var githubModel: GitHubCIModel?

    let xcodeLocalService: DeployXcodeModel
    let linuxLocalService: DeployLinuxModel

    /// Model for checking dependency installation status (lazy - created on first access)
    private var _dependencyStatusModel: DependencyStatusModel?

    /// Get or create the dependency status model (lazy initialization)
    var dependencyStatusModel: DependencyStatusModel {
        if let model = _dependencyStatusModel {
            return model
        }
        let model = DependencyStatusModel(cliClient: cliClient)
        _dependencyStatusModel = model
        Task {
            await model.checkAll()
        }
        return model
    }

    /// Observable models for local services (used by LocalServiceView)
    let xcodeLocalModel: LocalServicesModel
    let linuxLocalModel: LocalServicesModel

    /// The current local model based on mode (nil if remote)
    var currentLocalModel: LocalServicesModel? {
        switch mode {
        case .localXcode: return xcodeLocalModel
        case .localLinux: return linuxLocalModel
        case .remoteModel: return nil
        case .unconfigured: return nil
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
    private let cliClient: CLIClient

    // MARK: - Init

    init() {
        let projectDirectory = Self.resolveProjectDirectory()
        self.cliClient = CLIClient(defaultWorkingDirectory: projectDirectory)

        // Create remote service - may fail if AWS config is missing
        var remote: DeployRemoteModel?
        var remoteError: Error?
        do {
            remote = try DeployRemoteModel(projectRoot: projectDirectory, cliClient: cliClient)
        } catch {
            remoteError = error
        }

        // Create GitHub CI model if config is available
        var github: GitHubCIModel?
        if let githubConfig = GitHubConfiguration.loadConfig() {
            github = GitHubCIModel(
                projectRoot: projectDirectory,
                config: githubConfig,
                cliClient: cliClient
            )
        }

        let xcode = DeployXcodeModel(workingDirectory: projectDirectory)
        let linux = DeployLinuxModel(workingDirectory: projectDirectory)

        self.remoteModel = remote
        self.remoteServiceError = remoteError
        self.githubModel = github
        self.xcodeLocalService = xcode
        self.linuxLocalService = linux

        // Create observable models for local services
        self.xcodeLocalModel = LocalServicesModel(service: xcode)
        self.linuxLocalModel = LocalServicesModel(service: linux)

        // Load mode from UserDefaults and use pre-created services
        let savedKey = UserDefaults.standard.string(forKey: modeKey) ?? DeployRemoteModel.persistenceKey
        let initialMode: ConnectionMode
        switch savedKey {
        case DeployRemoteModel.persistenceKey:
            if let remote {
                initialMode = .remoteModel(remote)
            } else {
                initialMode = .localXcode(xcode)
            }
        case DeployXcodeModel.persistenceKey:
            initialMode = .localXcode(xcode)
        case DeployLinuxModel.persistenceKey:
            initialMode = .localLinux(linux)
        default:
            // Fall back to Xcode mode for unknown keys
            initialMode = .localXcode(xcode)
        }
        self.mode = initialMode

        // Start services if necessary for initial mode
        Task {
            await self.startCurrentServiceIfNecessary()
        }
    }

    /// Start the current service if necessary (used on init and mode change)
    private func startCurrentServiceIfNecessary() async {
        print("🔄 startCurrentServiceIfNecessary called, mode: \(mode.persistenceKey)")
        if let localModel = currentLocalModel {
            print("🔄 Found localModel, calling startIfNecessary")
            await localModel.startIfNecessary()
            print("🔄 startIfNecessary completed")
        } else if let remoteModel {
            print("🔄 No localModel (remote mode), calling refresh")
            await remoteModel.refresh()
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
        guard let remoteModel else { return }
        mode = .remoteModel(remoteModel)
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
        case .remoteModel(let service):
            return service.state.isConfigured
        case .localXcode(let service):
            return service.isConfigured
        case .localLinux(let service):
            return service.isConfigured
        case .unconfigured:
            return false
        }
    }

    /// Refresh status for the current service
    func refreshStatus() {
        Task {
            switch mode {
            case .remoteModel(let service):
                await service.refresh()
            case .localXcode(let service):
                await service.refresh()
            case .localLinux(let service):
                await service.refresh()
            case .unconfigured:
                break
            }
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
    case remoteModel(DeployRemoteModel)
    case localXcode(DeployXcodeModel)
    case localLinux(DeployLinuxModel)
    case unconfigured

    /// Persistence key for saving/restoring mode selection
    var persistenceKey: String {
        switch self {
        case .remoteModel: return DeployRemoteModel.persistenceKey
        case .localXcode: return DeployXcodeModel.persistenceKey
        case .localLinux: return DeployLinuxModel.persistenceKey
        case .unconfigured: return "unconfigured"
        }
    }

    /// Local service if applicable (for LambdaService protocol)
    var localService: LambdaService? {
        switch self {
        case .localXcode(let service): return service
        case .localLinux(let service): return service
        case .remoteModel: return nil
        case .unconfigured: return nil
        }
    }
}
