import Foundation

/// Client for managing local PostgreSQL database via Docker
public struct PostgreSQLClient: Sendable {
    private let dockerClient: DockerClient
    private let config: PostgreSQLConfig
    private let dataDirectory: String

    public init(dockerClient: DockerClient, config: PostgreSQLConfig, dataDirectory: String) {
        self.dockerClient = dockerClient
        self.config = config
        self.dataDirectory = dataDirectory
    }

    /// Get connection information
    public var connectionInfo: PostgreSQLConnectionInfo {
        PostgreSQLConnectionInfo(
            host: config.containerName,
            port: config.port,
            internalPort: config.internalPort,
            username: config.username,
            password: config.password,
            database: config.database,
            containerName: config.containerName
        )
    }

    /// Start PostgreSQL database
    public func start() async throws {
        print("\n🗄️  Starting PostgreSQL (\(config.containerName))...")

        // Check if container already exists
        let containerExists = try await dockerClient.containerExists(name: config.containerName)

        if containerExists {
            // Check if it's already running
            let isRunning = try await dockerClient.containerIsRunning(name: config.containerName)
            if isRunning {
                print("✅ PostgreSQL already running")
                return
            }

            // Container exists but is stopped - start it
            print("→ Starting existing PostgreSQL container...")
            try await dockerClient.start(container: config.containerName)
        } else {
            // Container doesn't exist - create and run it
            try await createAndRunContainer()
        }

        print("✅ PostgreSQL started successfully")
        print("   - Host: localhost:\(config.port)")
        print("   - Database: \(config.database)")
        print("   - Credentials: \(config.username)/\(config.password)")
    }

    /// Create and run a new PostgreSQL container
    private func createAndRunContainer() async throws {
        // Create data directory if it doesn't exist
        if !FileManager.default.fileExists(atPath: dataDirectory) {
            print("→ Creating PostgreSQL data directory at \(dataDirectory)...")
            try FileManager.default.createDirectory(
                atPath: dataDirectory,
                withIntermediateDirectories: true
            )
        }

        // Run PostgreSQL container with host directory for data persistence
        // The official postgres image handles initialization automatically
        print("→ Creating PostgreSQL container...")
        var runOptions = DockerClient.RunOptions()
        runOptions.detached = true
        runOptions.ports = [(config.port, config.internalPort)]
        runOptions.name = config.containerName
        runOptions.volumes = [(dataDirectory, "/var/lib/postgresql/data")]
        runOptions.environment = [
            "POSTGRES_USER": config.username,
            "POSTGRES_PASSWORD": config.password,
            "POSTGRES_DB": config.database
        ]

        try await dockerClient.run(
            image: config.imageName,
            options: runOptions
        )
    }

    /// Stop PostgreSQL database
    public func stop() async throws {
        try await stopContainer(named: config.containerName)
    }

    /// Check if PostgreSQL container is running
    public func isRunning() async throws -> Bool {
        return try await dockerClient.containerIsRunning(name: config.containerName)
    }

    // MARK: - Private Helpers

    /// Stop a Docker container by name
    private func stopContainer(named containerName: String) async throws {
        // Check if container exists
        let exists = try await dockerClient.containerExists(name: containerName)

        if exists {
            print("→ Stopping and removing \(containerName)...")
            try await dockerClient.stop(container: containerName)
            try await dockerClient.remove(container: containerName)
            print("✅ \(containerName) stopped and removed")
        }
    }
}

// MARK: - Supporting Types

/// Connection information for PostgreSQL
public struct PostgreSQLConnectionInfo: Sendable {
    public let host: String
    public let port: Int              // External/host port
    public let internalPort: Int      // Internal container port (always 5432)
    public let username: String
    public let password: String
    public let database: String
    public let containerName: String
}

/// Configuration for PostgreSQL service per deployment mode
public enum PostgreSQLConfig: Sendable {
    case xcode
    case linux

    public var containerName: String {
        switch self {
        case .xcode: return "postgres-xcode"
        case .linux: return "postgres-linux"
        }
    }

    public var imageName: String { "postgres:11" }

    public var port: Int {
        switch self {
        case .xcode: return 5432
        case .linux: return 5433
        }
    }

    // Use same database name for both modes - data isolation comes from separate containers
    public var database: String { "docker" }

    public var username: String { "docker" }
    public var password: String { "docker" }

    // PostgreSQL always listens on port 5432 internally
    public var internalPort: Int { 5432 }
}
