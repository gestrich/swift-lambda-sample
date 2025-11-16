import Foundation

/// Service for managing local development environment (Docker services, testing)
public actor LocalDevelopmentService {
    private let dockerService: DockerService
    private let cliService: CLIService
    private let minioImageName = "quay.io/minio/minio"
    private let minioContainerName = "minio_lambda"
    private let postgresImageName = "postgres_lambda"
    private let postgresContainerName = "postgres_lambda"
    private let networkName = "lambda-local"
    private let workingDirectory: String?

    public init(workingDirectory: String? = nil) {
        self.dockerService = DockerService()
        self.cliService = CLIService.shared
        self.workingDirectory = workingDirectory
    }

    // MARK: - Service Management

    /// Start all services (PostgreSQL + MinIO)
    public func startAllServices() async throws {
        try await stopAllServices()
        try await startS3()
        try await startDatabase()
    }

    /// Stop all services
    public func stopAllServices() async throws {
        try await stopS3()
        try await stopDatabase()
    }

    /// Start MinIO S3 service
    public func startS3() async throws {
        print("\n🗄️  Starting MinIO S3...")

        // Create data directory
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let minioDataPath = "\(homeDir)/minio/data/org.gestrich.sandbox"
        try FileManager.default.createDirectory(
            atPath: minioDataPath,
            withIntermediateDirectories: true,
            attributes: nil
        )

        // Get user ID and group ID
        let userId = try await dockerService.getCurrentUserId()
        let groupId = try await dockerService.getCurrentGroupId()

        // Run MinIO container
        var options = DockerService.RunOptions()
        options.detached = true
        options.ports = [(9000, 9000), (9001, 9001)]
        options.user = "\(userId):\(groupId)"
        options.name = minioContainerName
        options.environment = [
            "MINIO_ROOT_USER": "admin",
            "MINIO_ROOT_PASSWORD": "password"
        ]
        options.volumes = [("\(homeDir)/minio/data", "/data")]

        try await dockerService.run(
            image: minioImageName,
            command: ["server", "/data", "--console-address", ":9001"],
            options: options
        )

        print("✅ MinIO started successfully")
        print("   - S3 endpoint: http://localhost:9000")
        print("   - Console: http://localhost:9001")
        print("   - Credentials: admin/password")
    }

    /// Stop MinIO S3 service
    public func stopS3() async throws {
        try await stopContainer(named: minioContainerName)
    }

    /// Start PostgreSQL database
    public func startDatabase() async throws {
        print("\n🗄️  Starting PostgreSQL...")

        // Build PostgreSQL image
        print("→ Building PostgreSQL Docker image...")
        var buildOptions = DockerService.BuildOptions()
        buildOptions.tag = postgresImageName
        buildOptions.file = "PostgresDockerfile"
        buildOptions.buildArgs = [
            "EXPOSE_PORT": "5432",
            "USERNAME": "docker",
            "PASSWORD": "docker"
        ]
        buildOptions.workingDirectory = workingDirectory

        try await dockerService.build(context: ".", options: buildOptions)

        // Run PostgreSQL container
        print("→ Starting PostgreSQL container...")
        var runOptions = DockerService.RunOptions()
        runOptions.detached = true
        runOptions.ports = [(5432, 5432)]
        runOptions.name = postgresContainerName

        try await dockerService.run(
            image: postgresImageName,
            options: runOptions
        )

        print("✅ PostgreSQL started successfully")
        print("   - Host: localhost:5432")
        print("   - Database: docker")
        print("   - Credentials: docker/docker")
    }

    /// Stop PostgreSQL database
    public func stopDatabase() async throws {
        try await stopContainer(named: postgresContainerName)
    }

    // MARK: - Lambda Container Testing

    /// Setup Docker network for Lambda container testing
    public func setupLambdaNetwork() async throws {
        print("\n🔧 Setting up Docker network for local Lambda testing...")

        // Create network if it doesn't exist
        if !(try await dockerService.networkExists(name: networkName)) {
            print("→ Creating Docker network: \(networkName)")
            try await dockerService.createNetwork(name: networkName)
        } else {
            print("✓ Network \(networkName) already exists")
        }

        // Connect PostgreSQL to network
        try await connectContainerToNetwork(container: postgresContainerName)

        // Connect MinIO to network
        try await connectContainerToNetwork(container: minioContainerName)

        print("\n✅ Network setup complete!")
        print("\nYou can now run the Lambda container with:")
        print("  swift run SwiftDeploy local run-container")
    }

    /// Run Lambda in interactive Linux container
    public func runLambdaContainer() async throws {
        print("\n🚀 Starting Lambda in Linux container...")
        print("")

        // Check if lambda directory exists
        guard FileManager.default.fileExists(atPath: "lambda") else {
            print("❌ Error: lambda directory not found!")
            print("Build the Lambda first with: ./build.sh SwiftLambda")
            throw CLIError.invalidWorkingDirectory("lambda directory not found")
        }

        // Ensure network is set up
        try await setupLambdaNetwork()

        print("Starting interactive container...")
        print("(Type 'exit' to leave the container)")
        print("")

        let currentDir = FileManager.default.currentDirectoryPath

        // Run interactive container
        var options = DockerService.RunOptions()
        options.interactive = true
        options.tty = true
        options.remove = true
        options.platform = "linux/amd64"
        options.network = networkName
        options.volumes = [("\(currentDir)/lambda", "/var/task")]
        options.ports = [(8080, 7000)]
        options.environment = [
            "POSTGRES_HOST": postgresContainerName,
            "POSTGRES_PORT": "5432",
            "POSTGRES_USER_NAME": "docker",
            "POSTGRES_DBNAME": "docker",
            "POSTGRES_PASSWORD": "docker",
            "S3_BUCKET_NAME": "org.gestrich.sandbox",
            "AWS_ENDPOINT_URL": "http://\(minioContainerName):9000",
            "AWS_ACCESS_KEY_ID": "admin",
            "AWS_SECRET_ACCESS_KEY": "password",
            "MOCK_AWS_CREDENTIALS": "true",
            "LOCAL_LAMBDA_SERVER_ENABLED": "true",
            "LOCAL_LAMBDA_HOST": "0.0.0.0"
        ]

        try await dockerService.run(
            image: "swift:6.2.0-amazonlinux2",
            command: ["bash", "-c", "cd /var/task && chmod +x bootstrap && echo '✅ Lambda ready! Run: ./bootstrap' && bash"],
            options: options
        )
    }

    /// Test local Lambda endpoints
    public func testLocalLambda(port: Int = 8080) async throws {
        let endpoint = "http://localhost:\(port)/invoke"

        print("\n🧪 Testing local Lambda on port \(port)...")
        print("")

        // Test S3 file endpoint
        print("→ Testing S3 file upload/download...")
        let s3Body = """
        {
          "resource": "/api/file",
          "path": "/api/file",
          "httpMethod": "POST",
          "headers": {},
          "multiValueHeaders": {},
          "requestContext": {
            "resourceId": "test",
            "apiId": "test",
            "resourcePath": "/api/file",
            "httpMethod": "POST",
            "requestId": "test",
            "accountId": "123456789012",
            "stage": "local",
            "identity": {"sourceIp": "127.0.0.1"},
            "path": "/api/file"
          },
          "body": null,
          "isBase64Encoded": false
        }
        """

        let s3Result = try await cliService.execute(
            command: "curl",
            arguments: [
                "-s",
                "-X", "POST",
                endpoint,
                "-H", "Content-Type: application/json",
                "-d", s3Body
            ],
            printCommand: false
        )

        if s3Result.stdout.contains("File uploaded and downloaded") {
            print("  ✅ S3 test passed")
        } else {
            print("  ❌ S3 test failed: \(s3Result.stdout)")
            throw CLIError.testFailed(message: "S3 endpoint test failed")
        }

        print("")

        // Test database initialization
        print("→ Testing database initialization...")
        let dbBody = """
        {
          "resource": "/api/database",
          "path": "/api/database",
          "httpMethod": "POST",
          "headers": {},
          "multiValueHeaders": {},
          "requestContext": {
            "resourceId": "test",
            "apiId": "test",
            "resourcePath": "/api/database",
            "httpMethod": "POST",
            "requestId": "test",
            "accountId": "123456789012",
            "stage": "local",
            "identity": {"sourceIp": "127.0.0.1"},
            "path": "/api/database"
          },
          "body": null,
          "isBase64Encoded": false
        }
        """

        let dbResult = try await cliService.execute(
            command: "curl",
            arguments: [
                "-s",
                "-X", "POST",
                endpoint,
                "-H", "Content-Type: application/json",
                "-d", dbBody
            ],
            printCommand: false
        )

        if dbResult.stdout.contains("Database Initialized") {
            print("  ✅ Database test passed")
        } else {
            print("  ❌ Database test failed: \(dbResult.stdout)")
            throw CLIError.testFailed(message: "Database endpoint test failed")
        }

        print("")
        print("✅ All local Lambda tests passed!")
    }

    // MARK: - Configuration

    /// Copy config file to home directory
    /// - Parameter sourcePath: Optional path to the config file. If nil, uses "swiftLambdaDemo.json" in current directory
    public func copyConfig(sourcePath: String? = nil) async throws {
        print("\n📝 Copying config file...")

        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let configDir = "\(homeDir)/.swiftSampleDemo"
        let configPath = "\(configDir)/swiftLambdaDemo.json"

        // Determine source config path
        let sourceConfig: String
        if let providedPath = sourcePath {
            sourceConfig = providedPath
        } else {
            // Default to current directory
            sourceConfig = "swiftLambdaDemo.json"
        }

        // Check if source file exists
        guard FileManager.default.fileExists(atPath: sourceConfig) else {
            throw CLIError.invalidWorkingDirectory("Config file not found at: \(sourceConfig)")
        }

        // Create directory
        try FileManager.default.createDirectory(
            atPath: configDir,
            withIntermediateDirectories: true,
            attributes: nil
        )

        // Copy file
        if FileManager.default.fileExists(atPath: configPath) {
            try FileManager.default.removeItem(atPath: configPath)
        }

        try FileManager.default.copyItem(atPath: sourceConfig, toPath: configPath)

        print("✅ Config copied to \(configPath)")
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

    /// Connect a container to the Lambda network
    private func connectContainerToNetwork(container: String) async throws {
        // Check if container is connected
        let isConnected = try await dockerService.isConnectedToNetwork(
            container: container,
            network: networkName
        )

        if !isConnected {
            // Check if container is running
            let isRunning = try await dockerService.containerIsRunning(name: container)

            if isRunning {
                print("→ Connecting \(container) to \(networkName)")
                try await dockerService.connectToNetwork(container: container, network: networkName)
            } else {
                print("⚠️  Warning: \(container) is not running. Start it with: swift run SwiftDeploy local start-\(container == postgresContainerName ? "database" : "s3")")
            }
        } else {
            print("✓ \(container) already connected")
        }
    }
}
