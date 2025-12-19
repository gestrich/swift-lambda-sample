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
    private(set) var remoteModel: DeployRemoteModel?

    /// Error from failed remote service initialization (nil if service was created successfully)
    private(set) var remoteServiceError: Error?

    /// GitHub CI model is optional - nil if GitHub config is missing
    private(set) var githubModel: GitHubCIModel?

    let xcodeLocalService: DeployXcodeModel

    /// Linux development model - created lazily on first access
    private var _linuxLocalService: DeployLinuxModel?
    private var _linuxLocalModel: LocalServicesModel?
    private let projectDirectory: String

    /// Get or create the Linux local service (lazy initialization)
    var linuxLocalService: DeployLinuxModel {
        if let service = _linuxLocalService {
            return service
        }
        let service = DeployLinuxModel(workingDirectory: projectDirectory)
        _linuxLocalService = service
        _linuxLocalModel = LocalServicesModel(service: service)
        return service
    }

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

    /// Get or create the Linux local model (lazy initialization along with linuxLocalService)
    var linuxLocalModel: LocalServicesModel {
        // Accessing linuxLocalService creates both service and model if needed
        _ = linuxLocalService
        return _linuxLocalModel!
    }

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
        self.projectDirectory = projectDirectory
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
        // Note: linuxLocalService is created lazily on first access

        self.remoteModel = remote
        self.remoteServiceError = remoteError
        self.githubModel = github
        self.xcodeLocalService = xcode

        // Create observable model for Xcode service (Linux model is created lazily)
        self.xcodeLocalModel = LocalServicesModel(service: xcode)

        // Load mode from UserDefaults and use pre-created services
        // Note: For Linux mode, we temporarily set to Xcode and switch after init
        let savedKey = UserDefaults.standard.string(forKey: modeKey) ?? DeployRemoteModel.persistenceKey
        let initialMode: ConnectionMode
        let needsLinuxSwitch: Bool
        switch savedKey {
        case DeployRemoteModel.persistenceKey:
            if let remote {
                initialMode = .remoteModel(remote)
            } else {
                initialMode = .localXcode(xcode)
            }
            needsLinuxSwitch = false
        case DeployXcodeModel.persistenceKey:
            initialMode = .localXcode(xcode)
            needsLinuxSwitch = false
        case DeployLinuxModel.persistenceKey:
            // Can't access linuxLocalService before init completes
            // Temporarily set to Xcode, then switch to Linux after init
            initialMode = .localXcode(xcode)
            needsLinuxSwitch = true
        default:
            // Fall back to Xcode mode for unknown keys
            initialMode = .localXcode(xcode)
            needsLinuxSwitch = false
        }
        self.mode = initialMode

        // Now that init is complete, switch to Linux if that was the saved mode
        if needsLinuxSwitch {
            self.mode = .localLinux(linuxLocalService)
        }

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

    // MARK: - Model Lifecycle

    /// Reload configuration-dependent models from disk.
    /// Call this after Settings saves new configuration to create/recreate models.
    func reloadModels() {
        reloadRemoteModel()
        reloadGitHubModel()

        // If current mode was remote and the model was recreated, update the mode reference
        if case .remoteModel = mode, let remote = remoteModel {
            mode = .remoteModel(remote)
        }
    }

    /// Reload the remote model from AWS configuration.
    /// Creates a new model if config is now available, or clears it if config was removed.
    private func reloadRemoteModel() {
        do {
            remoteModel = try DeployRemoteModel(projectRoot: projectDirectory, cliClient: cliClient)
            remoteServiceError = nil
        } catch {
            remoteModel = nil
            remoteServiceError = error
        }
    }

    /// Reload the GitHub CI model from GitHub configuration.
    /// Creates a new model if config is now available, or clears it if config was removed.
    private func reloadGitHubModel() {
        if let githubConfig = GitHubConfiguration.loadConfig() {
            githubModel = GitHubCIModel(
                projectRoot: projectDirectory,
                config: githubConfig,
                cliClient: cliClient
            )
        } else {
            githubModel = nil
        }
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
