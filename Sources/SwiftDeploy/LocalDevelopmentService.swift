import Client
import Foundation

/// Service for managing local development environment (Docker services, testing)
public actor LocalDevelopmentService {
    private let dockerService: DockerService
    private let cliService: CLIService

    // Container configuration
    private let minioImageName = "quay.io/minio/minio"
    private let minioContainerName = "minio-lambda"  // Use hyphen not underscore for valid HTTP hostname
    private let postgresImageName = "postgres-lambda"
    private let postgresContainerName = "postgres-lambda"
    private let lambdaContainerName = "lambda-test-container"
    private let lambdaSwiftImage = "swift:6.2.0-amazonlinux2"
    private let networkName = "lambda-local"

    // Lambda configuration
    private let lambdaHostPort = 8080
    private let lambdaContainerPort = 7000
    private let s3BucketName = "org.gestrich.sandbox"

    // Working directory
    private let workingDirectory: String

    // Public accessors for configuration
    public var port: Int { lambdaHostPort }

    /// Get the local Lambda endpoint URL
    nonisolated public var localEndpoint: String {
        "http://localhost:\(lambdaHostPort)/invoke"
    }

    public init(workingDirectory: String) {
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
        let minioRootPath = "\(homeDir)/minio"
        let minioDataPath = "\(minioRootPath)/data"

        // Clean any existing MinIO data to avoid configuration conflicts
        if FileManager.default.fileExists(atPath: minioDataPath) {
            print("→ Removing existing MinIO data...")
            try FileManager.default.removeItem(atPath: minioDataPath)
        }

        // Create fresh data directory
        try FileManager.default.createDirectory(
            atPath: "\(minioDataPath)/org.gestrich.sandbox",
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
            "MINIO_ROOT_PASSWORD": "password",
            "MINIO_REGION_NAME": "us-east-1"  // Modern MinIO uses MINIO_REGION_NAME
        ]
        options.volumes = [("\(minioDataPath)", "/data")]

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

    /// Create S3 bucket in MinIO
    public func createBucket(bucketName: String? = nil) async throws {
        let bucket = bucketName ?? s3BucketName
        print("📦 Creating S3 bucket in MinIO...")

        // Run AWS CLI in a container to create the bucket
        var options = DockerService.RunOptions()
        options.remove = true
        options.network = networkName
        options.environment = [
            "AWS_ACCESS_KEY_ID": "admin",
            "AWS_SECRET_ACCESS_KEY": "password",
            "AWS_REGION": "us-east-1",
            "AWS_DEFAULT_REGION": "us-east-1"
        ]

        do {
            try await dockerService.run(
                image: "amazon/aws-cli",
                command: ["--endpoint-url", "http://\(minioContainerName):9000", "s3", "mb", "s3://\(bucket)"],
                options: options
            )
            print("  ✅ S3 bucket '\(bucket)' created")
        } catch {
            // Bucket might already exist, which is fine
            print("  ℹ️  Bucket might already exist (this is OK)")
        }
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

    // MARK: - Lambda Build

    /// Build Lambda for Linux
    public func buildLambda(clean: Bool = false) async throws {
        print("\n🔨 Building Lambda for Linux...")

        // Clean if requested
        if clean {
            print("🧹 Cleaning previous build artifacts...")
            _ = try await cliService.execute(
                command: "rm",
                arguments: ["-rf", ".aws-sam/build-SwiftLambda", "lambda", "lambda.zip"],
                workingDirectory: workingDirectory,
                printCommand: false
            )
            print("  ✅ Cleaned")
        }

        // Build
        let buildResult = try await cliService.execute(
            command: "./build.sh",
            arguments: ["SwiftLambda"],
            workingDirectory: workingDirectory,
            inheritIO: true  // Show build output in real-time
        )

        guard buildResult.isSuccess else {
            throw CLIError.commandFailed(
                command: "build.sh SwiftLambda",
                exitCode: buildResult.exitCode,
                stderr: buildResult.stderr
            )
        }

        print("✅ Build completed")
    }

    /// Check if Lambda is already built
    public nonisolated func isLambdaBuilt() -> Bool {
        let lambdaDir = "\(workingDirectory)/lambda"
        let bootstrapPath = "\(lambdaDir)/bootstrap"
        let zipPath = "\(workingDirectory)/lambda.zip"

        return FileManager.default.fileExists(atPath: lambdaDir) &&
               FileManager.default.fileExists(atPath: bootstrapPath) &&
               FileManager.default.fileExists(atPath: zipPath)
    }

    // MARK: - Local Lambda Execution

    /// Start Lambda locally (not in container)
    public func startLambdaLocally() async throws {
        print("\n🚀 Starting Lambda locally...")

        // Build Lambda
        print("→ Building SwiftLambda...")
        let buildResult = try await cliService.execute(
            command: "swift",
            arguments: ["build", "--product", "SwiftLambda"],
            workingDirectory: workingDirectory,
            printCommand: false
        )

        guard buildResult.isSuccess else {
            throw CLIError.commandFailed(
                command: "swift build",
                exitCode: buildResult.exitCode,
                stderr: buildResult.stderr
            )
        }

        print("✅ Build completed")

        // Get the built executable path
        let executablePath = "\(workingDirectory)/.build/debug/SwiftLambda"

        // Start Lambda in background with environment variables
        print("→ Starting Lambda on port \(lambdaHostPort)...")

        var env = getLambdaEnvironmentVariables()
        env["LOCAL_LAMBDA_SERVER_ENABLED"] = "true"
        env["LOCAL_LAMBDA_HOST"] = "0.0.0.0"
        env["LOCAL_LAMBDA_PORT"] = "\(lambdaHostPort)"

        // Build environment variable string for shell
        let envVars = env.map { "\($0.key)=\($0.value)" }.joined(separator: " ")

        // Run in background using nohup
        _ = try await cliService.execute(
            command: "sh",
            arguments: ["-c", "\(envVars) \(executablePath) > /tmp/lambda.log 2>&1 & echo $!"],
            workingDirectory: workingDirectory,
            printCommand: false
        )

        // Wait a bit for Lambda to start
        print("→ Waiting for Lambda to start...")
        try await Task.sleep(for: .seconds(3))

        // Check if it's running
        let checkResult = try await cliService.execute(
            command: "lsof",
            arguments: ["-i", ":\(lambdaHostPort)"],
            printCommand: false
        )

        if checkResult.isSuccess && !checkResult.stdout.isEmpty {
            print("\n✅ Lambda is running on port \(lambdaHostPort)")
            print("   Test with: ./tools.sh local lambda test")
            print("   Stop with: ./tools.sh local lambda stop")
        } else {
            throw CLIError.testFailed(message: "Lambda failed to start on port \(lambdaHostPort)")
        }
    }

    /// Stop locally running Lambda
    public func stopLambdaLocally() async throws {
        print("\n🛑 Stopping Lambda...")

        // Find process on port
        let lsofResult = try await cliService.execute(
            command: "lsof",
            arguments: ["-i", ":\(lambdaHostPort)", "-t"],
            printCommand: false
        )

        if lsofResult.isSuccess && !lsofResult.stdout.isEmpty {
            let pid = lsofResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            print("→ Killing process \(pid)...")

            let killResult = try await cliService.execute(
                command: "kill",
                arguments: [pid],
                printCommand: false
            )

            if killResult.isSuccess {
                print("✅ Lambda stopped")
            } else {
                throw CLIError.commandFailed(
                    command: "kill",
                    exitCode: killResult.exitCode,
                    stderr: killResult.stderr
                )
            }
        } else {
            print("⚠️  No Lambda process found on port \(lambdaHostPort)")
        }
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

        // Run interactive container
        var options = DockerService.RunOptions()
        options.interactive = true
        options.tty = true
        options.remove = true
        options.platform = "linux/amd64"
        options.network = networkName
        options.volumes = [("\(workingDirectory)/lambda", "/var/task")]
        options.ports = [(lambdaHostPort, lambdaContainerPort)]
        options.environment = getLambdaEnvironmentVariables()

        try await dockerService.run(
            image: lambdaSwiftImage,
            command: ["bash", "-c", "cd /var/task && chmod +x bootstrap && echo '✅ Lambda ready! Run: ./bootstrap' && bash"],
            options: options
        )
    }

    /// Run Lambda in detached mode (for automated testing)
    public func startLambdaContainerDetached(lambdaPath: String? = nil) async throws {
        print("🐳 Starting Lambda container in background...")

        // Determine lambda path
        let lambdaDir = lambdaPath ?? "\(workingDirectory)/lambda"

        // Check if lambda directory exists
        guard FileManager.default.fileExists(atPath: lambdaDir) else {
            print("❌ Error: lambda directory not found at \(lambdaDir)!")
            print("Build the Lambda first with: ./build.sh SwiftLambda")
            throw CLIError.invalidWorkingDirectory("lambda directory not found")
        }

        // Ensure network is set up
        try await setupLambdaNetwork()

        // Run detached container
        var options = DockerService.RunOptions()
        options.detached = true
        options.remove = true
        options.name = lambdaContainerName
        options.platform = "linux/amd64"
        options.network = networkName
        options.ports = [(lambdaHostPort, lambdaContainerPort)]
        options.volumes = [(lambdaDir, "/var/task")]
        options.environment = getLambdaEnvironmentVariables()

        try await dockerService.run(
            image: lambdaSwiftImage,
            command: ["bash", "-c", "cd /var/task && chmod +x bootstrap && exec ./bootstrap"],
            options: options
        )

        print("  ✅ Lambda container started")
    }

    /// Stop Lambda container
    public func stopLambdaContainer() async throws {
        print("🛑 Stopping Lambda container...")
        try await dockerService.stop(container: lambdaContainerName)
        print("  ✅ Lambda container stopped")
    }

    /// Wait for Lambda to be ready on specified port
    public func waitForLambdaReady(maxAttempts: Int = 30) async throws {
        print("🔍 Verifying Lambda is running...")

        // Check container is running
        let isRunning = try await dockerService.containerIsRunning(name: lambdaContainerName)
        guard isRunning else {
            throw CLIError.testFailed(message: "Lambda container '\(lambdaContainerName)' is not running")
        }

        // Wait for Lambda to be ready on the port
        var attempts = 0
        var ready = false

        while attempts < maxAttempts && !ready {
            let portCheck = try await cliService.execute(
                command: "lsof",
                arguments: ["-i", ":\(lambdaHostPort)"],
                printCommand: false
            )

            if portCheck.isSuccess && !portCheck.stdout.isEmpty {
                ready = true
                break
            }

            try await Task.sleep(for: .seconds(1))
            attempts += 1

            if attempts % 10 == 0 {
                print("  → Still waiting for Lambda on port \(lambdaHostPort)... (\(attempts) seconds)")
            }
        }

        if !ready {
            // Show container logs for debugging
            print("❌ Lambda failed to start. Checking container logs:")
            let logsResult = try await cliService.execute(
                command: "docker",
                arguments: ["logs", lambdaContainerName],
                printCommand: false
            )
            print(logsResult.stdout)
            print(logsResult.stderr)
            throw CLIError.testFailed(message: "Lambda failed to be ready on port \(lambdaHostPort) after \(maxAttempts) seconds")
        }

        print("  ✅ Lambda is running and ready")
    }

    /// Get standard Lambda environment variables for local testing
    private func getLambdaEnvironmentVariables() -> [String: String] {
        return [
            // PostgreSQL configuration
            "POSTGRES_HOST": postgresContainerName,
            "POSTGRES_PORT": "5432",
            "POSTGRES_USER_NAME": "docker",
            "POSTGRES_DBNAME": "docker",
            "POSTGRES_PASSWORD": "docker",
            "POSTGRES_PASSWORD_SECRET_ID": "local-testing",  // Bypass Secrets Manager for local testing

            // S3/MinIO configuration
            "S3_BUCKET_NAME": s3BucketName,
            "AWS_ENDPOINT_URL": "http://\(minioContainerName):9000",
            "AWS_ACCESS_KEY_ID": "admin",
            "AWS_SECRET_ACCESS_KEY": "password",
            "AWS_REGION": "us-east-1",
            "AWS_DEFAULT_REGION": "us-east-1",

            // Disable AWS credential chain for local testing
            "AWS_EC2_METADATA_DISABLED": "true",
            "AWS_CONTAINER_CREDENTIALS_RELATIVE_URI": "",  // Disable ECS credentials

            // Local Lambda server configuration
            "MOCK_AWS_CREDENTIALS": "true",
            "LOCAL_LAMBDA_SERVER_ENABLED": "true",
            "LOCAL_LAMBDA_HOST": "0.0.0.0"
        ]
    }

    /// Create an API client configured for local Lambda testing
    @MainActor
    private func createLocalAPIClient() -> APIClient {
        let endpoint = "http://localhost:\(lambdaHostPort)/invoke"
        return APIClient(
            baseURL: "http://localhost:\(lambdaHostPort)",
            mode: .localLambda(endpoint: endpoint)
        )
    }

    /// Test local Lambda endpoints using Client library
    public func testLocalLambda() async throws {
        print("\n🧪 Testing local Lambda on port \(lambdaHostPort)...")
        print("")

        do {
            try await performLocalLambdaTests()
        } catch let error as APIError {
            throw CLIError.testFailed(message: "API Error: \(error.localizedDescription)")
        }

        print("")
        print("✅ All local Lambda tests passed!")
    }

    @MainActor
    private func performLocalLambdaTests() async throws {
        let client = createLocalAPIClient()

        // Test file upload
        print("→ Testing file upload...")
        let testContent = "Hello from test file!"
        guard let testData = testContent.data(using: .utf8) else {
            throw CLIError.testFailed(message: "Failed to create test data")
        }

        let uploadResponse = try await client.uploadFile(fileName: "test-upload.txt", data: testData)
        if uploadResponse.contains("File uploaded: test-upload.txt") {
            print("  ✅ File upload test passed")
        } else {
            print("  ❌ File upload test failed: \(uploadResponse)")
            throw CLIError.testFailed(message: "File upload endpoint test failed")
        }

        print("")

        // Test list files
        print("→ Testing list files...")
        let fileList = try await client.listFiles()
        if fileList.contains("test-upload.txt") {
            print("  ✅ List files test passed (found \(fileList.count) files)")
        } else {
            print("  ❌ List files test failed: \(fileList)")
            throw CLIError.testFailed(message: "List files endpoint test failed")
        }

        print("")

        // Test file download
        print("→ Testing file download...")
        let downloadedData = try await client.downloadFile(fileName: "test-upload.txt")
        if let downloadedContent = String(data: downloadedData, encoding: .utf8) {
            if downloadedContent.contains("Hello from test file!") {
                print("  ✅ File download test passed")
            } else {
                print("  ❌ File download test failed: unexpected content")
                throw CLIError.testFailed(message: "File download endpoint test failed")
            }
        } else {
            print("  ❌ File download test failed: could not decode content")
            throw CLIError.testFailed(message: "File download endpoint test failed")
        }

        print("")

        // Test database initialization
        print("→ Testing database initialization...")
        let dbResult = try await client.initializeDatabase()
        if dbResult.contains("Database Initialized") {
            print("  ✅ Database test passed")
        } else {
            print("  ❌ Database test failed: \(dbResult)")
            throw CLIError.testFailed(message: "Database endpoint test failed")
        }
    }

    // MARK: - Configuration

    /// Copy config file to home directory
    /// - Parameter sourcePath: Optional path to the config file. If nil, uses "swiftLambdaDemo.json" in current directory
    public func copyConfig(sourcePath: String? = nil) async throws {
        print("\n📝 Copying runtime config file...")

        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let configDir = "\(homeDir)/.swiftSampleDemo"

        // Create directory
        try FileManager.default.createDirectory(
            atPath: configDir,
            withIntermediateDirectories: true,
            attributes: nil
        )

        // Copy swiftLambdaDemo.json (runtime app config)
        let appConfigSource = sourcePath ?? "swiftLambdaDemo.json"
        let appConfigDest = "\(configDir)/swiftLambdaDemo.json"

        guard FileManager.default.fileExists(atPath: appConfigSource) else {
            throw CLIError.invalidWorkingDirectory("App config file not found at: \(appConfigSource)")
        }

        if FileManager.default.fileExists(atPath: appConfigDest) {
            try FileManager.default.removeItem(atPath: appConfigDest)
        }
        try FileManager.default.copyItem(atPath: appConfigSource, toPath: appConfigDest)
        print("  ✓ Runtime config: \(appConfigDest)")

        print("\n✅ Runtime config copied to ~/.swiftSampleDemo/")
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
