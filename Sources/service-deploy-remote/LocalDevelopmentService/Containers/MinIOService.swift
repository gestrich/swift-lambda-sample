import Foundation
import sdk_cli_docker
import service_storage

/// Service for managing local MinIO S3 service via Docker
public actor MinIOService {
    private let dockerClient: DockerClient
    private let networkName: String
    private let config: MinIOConfig
    private let storageService: LocalStorageService

    public init(dockerClient: DockerClient, networkName: String, config: MinIOConfig, storageService: LocalStorageService) {
        self.dockerClient = dockerClient
        self.networkName = networkName
        self.config = config
        self.storageService = storageService
    }

    /// Get S3 endpoint URL
    nonisolated public var endpoint: String {
        "http://localhost:\(config.s3Port)"
    }

    /// Get MinIO console URL
    nonisolated public var consoleURL: String {
        "http://localhost:\(config.consolePort)"
    }

    /// Get MinIO credentials
    nonisolated public var credentials: MinIOCredentials {
        MinIOCredentials(
            accessKeyId: config.rootUser,
            secretAccessKey: config.rootPassword,
            region: config.region
        )
    }

    /// Get container name for networking
    nonisolated public var minioContainerName: String {
        config.containerName
    }

    /// Get default bucket name
    nonisolated public var bucketName: String {
        config.bucketName
    }

    /// Get S3 port for host networking (external port)
    nonisolated public var s3Port: Int {
        config.s3Port
    }

    /// Get S3 port for container-to-container networking (internal port)
    /// MinIO always listens on port 9000 internally
    nonisolated public var internalS3Port: Int {
        9000
    }

    /// Start MinIO S3 service
    public func start() async throws {
        print("\n🗄️  Starting MinIO S3 (\(config.containerName))...")

        // Check if container already exists
        let containerExists = try await dockerClient.containerExists(name: config.containerName)

        if containerExists {
            // Check if it's already running
            let isRunning = try await dockerClient.containerIsRunning(name: config.containerName)
            if isRunning {
                print("✅ MinIO already running")
                return
            }

            // Container exists but is stopped - start it
            print("→ Starting existing MinIO container...")
            try await dockerClient.start(container: config.containerName)
        } else {
            // Container doesn't exist - create and run it
            try await createAndRunContainer()
        }

        print("✅ MinIO started successfully")
        print("   - S3 endpoint: \(endpoint)")
        print("   - Console: \(consoleURL)")
        print("   - Credentials: \(config.rootUser)/\(config.rootPassword)")
    }

    /// Create and run a new MinIO container
    private func createAndRunContainer() async throws {
        // Create MinIO data directory if it doesn't exist
        // Don't remove existing data - let MinIO reuse it
        let dataDir = storageService.dataDirectory(for: config.storageKeyType)
        if !FileManager.default.fileExists(atPath: dataDir) {
            print("→ Creating MinIO data directory at \(dataDir)...")
            try storageService.ensureDataDirectoryExists(for: config.storageKeyType)
        }

        // Get user ID and group ID
        let userId = try await dockerClient.getCurrentUserId()
        let groupId = try await dockerClient.getCurrentGroupId()

        // Run MinIO container
        // MinIO S3 API always listens on port 9000 internally
        // Console port is configurable via --console-address
        let internalS3Port = 9000
        let internalConsolePort = 9001

        var options = DockerClient.RunOptions()
        options.detached = true
        // Map external ports to internal ports (MinIO always uses 9000 for S3, 9001 for console internally)
        options.ports = [(config.s3Port, internalS3Port), (config.consolePort, internalConsolePort)]
        options.user = "\(userId):\(groupId)"
        options.name = config.containerName
        options.environment = [
            "MINIO_ROOT_USER": config.rootUser,
            "MINIO_ROOT_PASSWORD": config.rootPassword,
            "MINIO_REGION_NAME": config.region  // Modern MinIO uses MINIO_REGION_NAME
        ]
        options.volumes = [(dataDir, "/data")]

        try await dockerClient.run(
            image: config.imageName,
            command: ["server", "/data", "--console-address", ":\(internalConsolePort)"],
            options: options
        )
    }

    /// Create S3 bucket in MinIO
    public func createBucket(bucketName: String? = nil) async throws {
        let bucket = bucketName ?? config.bucketName
        print("📦 Creating S3 bucket in MinIO...")

        // Run AWS CLI in a container to create the bucket
        // Use internal port (9000) since we're connecting container-to-container via Docker network
        var options = DockerClient.RunOptions()
        options.remove = true
        options.network = networkName
        options.environment = [
            "AWS_ACCESS_KEY_ID": config.rootUser,
            "AWS_SECRET_ACCESS_KEY": config.rootPassword,
            "AWS_REGION": config.region,
            "AWS_DEFAULT_REGION": config.region
        ]

        do {
            try await dockerClient.run(
                image: "amazon/aws-cli",
                command: ["--endpoint-url", "http://\(config.containerName):\(internalS3Port)", "s3", "mb", "s3://\(bucket)"],
                options: options
            )
            print("  ✅ S3 bucket '\(bucket)' created")
        } catch {
            // Bucket might already exist, which is fine
            print("  ℹ️  Bucket might already exist (this is OK)")
        }
    }

    /// Stop MinIO S3 service
    public func stop() async throws {
        try await stopContainer(named: config.containerName)
    }

    /// Check if MinIO container is running
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

/// Credentials for MinIO S3 service
public struct MinIOCredentials: Sendable {
    public let accessKeyId: String
    public let secretAccessKey: String
    public let region: String
}

/// Configuration for MinIO service per deployment mode
public enum MinIOConfig: Sendable {
    case xcode
    case linux

    var containerName: String {
        switch self {
        case .xcode: return "minio-xcode"
        case .linux: return "minio-linux"
        }
    }

    var s3Port: Int {
        switch self {
        case .xcode: return 9000
        case .linux: return 9002
        }
    }

    var consolePort: Int {
        switch self {
        case .xcode: return 9001
        case .linux: return 9003
        }
    }

    var storageKeyType: any StoragePathKey.Type {
        switch self {
        case .xcode: return MinIOXcodeStorageKey.self
        case .linux: return MinIOLinuxStorageKey.self
        }
    }

    // Use same bucket name for both modes - data isolation comes from separate containers/data directories
    var bucketName: String { "org.gestrich.sandbox" }

    var imageName: String { "quay.io/minio/minio" }
    var rootUser: String { "admin" }
    var rootPassword: String { "password" }
    var region: String { "us-east-1" }
}

// MARK: - Storage Keys

/// Storage key for MinIO Xcode workflow data
public struct MinIOXcodeStorageKey: StoragePathKey {
    public static let pathComponent = "minio/xcode-data"
}

/// Storage key for MinIO Linux workflow data
public struct MinIOLinuxStorageKey: StoragePathKey {
    public static let pathComponent = "minio/linux-data"
}
