import Foundation

/// Configuration for PostgreSQL service per deployment mode
public enum PostgreSQLConfig: Sendable {
    case xcode
    case linux

    var containerName: String {
        switch self {
        case .xcode: return "postgres-xcode"
        case .linux: return "postgres-linux"
        }
    }

    var imageName: String {
        switch self {
        case .xcode: return "postgres-xcode"
        case .linux: return "postgres-linux"
        }
    }

    var port: Int {
        switch self {
        case .xcode: return 5432
        case .linux: return 5433
        }
    }

    // Use same database name for both modes - data isolation comes from separate containers
    var database: String { "docker" }

    var username: String { "docker" }
    var password: String { "docker" }

    // PostgreSQL always listens on port 5432 internally
    var internalPort: Int { 5432 }
}

/// Service for managing local PostgreSQL database via Docker
public actor PostgreSQLService {
    private let dockerService: DockerService
    private let workingDirectory: String
    private let config: PostgreSQLConfig

    public init(dockerService: DockerService, workingDirectory: String, config: PostgreSQLConfig) {
        self.dockerService = dockerService
        self.workingDirectory = workingDirectory
        self.config = config
    }

    /// Get connection information
    nonisolated public var connectionInfo: PostgreSQLConnectionInfo {
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

        // Build PostgreSQL image
        print("→ Building PostgreSQL Docker image...")
        var buildOptions = DockerService.BuildOptions()
        buildOptions.tag = config.imageName
        buildOptions.file = "PostgresDockerfile"
        buildOptions.buildArgs = [
            "EXPOSE_PORT": "\(config.port)",
            "USERNAME": config.username,
            "PASSWORD": config.password
        ]
        buildOptions.workingDirectory = workingDirectory

        try await dockerService.build(context: ".", options: buildOptions)

        // Run PostgreSQL container
        // Map external port to internal port (PostgreSQL always listens on 5432 internally)
        print("→ Starting PostgreSQL container...")
        var runOptions = DockerService.RunOptions()
        runOptions.detached = true
        runOptions.ports = [(config.port, config.internalPort)]
        runOptions.name = config.containerName

        try await dockerService.run(
            image: config.imageName,
            options: runOptions
        )

        print("✅ PostgreSQL started successfully")
        print("   - Host: localhost:\(config.port)")
        print("   - Database: \(config.database)")
        print("   - Credentials: \(config.username)/\(config.password)")
    }

    /// Stop PostgreSQL database
    public func stop() async throws {
        try await stopContainer(named: config.containerName)
    }

    /// Check if PostgreSQL container is running
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
