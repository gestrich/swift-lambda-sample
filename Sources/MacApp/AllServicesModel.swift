import Client
import Foundation
import SwiftDeploy

/// Connection mode for the API - simple enum holding service references
@MainActor
enum ConnectionMode {
    case remote(RemoteService)
    case localXcode(XcodeLocalService)
    case localLinux(LinuxLocalService)

    /// Persistence key for saving/restoring mode selection
    var persistenceKey: String {
        switch self {
        case .remote: return RemoteService.persistenceKey
        case .localXcode: return XcodeLocalService.persistenceKey
        case .localLinux: return LinuxLocalService.persistenceKey
        }
    }
    
    var service: LambdaService {
        switch self {
        case .localXcode(let service): return service
        case .localLinux(let service): return service
        case .remote(let service): return service
        }
    }
}

/// Top-level model that creates and holds all services.
/// Manages mode selection and provides access to individual services.
@MainActor
@Observable
class AllServicesModel {
    // MARK: - Services (Eager Initialization)

    /// All services are created at app startup. The active mode determines which is in use.
    let remoteService: RemoteService
    let xcodeLocalService: XcodeLocalService
    let linuxLocalService: LinuxLocalService

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
        let remote = RemoteService(workingDirectory: projectDirectory)
        let xcode = XcodeLocalService(workingDirectory: projectDirectory)
        let linux = LinuxLocalService(workingDirectory: projectDirectory)

        self.remoteService = remote
        self.xcodeLocalService = xcode
        self.linuxLocalService = linux

        // Create observable models for local services
        self.xcodeLocalModel = LocalServicesModel(service: xcode)
        self.linuxLocalModel = LocalServicesModel(service: linux)

        // Load mode from UserDefaults and use pre-created services
        let savedKey = UserDefaults.standard.string(forKey: modeKey) ?? "remote"
        let initialMode: ConnectionMode
        switch savedKey {
        case XcodeLocalService.persistenceKey:
            initialMode = .localXcode(xcode)
        case LinuxLocalService.persistenceKey:
            initialMode = .localLinux(linux)
        default:
            initialMode = .remote(remote)
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
        } else {
            print("🔄 No localModel (remote mode), calling refreshStatus")
            remoteService.refreshStatus()
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
        return mode.service.isConfigured
    }

    /// Refresh status for the current service
    func refreshStatus() {
        mode.service.refreshStatus()
    }

    // MARK: - Persistence

    func save() {
        UserDefaults.standard.set(mode.persistenceKey, forKey: modeKey)
    }
}
