import Foundation
import DockerCLISDK

/// Client for managing local DynamoDB via Docker
public struct DynamoDBClient: Sendable {
    private let dockerClient: DockerClient
    private let config: DynamoDBLocalConfig
    private let dataDirectory: String

    public init(dockerClient: DockerClient, config: DynamoDBLocalConfig, dataDirectory: String) {
        self.dockerClient = dockerClient
        self.config = config
        self.dataDirectory = dataDirectory
    }

    /// Get endpoint URL for DynamoDB Local
    public var endpoint: String {
        "http://localhost:\(config.port)"
    }

    /// Get connection information
    public var connectionInfo: DynamoDBLocalConnectionInfo {
        DynamoDBLocalConnectionInfo(
            endpoint: endpoint,
            port: config.port,
            internalPort: config.internalPort,
            containerName: config.containerName,
            region: config.region
        )
    }

    /// Start DynamoDB Local
    public func start() async throws {
        print("\n🗄️  Starting DynamoDB Local (\(config.containerName))...")

        // Check if container already exists
        let containerExists = try await dockerClient.containerExists(name: config.containerName)

        if containerExists {
            // Check if it's already running
            let isRunning = try await dockerClient.containerIsRunning(name: config.containerName)
            if isRunning {
                print("✅ DynamoDB Local already running")
                return
            }

            // Container exists but is stopped - start it
            print("→ Starting existing DynamoDB Local container...")
            try await dockerClient.start(container: config.containerName)
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
        if !FileManager.default.fileExists(atPath: dataDirectory) {
            print("→ Creating DynamoDB Local data directory at \(dataDirectory)...")
            try FileManager.default.createDirectory(
                atPath: dataDirectory,
                withIntermediateDirectories: true
            )
        }

        // Run DynamoDB Local container
        // DynamoDB Local listens on port 8000 internally
        // Note: We don't set a custom user because DynamoDB Local runs as a specific user
        // and setting a different user causes permission issues with the jar file
        print("→ Creating DynamoDB Local container...")
        var runOptions = DockerClient.RunOptions()
        runOptions.detached = true
        runOptions.ports = [(config.port, config.internalPort)]
        runOptions.name = config.containerName
        runOptions.workingDirectory = "/home/dynamodblocal"
        runOptions.volumes = [(dataDirectory, "/home/dynamodblocal/data")]

        try await dockerClient.run(
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

/// Connection information for DynamoDB Local
public struct DynamoDBLocalConnectionInfo: Sendable {
    public let endpoint: String
    public let port: Int
    public let internalPort: Int
    public let containerName: String
    public let region: String
}

/// Configuration for DynamoDB Local service per deployment mode
public enum DynamoDBLocalConfig: Sendable {
    case xcode
    case linux

    public var containerName: String {
        switch self {
        case .xcode: return "dynamodb-xcode"
        case .linux: return "dynamodb-linux"
        }
    }

    public var imageName: String { "amazon/dynamodb-local:latest" }

    public var port: Int {
        switch self {
        case .xcode: return 8000
        case .linux: return 8001
        }
    }

    public var region: String { "us-east-1" }

    // DynamoDB Local always listens on port 8000 internally
    public var internalPort: Int { 8000 }
}
