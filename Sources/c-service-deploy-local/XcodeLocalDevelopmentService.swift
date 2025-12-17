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

/// Stateless service for native macOS Xcode development workflow
/// Orchestrates Docker services, native Swift builds, and Lambda process management
public actor XcodeLocalDevelopmentService {
    private let dockerClient: DockerClient
    private let cliClient: CLIClient
    private let storageService: LocalStorageService

    private let postgresClient: PostgreSQLClient
    private let minioClient: MinIOClient
    private let dynamodbClient: DynamoDBClient

    // Lambda configuration
    private let lambdaHostPort = 8080
    private let lambdaProductName = "app-lambda"
    private let lambdaProcessPattern = "swiftlamb"  // lsof truncates process names

    // Working directory
    private let workingDirectory: String

    // MARK: - Initialization

    public init(workingDirectory: String) {
        let cliClient = CLIClient(defaultWorkingDirectory: workingDirectory)
        self.cliClient = cliClient
        let dockerClient = DockerClient(cliClient: cliClient)
        self.dockerClient = dockerClient
        self.workingDirectory = workingDirectory
        let storageService = LocalStorageService()
        self.storageService = storageService

        self.postgresClient = PostgreSQLClient(
            dockerClient: dockerClient,
            config: .xcode,
            dataDirectory: storageService.dataDirectory(for: PostgreSQLXcodeStorageKey.self)
        )
        self.minioClient = MinIOClient(
            dockerClient: dockerClient,
            networkName: "lambda-xcode",
            config: .xcode,
            dataDirectory: storageService.dataDirectory(for: MinIOXcodeStorageKey.self)
        )
        self.dynamodbClient = DynamoDBClient(
            dockerClient: dockerClient,
            config: .xcode,
            dataDirectory: storageService.dataDirectory(for: DynamoDBLocalXcodeStorageKey.self)
        )
    }

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
            print("✓ MinIO (xcode) already running")
        }

        if !(try await postgresClient.isRunning()) {
            try await postgresClient.start()
        } else {
            print("✓ PostgreSQL (xcode) already running")
        }

        if !(try await dynamodbClient.isRunning()) {
            try await dynamodbClient.start()
        } else {
            print("✓ DynamoDB Local (xcode) already running")
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
        storageService.dataDirectory(for: MinIOXcodeStorageKey.self)
    }

    /// Data directory for PostgreSQL
    public var postgresDataDirectory: String {
        storageService.dataDirectory(for: PostgreSQLXcodeStorageKey.self)
    }

    /// Data directory for DynamoDB Local
    public var dynamodbDataDirectory: String {
        storageService.dataDirectory(for: DynamoDBLocalXcodeStorageKey.self)
    }

    // MARK: - Build Operations

    /// Build Lambda for macOS (native Swift build)
    /// - Parameters:
    ///   - clean: Whether to clean build artifacts first
    ///   - output: Optional stream to receive build output
    /// - Returns: Build result with success status and output
    public func build(clean: Bool = false, output: CLIOutputStream? = nil) async throws {
        if clean {
            let cleanMsg = "🧹 Cleaning previous build artifacts...\n"
            await output?.send(.stdout(commandID: .init(), text: cleanMsg))
            do {
                _ = try await cliClient.execute(
                    SwiftCLI.Package.Clean(),
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

        let buildMsg = "🔨 Building Lambda for macOS (native)...\n"
        await output?.send(.stdout(commandID: .init(), text: buildMsg))

        let buildCommand = SwiftCLI.Build(product: lambdaProductName)
        let stream = await cliClient.stream(
            buildCommand,
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

    /// Get the path to the built executable
    public func getExecutablePath() async throws -> String {
        let showBinPathCommand = SwiftCLI.Build(product: lambdaProductName, showBinPath: true)
        let result = try await cliClient.executeForResult(
            showBinPathCommand,
            workingDirectory: workingDirectory,
            printCommand: false
        )

        guard result.isSuccess else {
            throw DeployError.commandFailed(
                command: showBinPathCommand.commandString,
                exitCode: result.exitCode,
                output: result.output
            )
        }

        let binPath = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(binPath)/\(lambdaProductName)"
    }

    /// Check if Lambda is already built (native macOS build)
    public func isLambdaBuilt() -> Bool {
        let debugDir = "\(workingDirectory)/.build"
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: debugDir) else {
            return false
        }

        for item in contents {
            let executablePath = "\(debugDir)/\(item)/debug/\(lambdaProductName)"
            if FileManager.default.fileExists(atPath: executablePath) {
                return true
            }
        }
        return false
    }

    /// Delete build artifacts
    public func deleteBuild() async throws {
        _ = try await cliClient.execute(
            SwiftCLI.Package.Clean(),
            workingDirectory: workingDirectory,
            printCommand: false
        )
    }

    // MARK: - Lambda Lifecycle

    /// Start Lambda locally (native process)
    /// - Parameter output: Optional stream to receive output
    public func startLambda(output: CLIOutputStream? = nil) async throws {
        let startMsg = "🚀 Starting Lambda locally (native)...\n"
        await output?.send(.stdout(commandID: .init(), text: startMsg))

        if !isLambdaBuilt() {
            let buildMsg = "→ Building Lambda first...\n"
            await output?.send(.stdout(commandID: .init(), text: buildMsg))
            try await build(output: output)
        }

        let executablePath = try await getExecutablePath()

        let portMsg = "→ Starting Lambda on port \(lambdaHostPort)...\n"
        await output?.send(.stdout(commandID: .init(), text: portMsg))

        var env = getLambdaEnvironmentVariables()
        env["LOCAL_LAMBDA_PORT"] = "\(lambdaHostPort)"

        let envVars = env.map { "\($0.key)=\($0.value)" }.joined(separator: " ")

        _ = try await cliClient.execute(
            Sh(command: "\(envVars) \(executablePath) > /tmp/lambda.log 2>&1 & echo $!"),
            workingDirectory: workingDirectory,
            printCommand: false,
            output: output
        )

        let waitMsg = "→ Waiting for Lambda to start...\n"
        await output?.send(.stdout(commandID: .init(), text: waitMsg))
        try await Task.sleep(for: .seconds(3))

        if await isPortInUse(lambdaHostPort) {
            let successMsg = "   Test with: ./tools.sh local xcode test\n   Stop with: ./tools.sh local xcode stop\n"
            await output?.send(.stdout(commandID: .init(), text: successMsg))
            let doneMsg = "\n✅ Lambda is running\n"
            await output?.send(.stdout(commandID: .init(), text: doneMsg))
        } else {
            let errorMsg = "\n❌ Lambda failed to start on port \(lambdaHostPort)\n"
            await output?.send(.stderr(commandID: .init(), text: errorMsg))
            throw DeployError.testFailed(message: "Lambda failed to start on port \(lambdaHostPort)")
        }
    }

    /// Stop locally running Lambda
    /// - Parameter output: Optional stream to receive output
    public func stopLambda(output: CLIOutputStream? = nil) async throws {
        let stopMsg = "🛑 Stopping Lambda...\n"
        await output?.send(.stdout(commandID: .init(), text: stopMsg))

        let pids = await getProcessIDsOnPort(lambdaHostPort)

        if !pids.isEmpty {
            let killMsg = "→ Killing process(es): \(pids.joined(separator: ", "))...\n"
            await output?.send(.stdout(commandID: .init(), text: killMsg))

            for pid in pids {
                let killResult = try await cliClient.executeForResult(
                    Kill(pid: pid),
                    printCommand: false,
                    output: output
                )

                if !killResult.isSuccess {
                    let errorMsg = "❌ Failed to kill process \(pid)\n"
                    await output?.send(.stderr(commandID: .init(), text: errorMsg))
                    throw DeployError.commandFailed(
                        command: Kill(pid: pid).commandString,
                        exitCode: killResult.exitCode,
                        output: killResult.output
                    )
                }
            }

            let stoppedMsg = "Stopped \(pids.count) process\(pids.count == 1 ? "" : "es")\n"
            await output?.send(.stdout(commandID: .init(), text: stoppedMsg))
            let doneMsg = "\n✅ Lambda stopped\n"
            await output?.send(.stdout(commandID: .init(), text: doneMsg))
        } else {
            let notFoundMsg = "⚠️  No Lambda process found on port \(lambdaHostPort)\n"
            await output?.send(.stdout(commandID: .init(), text: notFoundMsg))
        }
    }

    /// Start Lambda with all services (complete flow)
    /// - Parameter output: Optional stream to receive output
    public func startWithServices(output: CLIOutputStream? = nil) async throws {
        print("\n📦 Starting local services...")
        try await startAllServices()

        try await setupNetworkAndBucket()

        try await startLambda(output: output)
    }

    /// Setup Docker network and S3 bucket for Xcode mode
    private func setupNetworkAndBucket() async throws {
        let networkName = "lambda-xcode"

        if !(try await dockerClient.networkExists(name: networkName)) {
            print("→ Creating Docker network: \(networkName)")
            try await dockerClient.createNetwork(name: networkName)
        }

        let minioContainer = minioClient.minioContainerName
        let isConnected = try await dockerClient.isConnectedToNetwork(
            container: minioContainer,
            network: networkName
        )
        if !isConnected {
            print("→ Connecting \(minioContainer) to \(networkName)")
            try await dockerClient.connectToNetwork(container: minioContainer, network: networkName)
        }

        try await minioClient.createBucket(bucketName: nil)
    }

    /// Stop Lambda and all services (complete flow)
    /// - Parameter output: Optional stream to receive output
    public func stopWithServices(output: CLIOutputStream? = nil) async throws {
        try await stopLambda(output: output)

        print("\n📦 Stopping local services...")
        try await stopAllServices()
    }

    // MARK: - Testing

    /// Wait for Lambda to be ready on specified port
    public func waitForReady(maxAttempts: Int = 30) async throws {
        print("🔍 Verifying Lambda is running...")

        var attempts = 0
        var ready = false

        while attempts < maxAttempts && !ready {
            if await isPortInUse(lambdaHostPort) {
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
            throw DeployError.testFailed(message: "Lambda failed to be ready on port \(lambdaHostPort) after \(maxAttempts) seconds")
        }

        print("  ✅ Lambda is running and ready")
    }

    /// Test local Lambda endpoints using Client library
    public func testLambda() async throws {
        print("\n🧪 Testing local Lambda on port \(lambdaHostPort)...")
        print("")

        do {
            try await performLocalLambdaTests()
        } catch let error as APIError {
            throw DeployError.testFailed(message: "API Error: \(error.localizedDescription)")
        }

        print("")
        print("✅ All local Lambda tests passed!")
    }

    // MARK: - Configuration

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

    // MARK: - Status

    /// Get the status of all services (Lambda, S3, PostgreSQL, DynamoDB)
    public func status() async throws -> DeploymentStatus {
        let lambdaRunning = await isLambdaRunning()
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

    /// Check if Lambda is running (native process on port, not Docker)
    public func isLambdaRunning() async -> Bool {
        let output = await getPortInfo(lambdaHostPort)
        guard !output.isEmpty else { return false }

        let lines = output.components(separatedBy: "\n")
        for line in lines {
            let lowercased = line.lowercased()
            if lowercased.contains(lambdaProcessPattern) && !lowercased.contains("docker") {
                return true
            }
        }
        return false
    }

    // MARK: - Private Helpers

    private func isPortInUse(_ port: Int) async -> Bool {
        let output = await getPortInfo(port)
        return !output.isEmpty
    }

    private func getPortInfo(_ port: Int) async -> String {
        do {
            let result = try await cliClient.executeForResult(
                Lsof(port: ":\(port)"),
                printCommand: false
            )
            guard result.isSuccess else { return "" }
            return result.stdout
        } catch {
            return ""
        }
    }

    private func getProcessIDsOnPort(_ port: Int) async -> [String] {
        do {
            let result = try await cliClient.executeForResult(
                Lsof(port: ":\(port)", pidOnly: true),
                printCommand: false
            )
            guard result.isSuccess && !result.stdout.isEmpty else {
                return []
            }
            let currentPID = String(ProcessInfo.processInfo.processIdentifier)
            return result.stdout
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .split(separator: "\n")
                .map(String.init)
                .filter { !$0.isEmpty && $0 != currentPID }
        } catch {
            return []
        }
    }

    private func getLambdaEnvironmentVariables() -> [String: String] {
        return createEnvironmentVariables(
            postgresClient: postgresClient,
            minioClient: minioClient,
            dynamodbClient: dynamodbClient,
            context: .xcode
        )
    }

    private func performLocalLambdaTests() async throws {
        let client = await MainActor.run { APIClient(localPort: lambdaHostPort, serviceName: "Local Xcode (Native)") }

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

// MARK: - Storage Keys

/// Storage key for app configuration file
public struct AppConfigFileKey: StorageFileKey {
    public static let filename = "swiftLambdaDemo.json"
}

/// Result of a local build operation
public struct LocalBuildResult: Sendable {
    public let success: Bool
    public let exitCode: Int32
    public let output: String
}
