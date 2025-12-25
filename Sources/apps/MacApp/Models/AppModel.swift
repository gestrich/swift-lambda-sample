import ClientService
import DeployCoreService
import DeployRemoteFeature
import Foundation
import GitHubSDK
import StorageService

/// Top-level model that creates and holds all services.
/// Manages mode selection and provides access to individual services.
@MainActor
@Observable
class AppModel {
    // MARK: - Models

    private(set) var dependencyStatusModel: DependencyStatusModel
    private(set) var githubModel: GitHubCIModel?
    private(set) var linuxLocalService: DeployLinuxModel
    private(set) var remoteModel: DeployRemoteModel?
    private(set) var xcodeLocalService: DeployXcodeModel

    /// Error from failed remote service initialization (nil if service was created successfully)
    private(set) var remoteServiceError: Error?

    private let projectDirectory: String

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
        self.projectDirectory = projectDirectory

        // Create remote service - may fail if AWS config is missing
        var remote: DeployRemoteModel?
        var remoteError: Error?
        do {
            remote = try DeployRemoteModel(projectRoot: projectDirectory)
        } catch {
            remoteError = error
        }

        // Create GitHub CI model - may fail if config is missing
        var github: GitHubCIModel?
        do {
            github = try GitHubCIModel(projectRoot: projectDirectory)
        } catch {
            // Optional - config missing is fine
        }

        let xcode = DeployXcodeModel(workingDirectory: projectDirectory)
        let linux = DeployLinuxModel(workingDirectory: projectDirectory)

        self.remoteModel = remote
        self.remoteServiceError = remoteError
        self.githubModel = github
        self.xcodeLocalService = xcode
        self.linuxLocalService = linux
        self.dependencyStatusModel = DependencyStatusModel(workingDirectory: projectDirectory)

        // Load mode from UserDefaults
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
            initialMode = .localXcode(xcode)
        }
        self.mode = initialMode
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
        save()
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
            remoteModel = try DeployRemoteModel(projectRoot: projectDirectory)
            remoteServiceError = nil
        } catch {
            remoteModel = nil
            remoteServiceError = error
        }
    }

    /// Reload the GitHub CI model from GitHub configuration.
    /// Creates a new model if config is now available, or clears it if config was removed.
    private func reloadGitHubModel() {
        do {
            githubModel = try GitHubCIModel(projectRoot: projectDirectory)
        } catch {
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
}
