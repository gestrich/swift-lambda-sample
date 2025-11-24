import Foundation

/// Service for managing local MinIO S3 service via Docker
public actor MinIOService {
    private let dockerService: DockerService
    private let networkName: String

    // Configuration
    private let imageName = "quay.io/minio/minio"
    private let containerName = "minio-lambda"  // Use hyphen not underscore for valid HTTP hostname
    private let s3Port = 9000
    private let consolePort = 9001
    private let rootUser = "admin"
    private let rootPassword = "password"
    private let region = "us-east-1"
    private let defaultBucketName = "org.gestrich.sandbox"

    // Data directory
    private let dataDirectory: String

    public init(dockerService: DockerService, networkName: String) {
        self.dockerService = dockerService
        self.networkName = networkName
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        self.dataDirectory = "\(homeDir)/minio/data"
    }

    /// Get S3 endpoint URL
    nonisolated public var endpoint: String {
        "http://localhost:\(s3Port)"
    }

    /// Get MinIO console URL
    nonisolated public var consoleURL: String {
        "http://localhost:\(consolePort)"
    }

    /// Get MinIO credentials
    nonisolated public var credentials: MinIOCredentials {
        MinIOCredentials(
            accessKeyId: rootUser,
            secretAccessKey: rootPassword,
            region: region
        )
    }

    /// Get container name for networking
    nonisolated public var minioContainerName: String {
        containerName
    }

    /// Get default bucket name
    nonisolated public var bucketName: String {
        defaultBucketName
    }

    /// Start MinIO S3 service
    public func start() async throws {
        print("\n🗄️  Starting MinIO S3...")

        // Create data directory
        let minioRootPath = "\(FileManager.default.homeDirectoryForCurrentUser.path)/minio"
        let minioDataPath = "\(minioRootPath)/data"

        // Create MinIO data directory if it doesn't exist
        // Don't remove existing data - let MinIO reuse it
        if !FileManager.default.fileExists(atPath: minioDataPath) {
            print("→ Creating MinIO data directory...")
            try FileManager.default.createDirectory(
                atPath: minioDataPath,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }

        // Get user ID and group ID
        let userId = try await dockerService.getCurrentUserId()
        let groupId = try await dockerService.getCurrentGroupId()

        // Run MinIO container
        var options = DockerService.RunOptions()
        options.detached = true
        options.ports = [(s3Port, s3Port), (consolePort, consolePort)]
        options.user = "\(userId):\(groupId)"
        options.name = containerName
        options.environment = [
            "MINIO_ROOT_USER": rootUser,
            "MINIO_ROOT_PASSWORD": rootPassword,
            "MINIO_REGION_NAME": region  // Modern MinIO uses MINIO_REGION_NAME
        ]
        options.volumes = [(minioDataPath, "/data")]

        try await dockerService.run(
            image: imageName,
            command: ["server", "/data", "--console-address", ":\(consolePort)"],
            options: options
        )

        print("✅ MinIO started successfully")
        print("   - S3 endpoint: \(endpoint)")
        print("   - Console: \(consoleURL)")
        print("   - Credentials: \(rootUser)/\(rootPassword)")
    }

    /// Create S3 bucket in MinIO
    public func createBucket(bucketName: String? = nil) async throws {
        let bucket = bucketName ?? defaultBucketName
        print("📦 Creating S3 bucket in MinIO...")

        // Run AWS CLI in a container to create the bucket
        var options = DockerService.RunOptions()
        options.remove = true
        options.network = networkName
        options.environment = [
            "AWS_ACCESS_KEY_ID": rootUser,
            "AWS_SECRET_ACCESS_KEY": rootPassword,
            "AWS_REGION": region,
            "AWS_DEFAULT_REGION": region
        ]

        do {
            try await dockerService.run(
                image: "amazon/aws-cli",
                command: ["--endpoint-url", "http://\(containerName):\(s3Port)", "s3", "mb", "s3://\(bucket)"],
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
        try await stopContainer(named: containerName)
    }

    /// Check if MinIO container is running
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

/// Credentials for MinIO S3 service
public struct MinIOCredentials: Sendable {
    public let accessKeyId: String
    public let secretAccessKey: String
    public let region: String
}
