import CLIKit
import Client
import Combine
import Foundation
import LocalStorageService

/// Service for Linux container deployment workflow (AWS Lambda compatible)
/// Uses Docker to build and run Lambda in a Linux container that matches AWS environment
@MainActor
public class LinuxLocalService: LocalService {
    private let dockerService: DockerService
    public let cliService: CLIService
    private let storageService: LocalStorageService

    private let postgresService: PostgreSQLService
    private let minioService: MinIOService
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

    // MARK: - Combine Publishers

    private let statusSubject = CurrentValueSubject<DeploymentStatus, Never>(.stopped)
    private let isLoadingStatusSubject = CurrentValueSubject<Bool, Never>(false)

    public var statusPublisher: AnyPublisher<DeploymentStatus, Never> {
        statusSubject.eraseToAnyPublisher()
    }

    public var isLoadingStatusPublisher: AnyPublisher<Bool, Never> {
        isLoadingStatusSubject.eraseToAnyPublisher()
    }

    // MARK: - Unified Output

    public let unifiedOutput = UnifiedOutputState()

    // MARK: - Build State

    public let buildState = BuildState()

    // MARK: - Lambda State

    public let lambdaState = LambdaState()

    // MARK: - LambdaService Protocol

    public static let persistenceKey = "localLinux"

    public static let displayName = "Local Linux (Container)"

    public static let detailText = "Docker container build - matches AWS Lambda environment"

    public var port: Int { config.hostPort }

    public var endpoint: String {
        "http://localhost:\(config.hostPort)/invoke"
    }

    public var endpointLabel: String { "Local Lambda Endpoint" }

    public var endpointHelpText: String {
        "Make sure local Lambda container is running on port \(config.hostPort)"
    }

    public var apiClient: APIClient {
        APIClient(localPort: config.hostPort)
    }

    public var isConfigured: Bool { true }

    public init(workingDirectory: String) {
        self.workingDirectory = workingDirectory
        let cliService = CLIService(defaultWorkingDirectory: workingDirectory)
        self.cliService = cliService
        self.dockerService = DockerService(cliService: cliService)
        self.config = .default(workingDirectory: workingDirectory)
        self.storageService = LocalStorageService()

        self.postgresService = PostgreSQLService(
            dockerService: dockerService,
            config: .linux,
            storageService: storageService
        )
        self.minioService = MinIOService(
            dockerService: dockerService,
            networkName: config.networkName,
            config: .linux,
            storageService: storageService
        )

        // Check for existing build artifacts
        refreshBuildStatus()
    }

    // MARK: - Service Management

    /// Start all services (PostgreSQL + MinIO)
    /// Services persist between mode switches - only starts if not already running
    public func startAllServices() async throws {
        try await dockerService.ensureDockerRunning()

        // Only start services if not already running (persist between sessions)
        if !(try await minioService.isRunning()) {
            try await minioService.start()
        } else {
            print("✓ MinIO (linux) already running")
        }

        if !(try await postgresService.isRunning()) {
            try await postgresService.start()
        } else {
            print("✓ PostgreSQL (linux) already running")
        }
    }

    /// Stop all services
    public func stopAllServices() async throws {
        try await minioService.stop()
        try await postgresService.stop()
    }

    /// Start MinIO S3 service
    public func startS3() async throws {
        try await dockerService.ensureDockerRunning()
        try await minioService.start()
    }

    /// Create S3 bucket in MinIO
    public func createBucket(bucketName: String? = nil) async throws {
        try await minioService.createBucket(bucketName: bucketName)
    }

    /// Stop MinIO S3 service
    public func stopS3() async throws {
        try await minioService.stop()
    }

    /// Start PostgreSQL database
    public func startDatabase() async throws {
        try await dockerService.ensureDockerRunning()
        try await postgresService.start()
    }

    /// Stop PostgreSQL database
    public func stopDatabase() async throws {
        try await postgresService.stop()
    }

    /// Data directory for S3 (MinIO)
    public var s3DataDirectory: String {
        storageService.dataDirectory(for: MinIOLinuxStorageKey.self)
    }

    /// Data directory for PostgreSQL
    public var postgresDataDirectory: String {
        storageService.dataDirectory(for: PostgreSQLLinuxStorageKey.self)
    }

    // MARK: - LambdaService Protocol: Build

    /// Build Lambda for Linux (AMD64) using Docker, updating buildState
    public func build(clean: Bool = false) async throws {
        buildState.startBuild()
        unifiedOutput.startOperation()

        // Clean if requested
        if clean {
            let cleanMsg = "🧹 Cleaning previous build artifacts...\n"
            buildState.appendOutput(cleanMsg)
            unifiedOutput.appendOutput(cleanMsg)
            do {
                let rmCmd = Rm(recursive: true, force: true, paths: buildArtifactPaths)
                _ = try await cliService.execute(
                    rmCmd,
                    workingDirectory: workingDirectory,
                    printCommand: false
                )
                let successMsg = "  ✅ Cleaned\n"
                buildState.appendOutput(successMsg)
                unifiedOutput.appendOutput(successMsg)
            } catch {
                let errorMsg = "  ❌ Clean failed: \(error)\n"
                buildState.appendOutput(errorMsg)
                unifiedOutput.appendOutput(errorMsg)
                buildState.markFailed(exitCode: 1)
                unifiedOutput.endOperation()
                throw BuildError.failed(exitCode: 1)
            }
        }

        let buildMsg = "🔨 Building Lambda for Linux (Docker)...\n"
        buildState.appendOutput(buildMsg)
        unifiedOutput.appendOutput(buildMsg)

        // Stream the build output using typed command
        let buildCmd = BuildScript.Build.lambda(target: "SwiftLambda")
        let stream = await cliService.stream(
            buildCmd,
            workingDirectory: workingDirectory,
            printCommand: false
        )

        var exitCode: Int32 = 0
        for await output in stream {
            if let code = buildState.processStreamOutput(output) {
                exitCode = code
            }
            _ = unifiedOutput.processStreamOutput(output)
        }

        if exitCode == 0 {
            buildState.markSuccess()
            unifiedOutput.appendOutput("\n✅ Build completed successfully\n")
        } else {
            buildState.markFailed(exitCode: exitCode)
            unifiedOutput.appendOutput("\n❌ Build failed with exit code \(exitCode)\n")
            unifiedOutput.endOperation()
            throw BuildError.failed(exitCode: exitCode)
        }
        unifiedOutput.endOperation()
    }

    /// Check if Lambda is already built (Linux artifacts)
    public func isLambdaBuilt() -> Bool {
        return FileManager.default.fileExists(atPath: lambdaDir) &&
               FileManager.default.fileExists(atPath: bootstrapPath) &&
               FileManager.default.fileExists(atPath: lambdaZipPath)
    }

    /// Delete build artifacts and reset build state
    public func deleteBuild() async throws {
        let rmCmd = Rm(recursive: true, force: true, paths: buildArtifactPaths)
        _ = try await cliService.execute(
            rmCmd,
            workingDirectory: workingDirectory,
            printCommand: false
        )
        buildState.clear()
    }

    // MARK: - LambdaService Protocol: Lifecycle

    /// Start Lambda container in detached mode
    public func startLambda() async throws {
        lambdaState.startLambda()
        unifiedOutput.startOperation()

        let startMsg = "🚀 Starting Lambda container...\n"
        lambdaState.appendOutput(startMsg)
        unifiedOutput.appendOutput(startMsg)

        do {
            try await startDetached(lambdaPath: nil)
            let containerMsg = "   Container: \(config.containerName)\n"
            let portMsg = "   Port: http://localhost:\(port)\n"
            lambdaState.appendOutput(containerMsg)
            lambdaState.appendOutput(portMsg)
            unifiedOutput.appendOutput(containerMsg)
            unifiedOutput.appendOutput(portMsg)
            lambdaState.markRunning()
            unifiedOutput.appendOutput("\n✅ Lambda is running\n")
        } catch {
            lambdaState.markFailed(reason: error.localizedDescription)
            unifiedOutput.appendOutput("\n❌ Lambda failed: \(error.localizedDescription)\n")
            unifiedOutput.endOperation()
            throw error
        }
        unifiedOutput.endOperation()
    }

    /// Stop Lambda container
    public func stopLambda() async throws {
        lambdaState.beginStop()
        unifiedOutput.startOperation()

        let stopMsg = "🛑 Stopping Lambda container...\n"
        lambdaState.appendOutput(stopMsg)
        unifiedOutput.appendOutput(stopMsg)

        do {
            try await dockerService.stop(container: config.containerName)
            lambdaState.markStopped()
            unifiedOutput.appendOutput("\n✅ Lambda stopped\n")
        } catch {
            // Container may already be stopped
            let warnMsg = "⚠️  Container may already be stopped\n"
            lambdaState.appendOutput(warnMsg)
            unifiedOutput.appendOutput(warnMsg)
            lambdaState.markStopped()
        }
        unifiedOutput.endOperation()
    }

    /// Start Lambda container with all services (complete flow)
    public func startWithServices() async throws {
        statusSubject.send(.starting)

        print("\n🚀 Setting up complete Lambda container environment...")

        // 1. Stop any existing Lambda container
        print("\n→ Checking for existing Lambda container...")
        do {
            try await stopLambda()
        } catch {
            print("  (No existing container to stop)")
        }

        // 2. Start services (PostgreSQL + MinIO)
        print("\n→ Starting local services...")
        try await startAllServices()

        // 3. Setup network (will connect services if needed)
        print("\n→ Setting up Docker network...")
        try await setupDockerNetwork()

        // 4. Ensure S3 bucket exists
        print("\n→ Ensuring S3 bucket exists...")
        try await minioService.createBucket(bucketName: nil)

        // 5. Start Lambda container in detached mode
        print("\n→ Starting Lambda container in background...")
        try await startLambda()

        print("\n✅ Lambda container started!")
        print("   Container: \(config.containerName)")
        print("   Port: http://localhost:\(port)")
        print("")
        print("To test: ./tools.sh local linux test")
        print("To stop: ./tools.sh local linux stop-all")

        refreshStatus()
    }

    /// Stop Lambda container and all services
    public func stopWithServices() async throws {
        statusSubject.send(.stopping)

        print("\n🛑 Stopping Lambda container and services...")

        // 1. Stop Lambda container
        print("\n→ Stopping Lambda container...")
        do {
            try await stopLambda()
        } catch {
            print("  (No container to stop)")
        }

        // 2. Stop services
        print("\n→ Stopping local services...")
        try await stopAllServices()

        print("\n✅ All services stopped")

        refreshStatus()
    }

    // MARK: - LambdaService Protocol: Testing

    /// Wait for Lambda to be ready on specified port
    public func waitForReady(maxAttempts: Int = 30) async throws {
        print("🔍 Verifying Lambda is running...")

        // Check container is running
        let isRunning = try await dockerService.containerIsRunning(name: config.containerName)
        guard isRunning else {
            throw DeployError.testFailed(message: "Lambda container '\(config.containerName)' is not running")
        }

        // Wait for Lambda to be ready on the port
        var attempts = 0
        var ready = false

        while attempts < maxAttempts && !ready {
            let portCheck = try await cliService.executeForResult(
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
            // Show container logs for debugging
            print("❌ Lambda failed to start. Checking container logs:")
            let logsResult = try await cliService.execute(
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

    /// Test Lambda endpoints using Client library
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

    // MARK: - LambdaService Protocol: Status

    /// Get the status of all services (Lambda, S3, PostgreSQL)
    public func status() async throws -> DeploymentStatus {
        // Check Lambda container
        let lambdaRunning = try await isRunning()

        // Check S3 (MinIO)
        let s3Running = try await minioService.isRunning()

        // Check PostgreSQL
        let postgresRunning = try await postgresService.isRunning()

        return DeploymentStatus(
            lambdaState: lambdaRunning ? .running : .stopped,
            s3State: s3Running ? .running : .stopped,
            postgresState: postgresRunning ? .running : .stopped
        )
    }

    /// Refresh status and publish results via Combine publishers
    public func refreshStatus() {
        let statusSubject = self.statusSubject
        let isLoadingStatusSubject = self.isLoadingStatusSubject

        isLoadingStatusSubject.send(true)
        Task {
            do {
                let newStatus = try await self.status()
                statusSubject.send(newStatus)
            } catch {
                statusSubject.send(.stopped)
            }
            isLoadingStatusSubject.send(false)
        }
    }

    // MARK: - Linux-Specific Methods (Not in Protocol)

    /// Setup Docker network for Lambda container
    public func setupDockerNetwork() async throws {
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
    }

    /// Print the Docker command to run Lambda interactively
    public func printRunCommand() async throws {
        // Check if lambda directory exists
        guard FileManager.default.fileExists(atPath: lambdaDir) else {
            print("❌ Error: lambda directory not found!")
            print("Build the Lambda first with: ./tools.sh local linux build")
            throw CLIServiceError.invalidWorkingDirectory("lambda directory not found")
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

    /// Run Lambda in interactive container (direct execution - may have TTY issues)
    public func runInteractive() async throws {
        // Check if lambda directory exists
        guard FileManager.default.fileExists(atPath: lambdaDir) else {
            print("❌ Error: lambda directory not found!")
            print("Build the Lambda first with: ./tools.sh local linux build")
            throw CLIServiceError.invalidWorkingDirectory("lambda directory not found")
        }

        print("\n✅ Starting interactive container...")
        print("(Type 'exit' to leave the container)\n")

        // Run interactive container
        var options = DockerService.RunOptions()
        options.interactive = true
        options.tty = true
        options.remove = true
        options.platform = "linux/amd64"
        options.network = config.networkName
        options.volumes = [(lambdaDir, "/var/task")]
        options.ports = [(config.hostPort, config.containerPort)]
        options.environment = getEnvironmentVariables()

        try await dockerService.run(
            image: config.swiftImage,
            command: ["bash", "-c", "cd /var/task && chmod +x bootstrap && echo '✅ Lambda ready! Run: ./bootstrap' && bash"],
            options: options
        )
    }

    /// Check if container is running
    public func isRunning() async throws -> Bool {
        return try await dockerService.containerIsRunning(name: config.containerName)
    }

    /// Start Lambda container in detached mode (for automated testing)
    public func startDetached(lambdaPath: String? = nil) async throws {
        // Ensure Docker is running
        try await dockerService.ensureDockerRunning()

        // Determine lambda path
        let effectiveLambdaDir = lambdaPath ?? lambdaDir

        // Check if lambda directory exists
        guard FileManager.default.fileExists(atPath: effectiveLambdaDir) else {
            print("❌ Error: lambda directory not found at \(effectiveLambdaDir)!")
            print("Build the Lambda first with: ./tools.sh local linux build")
            throw CLIServiceError.invalidWorkingDirectory("lambda directory not found")
        }

        // Run detached container
        var options = DockerService.RunOptions()
        options.detached = true
        options.remove = true
        options.name = config.containerName
        options.platform = "linux/amd64"
        options.network = config.networkName
        options.ports = [(config.hostPort, config.containerPort)]
        options.volumes = [(effectiveLambdaDir, "/var/task")]
        options.environment = getEnvironmentVariables()

        try await dockerService.run(
            image: config.swiftImage,
            command: ["bash", "-c", "cd /var/task && chmod +x bootstrap && exec ./bootstrap"],
            options: options
        )
    }

    // MARK: - Private Helpers

    /// Get environment variables for Lambda container (Docker network)
    public func getEnvironmentVariables() -> [String: String] {
        return createEnvironmentVariables(
            postgresService: postgresService,
            minioService: minioService,
            context: .container  // Container connects via Docker network DNS
        )
    }

    /// Connect a container to the Lambda network
    private func connectContainerToNetwork(container: String) async throws {
        // Wait a moment for container to be fully started
        try await Task.sleep(for: .seconds(1))

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
                print("⚠️  Warning: \(container) is not running. Start it with: swift run SwiftDeploy local services start-\(container == postgresService.connectionInfo.containerName ? "database" : "s3")")
            }
        } else {
            print("✓ \(container) already connected")
        }
    }

    /// Create an API client configured for local Lambda testing
    @MainActor
    private func createLocalAPIClient() -> APIClient {
        APIClient(localPort: config.hostPort)
    }

    @MainActor
    private func performLocalLambdaTests() async throws {
        let client = createLocalAPIClient()

        // Test file upload
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

        // Test list files
        print("→ Testing list files...")
        let fileList = try await client.listFiles()
        if fileList.contains("test-upload.txt") {
            print("  ✅ List files test passed (found \(fileList.count) files)")
        } else {
            print("  ❌ List files test failed: \(fileList)")
            throw DeployError.testFailed(message: "List files endpoint test failed")
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
                throw DeployError.testFailed(message: "File download endpoint test failed")
            }
        } else {
            print("  ❌ File download test failed: could not decode content")
            throw DeployError.testFailed(message: "File download endpoint test failed")
        }

        print("")

        // Test database initialization
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
    static func `default`(workingDirectory: String) -> LinuxContainerConfig {
        LinuxContainerConfig(
            containerName: "lambda-linux-container",
            swiftImage: "swift:6.2.0-amazonlinux2",
            hostPort: 8080,
            containerPort: 7000,
            networkName: "lambda-linux",
            workingDirectory: workingDirectory
        )
    }
}
