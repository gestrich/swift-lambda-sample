import Foundation

/// Configuration for Lambda container
public struct LambdaContainerConfig: Sendable {
    public let containerName: String
    public let swiftImage: String
    public let hostPort: Int
    public let containerPort: Int
    public let networkName: String
    public let workingDirectory: String

    public init(
        containerName: String,
        swiftImage: String,
        hostPort: Int,
        containerPort: Int,
        networkName: String,
        workingDirectory: String
    ) {
        self.containerName = containerName
        self.swiftImage = swiftImage
        self.hostPort = hostPort
        self.containerPort = containerPort
        self.networkName = networkName
        self.workingDirectory = workingDirectory
    }
}

/// Service for managing Lambda Docker containers
public actor LambdaContainerService {
    private let dockerService: DockerService
    private let cliService: CLIService
    private let postgresService: PostgreSQLService
    private let minioService: MinIOService
    private let config: LambdaContainerConfig

    public init(
        dockerService: DockerService,
        cliService: CLIService,
        postgresService: PostgreSQLService,
        minioService: MinIOService,
        config: LambdaContainerConfig
    ) {
        self.dockerService = dockerService
        self.cliService = cliService
        self.postgresService = postgresService
        self.minioService = minioService
        self.config = config
    }

    // MARK: - Network Management

    /// Setup Docker network for Lambda containers
    public func setupNetwork() async throws {
        print("\n🔧 Setting up Docker network for local Lambda testing...")

        // Create network if it doesn't exist
        if !(try await dockerService.networkExists(name: config.networkName)) {
            print("→ Creating Docker network: \(config.networkName)")
            try await dockerService.createNetwork(name: config.networkName)
        } else {
            print("✓ Network \(config.networkName) already exists")
        }

        // Connect PostgreSQL to network
        try await connectContainerToNetwork(container: postgresService.connectionInfo.containerName)

        // Connect MinIO to network
        try await connectContainerToNetwork(container: minioService.minioContainerName)

        print("\n✅ Network setup complete!")
        print("\nYou can now run the Lambda container with:")
        print("  swift run SwiftDeploy local run-container")
    }

    // MARK: - Container Lifecycle

    /// Run Lambda in interactive container
    public func runInteractive() async throws {
        print("\n🚀 Starting Lambda in Linux container...")
        print("")

        // Check if lambda directory exists
        guard FileManager.default.fileExists(atPath: "lambda") else {
            print("❌ Error: lambda directory not found!")
            print("Build the Lambda first with: ./build.sh SwiftLambda")
            throw CLIError.invalidWorkingDirectory("lambda directory not found")
        }

        // Ensure network is set up
        try await setupNetwork()

        print("Starting interactive container...")
        print("(Type 'exit' to leave the container)")
        print("")

        // Run interactive container
        var options = DockerService.RunOptions()
        options.interactive = true
        options.tty = true
        options.remove = true
        options.platform = "linux/amd64"
        options.network = config.networkName
        options.volumes = [("\(config.workingDirectory)/lambda", "/var/task")]
        options.ports = [(config.hostPort, config.containerPort)]
        options.environment = getEnvironmentVariables()

        try await dockerService.run(
            image: config.swiftImage,
            command: ["bash", "-c", "cd /var/task && chmod +x bootstrap && echo '✅ Lambda ready! Run: ./bootstrap' && bash"],
            options: options
        )
    }

    /// Start Lambda in detached mode (for automated testing)
    public func startDetached(lambdaPath: String? = nil) async throws {
        print("🐳 Starting Lambda container in background...")

        // Determine lambda path
        let lambdaDir = lambdaPath ?? "\(config.workingDirectory)/lambda"

        // Check if lambda directory exists
        guard FileManager.default.fileExists(atPath: lambdaDir) else {
            print("❌ Error: lambda directory not found at \(lambdaDir)!")
            print("Build the Lambda first with: ./build.sh SwiftLambda")
            throw CLIError.invalidWorkingDirectory("lambda directory not found")
        }

        // Ensure network is set up
        try await setupNetwork()

        // Run detached container
        var options = DockerService.RunOptions()
        options.detached = true
        options.remove = true
        options.name = config.containerName
        options.platform = "linux/amd64"
        options.network = config.networkName
        options.ports = [(config.hostPort, config.containerPort)]
        options.volumes = [(lambdaDir, "/var/task")]
        options.environment = getEnvironmentVariables()

        try await dockerService.run(
            image: config.swiftImage,
            command: ["bash", "-c", "cd /var/task && chmod +x bootstrap && exec ./bootstrap"],
            options: options
        )

        print("  ✅ Lambda container started")
    }

    /// Stop Lambda container
    public func stop() async throws {
        print("🛑 Stopping Lambda container...")
        try await dockerService.stop(container: config.containerName)
        print("  ✅ Lambda container stopped")
    }

    /// Wait for Lambda to be ready on specified port
    public func waitForReady(maxAttempts: Int = 30) async throws {
        print("🔍 Verifying Lambda is running...")

        // Check container is running
        let isRunning = try await dockerService.containerIsRunning(name: config.containerName)
        guard isRunning else {
            throw CLIError.testFailed(message: "Lambda container '\(config.containerName)' is not running")
        }

        // Wait for Lambda to be ready on the port
        var attempts = 0
        var ready = false

        while attempts < maxAttempts && !ready {
            let portCheck = try await cliService.execute(
                command: "lsof",
                arguments: ["-i", ":\(config.hostPort)"],
                printCommand: false
            )

            if portCheck.isSuccess && !portCheck.stdout.isEmpty {
                ready = true
                break
            }

            try await Task.sleep(for: .seconds(1))
            attempts += 1

            if attempts % 10 == 0 {
                print("  → Still waiting for Lambda on port \(config.hostPort)... (\(attempts) seconds)")
            }
        }

        if !ready {
            // Show container logs for debugging
            print("❌ Lambda failed to start. Checking container logs:")
            let logsResult = try await cliService.execute(
                command: "docker",
                arguments: ["logs", config.containerName],
                printCommand: false
            )
            print(logsResult.stdout)
            print(logsResult.stderr)
            throw CLIError.testFailed(message: "Lambda failed to be ready on port \(config.hostPort) after \(maxAttempts) seconds")
        }

        print("  ✅ Lambda is running and ready")
    }

    /// Check if container is running
    public func isRunning() async throws -> Bool {
        return try await dockerService.containerIsRunning(name: config.containerName)
    }

    // MARK: - Environment

    /// Get environment variables for Lambda container
    nonisolated public func getEnvironmentVariables() -> [String: String] {
        let postgresInfo = postgresService.connectionInfo
        let minioCreds = minioService.credentials

        return [
            // PostgreSQL configuration
            "POSTGRES_HOST": postgresInfo.containerName,
            "POSTGRES_PORT": "\(postgresInfo.port)",
            "POSTGRES_USER_NAME": postgresInfo.username,
            "POSTGRES_DBNAME": postgresInfo.database,
            "POSTGRES_PASSWORD": postgresInfo.password,
            "POSTGRES_PASSWORD_SECRET_ID": "local-testing",  // Bypass Secrets Manager for local testing

            // S3/MinIO configuration
            "S3_BUCKET_NAME": minioService.bucketName,
            "AWS_ENDPOINT_URL": "http://\(minioService.minioContainerName):9000",
            "AWS_ACCESS_KEY_ID": minioCreds.accessKeyId,
            "AWS_SECRET_ACCESS_KEY": minioCreds.secretAccessKey,
            "AWS_REGION": minioCreds.region,
            "AWS_DEFAULT_REGION": minioCreds.region,

            // Disable AWS credential chain for local testing
            "AWS_EC2_METADATA_DISABLED": "true",
            "AWS_CONTAINER_CREDENTIALS_RELATIVE_URI": "",  // Disable ECS credentials

            // Local Lambda server configuration
            "MOCK_AWS_CREDENTIALS": "true",
            "LOCAL_LAMBDA_SERVER_ENABLED": "true",
            "LOCAL_LAMBDA_HOST": "0.0.0.0"
        ]
    }

    // MARK: - Private Helpers

    /// Connect a container to the Lambda network
    private func connectContainerToNetwork(container: String) async throws {
        // Check if container is connected
        let isConnected = try await dockerService.isConnectedToNetwork(
            container: container,
            network: config.networkName
        )

        if !isConnected {
            // Check if container is running
            let isRunning = try await dockerService.containerIsRunning(name: container)

            if isRunning {
                print("→ Connecting \(container) to \(config.networkName)")
                try await dockerService.connectToNetwork(container: container, network: config.networkName)
            } else {
                print("⚠️  Warning: \(container) is not running. Start it with: swift run SwiftDeploy local start-\(container == postgresService.connectionInfo.containerName ? "database" : "s3")")
            }
        } else {
            print("✓ \(container) already connected")
        }
    }
}
