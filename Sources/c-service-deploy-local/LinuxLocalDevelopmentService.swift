import CLISDK
import DockerCLISDK
import MinioSDK
import PostgreSQLSDK
import DynamoDBSDK
import c_service_client
import c_service_lambda_build
import Foundation
import c_service_storage
import c_service_deploy_core

/// Stateless service for Linux container development workflow (AWS Lambda compatible)
/// Orchestrates Docker services, container builds, and Lambda container management
public actor LinuxLocalDevelopmentService {
    private let dockerClient: DockerClient
    private let cliClient: CLIClient
    private let storageService: LocalStorageService

    private let postgresClient: PostgreSQLClient
    private let minioClient: MinIOClient
    private let dynamodbClient: DynamoDBClient
    private let config: LinuxContainerConfig

    // Working directory
    private let workingDirectory: String

    // MARK: - Build Artifact Paths

    private var lambdaDir: String { "\(workingDirectory)/lambda" }
    private var lambdaZipPath: String { "\(workingDirectory)/lambda.zip" }
    private var bootstrapPath: String { "\(lambdaDir)/bootstrap" }
    private var awsSamBuildDir: String { ".aws-sam/build-SwiftLambda" }

    /// Paths to clean when deleting build artifacts (relative to workingDirectory)
    private var buildArtifactPaths: [String] { ["lambda", "lambda.zip", awsSamBuildDir] }

    // MARK: - Initialization

    public init(workingDirectory: String) {
        let cliClient = CLIClient(defaultWorkingDirectory: workingDirectory)
        self.cliClient = cliClient
        let dockerClient = DockerClient(cliClient: cliClient)
        self.dockerClient = dockerClient
        self.workingDirectory = workingDirectory
        let config = LinuxContainerConfig.default(workingDirectory: workingDirectory)
        self.config = config
        let storageService = LocalStorageService()
        self.storageService = storageService

        self.postgresClient = PostgreSQLClient(
            dockerClient: dockerClient,
            config: .linux,
            dataDirectory: storageService.dataDirectory(for: PostgreSQLLinuxStorageKey.self)
        )
        self.minioClient = MinIOClient(
            dockerClient: dockerClient,
            networkName: config.networkName,
            config: .linux,
            dataDirectory: storageService.dataDirectory(for: MinIOLinuxStorageKey.self)
        )
        self.dynamodbClient = DynamoDBClient(
            dockerClient: dockerClient,
            config: .linux,
            dataDirectory: storageService.dataDirectory(for: DynamoDBLocalLinuxStorageKey.self)
        )
    }

    // MARK: - Configuration Properties

    /// The port where Lambda container listens
    public var port: Int { config.hostPort }

    /// The container name
    public var containerName: String { config.containerName }

    // MARK: - Docker Daemon Management

    /// Ensure Docker daemon is running, starting Docker Desktop if needed
    private func ensureDockerRunning() async throws {
        if await dockerClient.isDockerRunning() {
            return
        }
        try await startDockerDesktop()
    }

    /// Start Docker Desktop application and wait for daemon to be ready
    private func startDockerDesktop() async throws {
        print("🐳 Starting Docker Desktop...")

        let result = try await cliClient.executeForResult(
            Open(application: "Docker"),
            printCommand: false
        )

        guard result.isSuccess else {
            throw DeployError.commandFailed(
                command: "open -a Docker",
                exitCode: result.exitCode,
                output: "Failed to start Docker Desktop. Is it installed?"
            )
        }

        print("   Waiting for Docker daemon to be ready...")
        let maxAttempts = 60
        for attempt in 1...maxAttempts {
            if await dockerClient.isDockerRunning() {
                print("   ✅ Docker is ready")
                return
            }
            try await Task.sleep(for: .seconds(1))
            if attempt % 10 == 0 {
                print("   Still waiting... (\(attempt)s)")
            }
        }

        throw DeployError.commandFailed(
            command: "docker",
            exitCode: 1,
            output: "Docker Desktop started but daemon did not become ready within 60 seconds."
        )
    }

    // MARK: - Service Management

    /// Start all services (PostgreSQL + MinIO + DynamoDB)
    public func startAllServices() async throws {
        try await ensureDockerRunning()

        if !(try await minioClient.isRunning()) {
            try await minioClient.start()
        } else {
            print("✓ MinIO (linux) already running")
        }

        if !(try await postgresClient.isRunning()) {
            try await postgresClient.start()
        } else {
            print("✓ PostgreSQL (linux) already running")
        }

        if !(try await dynamodbClient.isRunning()) {
            try await dynamodbClient.start()
        } else {
            print("✓ DynamoDB Local (linux) already running")
        }
    }

    /// Stop all services
    public func stopAllServices() async throws {
        try await minioClient.stop()
        try await postgresClient.stop()
        try await dynamodbClient.stop()
    }

    /// Start MinIO S3 service
    public func startS3() async throws {
        try await ensureDockerRunning()
        try await minioClient.start()
    }

    /// Create S3 bucket in MinIO
    public func createBucket(bucketName: String? = nil) async throws {
        try await minioClient.createBucket(bucketName: bucketName)
    }

    /// Stop MinIO S3 service
    public func stopS3() async throws {
        try await minioClient.stop()
    }

    /// Start PostgreSQL database
    public func startDatabase() async throws {
        try await ensureDockerRunning()
        try await postgresClient.start()
    }

    /// Stop PostgreSQL database
    public func stopDatabase() async throws {
        try await postgresClient.stop()
    }

    /// Start DynamoDB Local
    public func startDynamoDB() async throws {
        try await ensureDockerRunning()
        try await dynamodbClient.start()
    }

    /// Stop DynamoDB Local
    public func stopDynamoDB() async throws {
        try await dynamodbClient.stop()
    }

    /// Data directory for S3 (MinIO)
    public var s3DataDirectory: String {
        storageService.dataDirectory(for: MinIOLinuxStorageKey.self)
    }

    /// Data directory for PostgreSQL
    public var postgresDataDirectory: String {
        storageService.dataDirectory(for: PostgreSQLLinuxStorageKey.self)
    }

    /// Data directory for DynamoDB Local
    public var dynamodbDataDirectory: String {
        storageService.dataDirectory(for: DynamoDBLocalLinuxStorageKey.self)
    }

    // MARK: - Build Operations

    /// Build Lambda for Linux (AMD64) using Docker
    /// - Parameters:
    ///   - clean: Whether to clean build artifacts first
    ///   - output: Optional stream to receive build output
    public func build(clean: Bool = false, output: CLIOutputStream? = nil) async throws {
        if clean {
            let cleanMsg = "🧹 Cleaning previous build artifacts...\n"
            await output?.send(.stdout(commandID: .init(), text: cleanMsg))
            do {
                let rmCmd = Rm(recursive: true, force: true, paths: buildArtifactPaths)
                _ = try await cliClient.execute(
                    rmCmd,
                    workingDirectory: workingDirectory,
                    printCommand: false,
                    output: output
                )
                let successMsg = "  ✅ Cleaned\n"
                await output?.send(.stdout(commandID: .init(), text: successMsg))
            } catch {
                let errorMsg = "  ❌ Clean failed: \(error)\n"
                await output?.send(.stderr(commandID: .init(), text: errorMsg))
                throw BuildError.failed(exitCode: 1)
            }
        }

        let buildMsg = "🔨 Building Lambda for Linux (Docker)...\n"
        await output?.send(.stdout(commandID: .init(), text: buildMsg))

        let buildCmd = BuildScript.Build.lambda(target: "app-lambda")
        let stream = await cliClient.stream(
            buildCmd,
            workingDirectory: workingDirectory,
            printCommand: false,
            output: output
        )

        var exitCode: Int32 = 0
        for await streamOutput in stream {
            switch streamOutput {
            case .exit(_, let code):
                exitCode = code
            default:
                break
            }
        }

        if exitCode != 0 {
            throw BuildError.failed(exitCode: exitCode)
        }
    }

    /// Check if Lambda is already built (Linux artifacts)
    public func isLambdaBuilt() -> Bool {
        return FileManager.default.fileExists(atPath: lambdaDir) &&
               FileManager.default.fileExists(atPath: bootstrapPath) &&
               FileManager.default.fileExists(atPath: lambdaZipPath)
    }

    /// Delete build artifacts
    public func deleteBuild() async throws {
        let rmCmd = Rm(recursive: true, force: true, paths: buildArtifactPaths)
        _ = try await cliClient.execute(
            rmCmd,
            workingDirectory: workingDirectory,
            printCommand: false
        )
    }

    // MARK: - Lambda Lifecycle

    /// Start Lambda container in detached mode
    /// - Parameter output: Optional stream to receive output
    public func startLambda(output: CLIOutputStream? = nil) async throws {
        let startMsg = "🚀 Starting Lambda container...\n"
        await output?.send(.stdout(commandID: .init(), text: startMsg))

        try await startDetached(lambdaPath: nil, output: output)

        let containerMsg = "   Container: \(config.containerName)\n"
        let portMsg = "   Port: http://localhost:\(port)\n"
        await output?.send(.stdout(commandID: .init(), text: containerMsg))
        await output?.send(.stdout(commandID: .init(), text: portMsg))
        let doneMsg = "\n✅ Lambda is running\n"
        await output?.send(.stdout(commandID: .init(), text: doneMsg))
    }

    /// Stop Lambda container
    /// - Parameter output: Optional stream to receive output
    public func stopLambda(output: CLIOutputStream? = nil) async throws {
        let stopMsg = "🛑 Stopping Lambda container...\n"
        await output?.send(.stdout(commandID: .init(), text: stopMsg))

        do {
            try await dockerClient.stop(container: config.containerName)
            let doneMsg = "\n✅ Lambda stopped\n"
            await output?.send(.stdout(commandID: .init(), text: doneMsg))
        } catch {
            let warnMsg = "⚠️  Container may already be stopped\n"
            await output?.send(.stdout(commandID: .init(), text: warnMsg))
        }
    }

    /// Start Lambda container with all services (complete flow)
    /// - Parameter output: Optional stream to receive output
    public func startWithServices(output: CLIOutputStream? = nil) async throws {
        print("\n🚀 Setting up complete Lambda container environment...")

        print("\n→ Checking for existing Lambda container...")
        do {
            try await stopLambda(output: output)
        } catch {
            print("  (No existing container to stop)")
        }

        print("\n→ Starting local services...")
        try await startAllServices()

        print("\n→ Setting up Docker network...")
        try await setupDockerNetwork()

        print("\n→ Ensuring S3 bucket exists...")
        try await minioClient.createBucket(bucketName: nil)

        print("\n→ Starting Lambda container in background...")
        try await startLambda(output: output)

        print("\n✅ Lambda container started!")
        print("   Container: \(config.containerName)")
        print("   Port: http://localhost:\(port)")
        print("")
        print("To test: ./tools.sh local linux test")
        print("To stop: ./tools.sh local linux stop-all")
    }

    /// Stop Lambda container and all services
    /// - Parameter output: Optional stream to receive output
    public func stopWithServices(output: CLIOutputStream? = nil) async throws {
        print("\n🛑 Stopping Lambda container and services...")

        print("\n→ Stopping Lambda container...")
        do {
            try await stopLambda(output: output)
        } catch {
            print("  (No container to stop)")
        }

        print("\n→ Stopping local services...")
        try await stopAllServices()

        print("\n✅ All services stopped")
    }

    // MARK: - Testing

    /// Wait for Lambda to be ready on specified port
    public func waitForReady(maxAttempts: Int = 30) async throws {
        print("🔍 Verifying Lambda is running...")

        let isRunning = try await dockerClient.containerIsRunning(name: config.containerName)
        guard isRunning else {
            throw DeployError.testFailed(message: "Lambda container '\(config.containerName)' is not running")
        }

        var attempts = 0
        var ready = false

        while attempts < maxAttempts && !ready {
            let portCheck = try await cliClient.executeForResult(
                Lsof(port: ":\(config.hostPort)"),
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
            print("❌ Lambda failed to start. Checking container logs:")
            let logsResult = try await cliClient.execute(
                command: "docker",
                arguments: ["logs", config.containerName],
                printCommand: false
            )
            print(logsResult.stdout)
            print(logsResult.stderr)
            throw DeployError.testFailed(message: "Lambda failed to be ready on port \(config.hostPort) after \(maxAttempts) seconds")
        }

        print("  ✅ Lambda is running and ready")
    }

    /// Test Lambda container endpoints using Client library
    public func testLambda() async throws {
        print("\n🧪 Testing Lambda container on port \(config.hostPort)...")
        print("")

        do {
            try await performLocalLambdaTests()
        } catch let error as APIError {
            throw DeployError.testFailed(message: "API Error: \(error.localizedDescription)")
        }

        print("")
        print("✅ All Lambda container tests passed!")
    }

    // MARK: - Status

    /// Get the status of all services (Lambda, S3, PostgreSQL, DynamoDB)
    public func status() async throws -> DeploymentStatus {
        let lambdaRunning = try await isRunning()
        let s3Running = try await minioClient.isRunning()
        let postgresRunning = try await postgresClient.isRunning()
        let dynamodbRunning = try await dynamodbClient.isRunning()

        return DeploymentStatus(
            lambdaState: lambdaRunning ? .running : .stopped,
            s3State: s3Running ? .running : .stopped,
            postgresState: postgresRunning ? .running : .stopped,
            dynamodbState: dynamodbRunning ? .running : .stopped
        )
    }

    /// Check if Lambda container is running
    public func isRunning() async throws -> Bool {
        return try await dockerClient.containerIsRunning(name: config.containerName)
    }

    // MARK: - Linux-Specific Methods

    /// Setup Docker network for Lambda container
    public func setupDockerNetwork() async throws {
        if !(try await dockerClient.networkExists(name: config.networkName)) {
            print("→ Creating Docker network: \(config.networkName)")
            try await dockerClient.createNetwork(name: config.networkName)
        } else {
            print("✓ Network \(config.networkName) already exists")
        }

        try await connectContainerToNetwork(container: postgresClient.connectionInfo.containerName)
        try await connectContainerToNetwork(container: minioClient.minioContainerName)
        try await connectContainerToNetwork(container: dynamodbClient.connectionInfo.containerName)
    }

    /// Print the Docker command to run Lambda interactively
    public func printRunCommand() async throws {
        guard FileManager.default.fileExists(atPath: lambdaDir) else {
            print("❌ Error: lambda directory not found!")
            print("Build the Lambda first with: ./tools.sh local linux build")
            throw CLIClientError.invalidWorkingDirectory("lambda directory not found")
        }

        let env = getEnvironmentVariables()
        let envFlags = env.map { "-e \($0.key)=\($0.value)" }.joined(separator: " \\\n    ")

        print("""
        docker run --rm -it \\
            --platform linux/amd64 \\
            --network \(config.networkName) \\
            --name \(config.containerName) \\
            -p \(config.hostPort):\(config.containerPort) \\
            -v \(lambdaDir):/var/task \\
            \(envFlags) \\
            \(config.swiftImage) \\
            bash -c 'cd /var/task && chmod +x bootstrap && echo "✅ Lambda ready! Run: ./bootstrap" && bash'

        Inside the container, run: ./bootstrap
        To exit: Type 'exit' or press Ctrl+D
        """)
    }

    /// Run Lambda in interactive container
    public func runInteractive() async throws {
        guard FileManager.default.fileExists(atPath: lambdaDir) else {
            print("❌ Error: lambda directory not found!")
            print("Build the Lambda first with: ./tools.sh local linux build")
            throw CLIClientError.invalidWorkingDirectory("lambda directory not found")
        }

        print("\n✅ Starting interactive container...")
        print("(Type 'exit' to leave the container)\n")

        var options = DockerClient.RunOptions()
        options.interactive = true
        options.tty = true
        options.remove = true
        options.platform = "linux/amd64"
        options.network = config.networkName
        options.volumes = [(lambdaDir, "/var/task")]
        options.ports = [(config.hostPort, config.containerPort)]
        options.environment = getEnvironmentVariables()

        try await dockerClient.run(
            image: config.swiftImage,
            command: ["bash", "-c", "cd /var/task && chmod +x bootstrap && echo '✅ Lambda ready! Run: ./bootstrap' && bash"],
            options: options
        )
    }

    /// Copy config file to home directory
    public func copyConfig(sourcePath: String? = nil) async throws {
        print("\n📝 Copying runtime config file...")

        let storageService = LocalStorageService()

        try storageService.ensureDirectoryExists(at: storageService.baseDataDirectory)

        let appConfigSource = sourcePath ?? AppConfigFileKey.filename
        let appConfigDest = storageService.filePath(for: AppConfigFileKey.self)

        guard FileManager.default.fileExists(atPath: appConfigSource) else {
            throw CLIClientError.invalidWorkingDirectory("App config file not found at: \(appConfigSource)")
        }

        if FileManager.default.fileExists(atPath: appConfigDest) {
            try FileManager.default.removeItem(atPath: appConfigDest)
        }
        try FileManager.default.copyItem(atPath: appConfigSource, toPath: appConfigDest)
        print("  ✓ Runtime config: \(appConfigDest)")

        print("\n✅ Runtime config copied to \(storageService.baseDataDirectory)/")
    }

    // MARK: - Private Helpers

    /// Start Lambda container in detached mode
    private func startDetached(lambdaPath: String? = nil, output: CLIOutputStream? = nil) async throws {
        try await ensureDockerRunning()

        let effectiveLambdaDir = lambdaPath ?? lambdaDir

        guard FileManager.default.fileExists(atPath: effectiveLambdaDir) else {
            print("❌ Error: lambda directory not found at \(effectiveLambdaDir)!")
            print("Build the Lambda first with: ./tools.sh local linux build")
            throw CLIClientError.invalidWorkingDirectory("lambda directory not found")
        }

        var options = DockerClient.RunOptions()
        options.detached = true
        options.remove = true
        options.name = config.containerName
        options.platform = "linux/amd64"
        options.network = config.networkName
        options.ports = [(config.hostPort, config.containerPort)]
        options.volumes = [(effectiveLambdaDir, "/var/task")]
        options.environment = getEnvironmentVariables()

        try await dockerClient.run(
            image: config.swiftImage,
            command: ["bash", "-c", "cd /var/task && chmod +x bootstrap && exec ./bootstrap"],
            options: options,
            output: output
        )
    }

    /// Get environment variables for Lambda container (Docker network)
    public func getEnvironmentVariables() -> [String: String] {
        return createEnvironmentVariables(
            postgresClient: postgresClient,
            minioClient: minioClient,
            dynamodbClient: dynamodbClient,
            context: .container
        )
    }

    /// Connect a container to the Lambda network
    private func connectContainerToNetwork(container: String) async throws {
        try await Task.sleep(for: .seconds(1))

        let isConnected = try await dockerClient.isConnectedToNetwork(
            container: container,
            network: config.networkName
        )

        if !isConnected {
            let isRunning = try await dockerClient.containerIsRunning(name: container)

            if isRunning {
                print("→ Connecting \(container) to \(config.networkName)")
                try await dockerClient.connectToNetwork(container: container, network: config.networkName)
            } else {
                print("⚠️  Warning: \(container) is not running. Start it with: swift run SwiftDeploy local services start-\(container == postgresClient.connectionInfo.containerName ? "database" : "s3")")
            }
        } else {
            print("✓ \(container) already connected")
        }
    }

    private func performLocalLambdaTests() async throws {
        let client = await MainActor.run { APIClient(localPort: config.hostPort, serviceName: "Local Linux (Container)") }

        print("→ Testing file upload...")
        let testContent = "Hello from test file!"
        guard let testData = testContent.data(using: .utf8) else {
            throw DeployError.testFailed(message: "Failed to create test data")
        }

        let uploadResponse = try await client.uploadFile(fileName: "test-upload.txt", data: testData)
        if uploadResponse.contains("File uploaded: test-upload.txt") {
            print("  ✅ File upload test passed")
        } else {
            print("  ❌ File upload test failed: \(uploadResponse)")
            throw DeployError.testFailed(message: "File upload endpoint test failed")
        }

        print("")

        print("→ Testing list files...")
        let fileList = try await client.listFiles()
        if fileList.contains("test-upload.txt") {
            print("  ✅ List files test passed (found \(fileList.count) files)")
        } else {
            print("  ❌ List files test failed: \(fileList)")
            throw DeployError.testFailed(message: "List files endpoint test failed")
        }

        print("")

        print("→ Testing file download...")
        let downloadedData = try await client.downloadFile(fileName: "test-upload.txt")
        if let downloadedContent = String(data: downloadedData, encoding: .utf8) {
            if downloadedContent.contains("Hello from test file!") {
                print("  ✅ File download test passed")
            } else {
                print("  ❌ File download test failed: unexpected content")
                throw DeployError.testFailed(message: "File download endpoint test failed")
            }
        } else {
            print("  ❌ File download test failed: could not decode content")
            throw DeployError.testFailed(message: "File download endpoint test failed")
        }

        print("")

        print("→ Testing database initialization...")
        let dbResult = try await client.initializeDatabase()
        if dbResult.contains("Database Initialized") {
            print("  ✅ Database test passed")
        } else {
            print("  ❌ Database test failed: \(dbResult)")
            throw DeployError.testFailed(message: "Database endpoint test failed")
        }
    }
}

/// Configuration for Lambda container
struct LinuxContainerConfig: Sendable {
    let containerName: String
    let swiftImage: String
    let hostPort: Int
    let containerPort: Int
    let networkName: String
    let workingDirectory: String

    /// Create the default Linux container configuration
    /// Uses port 8081 to avoid conflict with Xcode local service (port 8080)
    static func `default`(workingDirectory: String) -> LinuxContainerConfig {
        LinuxContainerConfig(
            containerName: "lambda-linux-container",
            swiftImage: "swift:6.2.0-amazonlinux2",
            hostPort: 8081,
            containerPort: 7000,
            networkName: "lambda-linux",
            workingDirectory: workingDirectory
        )
    }
}
