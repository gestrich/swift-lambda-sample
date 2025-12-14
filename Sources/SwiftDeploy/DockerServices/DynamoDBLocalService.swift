import Foundation
import LocalStorageService

/// Service for managing local DynamoDB via Docker
public actor DynamoDBLocalService {
    private let dockerService: DockerService
    private let config: DynamoDBLocalConfig
    private let storageService: LocalStorageService

    public init(dockerService: DockerService, config: DynamoDBLocalConfig, storageService: LocalStorageService) {
        self.dockerService = dockerService
        self.config = config
        self.storageService = storageService
    }

    /// Get endpoint URL for DynamoDB Local
    nonisolated public var endpoint: String {
        "http://localhost:\(config.port)"
    }

    /// Get connection information
    nonisolated public var connectionInfo: DynamoDBLocalConnectionInfo {
        DynamoDBLocalConnectionInfo(
            endpoint: endpoint,
            port: config.port,
            containerName: config.containerName,
            region: config.region
        )
    }

    /// Start DynamoDB Local
    public func start() async throws {
        print("\n🗄️  Starting DynamoDB Local (\(config.containerName))...")

        // Check if container already exists
        let containerExists = try await dockerService.containerExists(name: config.containerName)

        if containerExists {
            // Check if it's already running
            let isRunning = try await dockerService.containerIsRunning(name: config.containerName)
            if isRunning {
                print("✅ DynamoDB Local already running")
                return
            }

            // Container exists but is stopped - start it
            print("→ Starting existing DynamoDB Local container...")
            try await dockerService.start(container: config.containerName)
        } else {
            // Container doesn't exist - create and run it
            try await createAndRunContainer()
        }

        print("✅ DynamoDB Local started successfully")
        print("   - Endpoint: \(endpoint)")
        print("   - Region: \(config.region)")
    }

    /// Create and run a new DynamoDB Local container
    private func createAndRunContainer() async throws {
        // Create data directory if it doesn't exist
        let dataDir = storageService.dataDirectory(for: config.storageKeyType)
        if !FileManager.default.fileExists(atPath: dataDir) {
            print("→ Creating DynamoDB Local data directory at \(dataDir)...")
            try storageService.ensureDataDirectoryExists(for: config.storageKeyType)
        }

        // Run DynamoDB Local container
        // DynamoDB Local listens on port 8000 internally
        // Note: We don't set a custom user because DynamoDB Local runs as a specific user
        // and setting a different user causes permission issues with the jar file
        print("→ Creating DynamoDB Local container...")
        var runOptions = DockerService.RunOptions()
        runOptions.detached = true
        runOptions.ports = [(config.port, config.internalPort)]
        runOptions.name = config.containerName
        runOptions.workingDirectory = "/home/dynamodblocal"
        runOptions.volumes = [(dataDir, "/home/dynamodblocal/data")]

        try await dockerService.run(
            image: config.imageName,
            command: ["-jar", "DynamoDBLocal.jar", "-sharedDb", "-dbPath", "./data"],
            options: runOptions
        )
    }

    /// Stop DynamoDB Local
    public func stop() async throws {
        try await stopContainer(named: config.containerName)
    }

    /// Check if DynamoDB Local container is running
    public func isRunning() async throws -> Bool {
        return try await dockerService.containerIsRunning(name: config.containerName)
    }

    // MARK: - Private Helpers

    /// Stop a Docker container by name
    private func stopContainer(named containerName: String) async throws {
        // Check if container exists
        let exists = try await dockerService.containerExists(name: containerName)

        if exists {
            print("→ Stopping and removing \(containerName)...")
            try await dockerService.stop(container: containerName)
            try await dockerService.remove(container: containerName)
            print("✅ \(containerName) stopped and removed")
        }
    }
}

// MARK: - Supporting Types

/// Connection information for DynamoDB Local
public struct DynamoDBLocalConnectionInfo: Sendable {
    public let endpoint: String
    public let port: Int
    public let containerName: String
    public let region: String
}

/// Configuration for DynamoDB Local service per deployment mode
public enum DynamoDBLocalConfig: Sendable {
    case xcode
    case linux

    var containerName: String {
        switch self {
        case .xcode: return "dynamodb-xcode"
        case .linux: return "dynamodb-linux"
        }
    }

    var imageName: String { "amazon/dynamodb-local:latest" }

    var port: Int {
        switch self {
        case .xcode: return 8000
        case .linux: return 8001
        }
    }

    var storageKeyType: any StoragePathKey.Type {
        switch self {
        case .xcode: return DynamoDBLocalXcodeStorageKey.self
        case .linux: return DynamoDBLocalLinuxStorageKey.self
        }
    }

    var region: String { "us-east-1" }

    // DynamoDB Local always listens on port 8000 internally
    var internalPort: Int { 8000 }
}

// MARK: - Storage Keys

/// Storage key for DynamoDB Local Xcode workflow data
public struct DynamoDBLocalXcodeStorageKey: StoragePathKey {
    public static let pathComponent = "dynamodb/xcode-data"
}

/// Storage key for DynamoDB Local Linux workflow data
public struct DynamoDBLocalLinuxStorageKey: StoragePathKey {
    public static let pathComponent = "dynamodb/linux-data"
}
