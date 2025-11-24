import Client
import Foundation

/// Service for managing local development environment (Docker services, testing)
public actor LocalDevelopmentService {
    private let dockerService: DockerService
    private let cliService: CLIService

    // Extracted services
    private let postgresService: PostgreSQLService
    private let minioService: MinIOService
    private let lambdaContainerService: LambdaContainerService

    // Lambda configuration
    private let lambdaHostPort = 8080

    // Working directory
    private let workingDirectory: String

    // Public accessors for configuration
    nonisolated public var port: Int { lambdaHostPort }

    /// Get the local Lambda endpoint URL
    nonisolated public var localEndpoint: String {
        "http://localhost:\(lambdaHostPort)/invoke"
    }

    public init(workingDirectory: String) {
        self.dockerService = DockerService()
        self.cliService = CLIService.shared
        self.workingDirectory = workingDirectory

        // Initialize extracted services
        self.postgresService = PostgreSQLService(
            dockerService: dockerService,
            workingDirectory: workingDirectory
        )
        self.minioService = MinIOService(
            dockerService: dockerService,
            networkName: "lambda-local"
        )

        // Initialize Lambda container service
        let containerConfig = LambdaContainerConfig(
            containerName: "lambda-test-container",
            swiftImage: "swift:6.2.0-amazonlinux2",
            hostPort: 8080,
            containerPort: 7000,
            networkName: "lambda-local",
            workingDirectory: workingDirectory
        )
        self.lambdaContainerService = LambdaContainerService(
            dockerService: dockerService,
            cliService: cliService,
            postgresService: postgresService,
            minioService: minioService,
            config: containerConfig
        )
    }

    // MARK: - Service Management

    /// Start all services (PostgreSQL + MinIO)
    public func startAllServices() async throws {
        try await stopAllServices()
        try await minioService.start()
        try await postgresService.start()
    }

    /// Stop all services
    public func stopAllServices() async throws {
        try await minioService.stop()
        try await postgresService.stop()
    }

    /// Start MinIO S3 service
    public func startS3() async throws {
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
        try await postgresService.start()
    }

    /// Stop PostgreSQL database
    public func stopDatabase() async throws {
        try await postgresService.stop()
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

    /// Start Lambda locally with services (complete flow)
    public func startLambdaWithServices() async throws {
        // Start services first
        print("\n📦 Starting local services...")
        try await startAllServices()

        // Then start Lambda
        try await startLambdaLocally()
    }

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

    /// Stop Lambda and services (complete flow)
    public func stopLambdaWithServices() async throws {
        // Stop Lambda first
        try await stopLambdaLocally()

        // Then stop services
        print("\n📦 Stopping local services...")
        try await stopAllServices()
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
            // Split PIDs by newlines in case there are multiple processes
            let pids = lsofResult.stdout
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .split(separator: "\n")
                .map(String.init)
                .filter { !$0.isEmpty }

            guard !pids.isEmpty else {
                print("⚠️  No Lambda process found on port \(lambdaHostPort)")
                return
            }

            print("→ Killing process(es): \(pids.joined(separator: ", "))...")

            // Kill each process
            for pid in pids {
                let killResult = try await cliService.execute(
                    command: "kill",
                    arguments: [pid],
                    printCommand: false
                )

                if !killResult.isSuccess {
                    throw CLIError.commandFailed(
                        command: "kill",
                        exitCode: killResult.exitCode,
                        stderr: killResult.stderr
                    )
                }
            }

            print("✅ Lambda stopped (\(pids.count) process\(pids.count == 1 ? "" : "es"))")
        } else {
            print("⚠️  No Lambda process found on port \(lambdaHostPort)")
        }
    }

    // MARK: - Lambda Container Testing

    /// Setup Docker network for Lambda container testing
    public func setupLambdaNetwork() async throws {
        try await lambdaContainerService.setupNetwork()
    }

    /// Run Lambda in interactive Linux container (complete setup)
    /// This command does everything: stops existing containers, starts services, sets up network, runs container
    public func runLambdaContainer() async throws {
        print("\n🚀 Setting up complete Lambda container environment...")

        // 1. Stop any existing Lambda container
        print("\n→ Checking for existing Lambda container...")
        do {
            try await lambdaContainerService.stop()
        } catch {
            // Container might not exist, which is fine
            print("  (No existing container to stop)")
        }

        // 2. Start services (PostgreSQL + MinIO)
        print("\n→ Starting local services...")
        try await startAllServices()

        // 3. Setup network (will connect services if needed)
        print("\n→ Setting up Docker network...")
        try await lambdaContainerService.setupNetwork()

        // 4. Show container launch instructions
        print("\n✅ Environment ready! To start the Lambda container, run:\n")
        try await lambdaContainerService.printRunCommand()
        print("")
    }

    /// Stop Lambda container and all services (complete teardown)
    public func stopLambdaContainerAndServices() async throws {
        print("\n🛑 Stopping Lambda container and services...")

        // 1. Stop Lambda container
        print("\n→ Stopping Lambda container...")
        do {
            try await lambdaContainerService.stop()
        } catch {
            print("  (No container to stop)")
        }

        // 2. Stop services
        print("\n→ Stopping local services...")
        try await stopAllServices()

        print("\n✅ All services stopped")
    }

    /// Run Lambda in detached mode (for automated testing)
    public func startLambdaContainerDetached(lambdaPath: String? = nil) async throws {
        try await lambdaContainerService.startDetached(lambdaPath: lambdaPath)
    }

    /// Stop Lambda container
    public func stopLambdaContainer() async throws {
        try await lambdaContainerService.stop()
    }

    /// Wait for Lambda to be ready on specified port
    public func waitForLambdaReady(maxAttempts: Int = 30) async throws {
        try await lambdaContainerService.waitForReady(maxAttempts: maxAttempts)
    }

    /// Get standard Lambda environment variables for local testing
    private func getLambdaEnvironmentVariables() -> [String: String] {
        return lambdaContainerService.getEnvironmentVariables()
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

}
