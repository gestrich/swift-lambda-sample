import Foundation

/// Service for managing local PostgreSQL database via Docker
public actor PostgreSQLService {
    private let dockerService: DockerService
    private let workingDirectory: String

    // Configuration
    private let imageName = "postgres-lambda"
    private let containerName = "postgres-lambda"
    private let port = 5432
    private let username = "docker"
    private let password = "docker"
    private let database = "docker"

    public init(dockerService: DockerService, workingDirectory: String) {
        self.dockerService = dockerService
        self.workingDirectory = workingDirectory
    }

    /// Get connection information
    nonisolated public var connectionInfo: PostgreSQLConnectionInfo {
        PostgreSQLConnectionInfo(
            host: containerName,
            port: port,
            username: username,
            password: password,
            database: database,
            containerName: containerName
        )
    }

    /// Start PostgreSQL database
    public func start() async throws {
        print("\n🗄️  Starting PostgreSQL...")

        // Build PostgreSQL image
        print("→ Building PostgreSQL Docker image...")
        var buildOptions = DockerService.BuildOptions()
        buildOptions.tag = imageName
        buildOptions.file = "PostgresDockerfile"
        buildOptions.buildArgs = [
            "EXPOSE_PORT": "\(port)",
            "USERNAME": username,
            "PASSWORD": password
        ]
        buildOptions.workingDirectory = workingDirectory

        try await dockerService.build(context: ".", options: buildOptions)

        // Run PostgreSQL container
        print("→ Starting PostgreSQL container...")
        var runOptions = DockerService.RunOptions()
        runOptions.detached = true
        runOptions.ports = [(port, port)]
        runOptions.name = containerName

        try await dockerService.run(
            image: imageName,
            options: runOptions
        )

        print("✅ PostgreSQL started successfully")
        print("   - Host: localhost:\(port)")
        print("   - Database: \(database)")
        print("   - Credentials: \(username)/\(password)")
    }

    /// Stop PostgreSQL database
    public func stop() async throws {
        try await stopContainer(named: containerName)
    }

    /// Check if PostgreSQL container is running
    public func isRunning() async throws -> Bool {
        return try await dockerService.containerIsRunning(name: containerName)
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
    public let port: Int
    public let username: String
    public let password: String
    public let database: String
    public let containerName: String
}
