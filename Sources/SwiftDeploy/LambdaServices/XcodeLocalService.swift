import CLIKit
import Client
import Combine
import Foundation
import LocalStorageService

/// Service for native macOS Xcode development workflow (fast iteration)
/// Uses native Swift toolchain for builds and direct process execution
@MainActor
public class XcodeLocalService: LocalService {
    private let dockerService: DockerService
    public let cliService: CLIService
    private let storageService: LocalStorageService

    private let postgresService: PostgreSQLService
    private let minioService: MinIOService
    private let dynamodbService: DynamoDBLocalService

    // Lambda configuration
    private let lambdaHostPort = 8080
    private let lambdaProductName = "SwiftLambda"
    private let lambdaProcessPattern = "swiftlamb"  // lsof truncates process names

    // Working directory
    private let workingDirectory: String

    // MARK: - Combine Publishers

    private let statusSubject = CurrentValueSubject<DeploymentStatus, Never>(
        .stopped
    )
    private let isLoadingStatusSubject = CurrentValueSubject<Bool, Never>(false)

    /// Flag to prevent refreshStatus from overwriting transitional states (starting/stopping)
    private var isTransitioning = false

    public var statusPublisher: AnyPublisher<DeploymentStatus, Never> {
        statusSubject.eraseToAnyPublisher()
    }

    public var isLoadingStatusPublisher: AnyPublisher<Bool, Never> {
        isLoadingStatusSubject.eraseToAnyPublisher()
    }

    // MARK: - Build State

    public let buildState = BuildState()

    // MARK: - Lambda State

    public let lambdaState = LambdaState()

    // MARK: - LambdaService Protocol

    public static let persistenceKey = "localXcode"

    public static let displayName = "Local Xcode (Native)"

    public static let detailText = "Native macOS build - fast iteration, best for development"

    public var port: Int { lambdaHostPort }

    public var endpoint: String {
        "http://localhost:\(lambdaHostPort)/invoke"
    }

    public var endpointLabel: String { "Local Lambda Endpoint" }

    public var endpointHelpText: String {
        "Make sure local Lambda is running on port \(lambdaHostPort)"
    }

    public var apiClient: APIClient {
        APIClient(localPort: lambdaHostPort, serviceName: Self.displayName)
    }

    public var isConfigured: Bool { true }

    public init(workingDirectory: String) {
        let cliService = CLIService(defaultWorkingDirectory: workingDirectory)
        self.cliService = cliService
        self.dockerService = DockerService(cliService: cliService)
        self.workingDirectory = workingDirectory
        self.storageService = LocalStorageService()

        self.postgresService = PostgreSQLService(
            dockerService: dockerService,
            config: .xcode,
            storageService: storageService
        )
        self.minioService = MinIOService(
            dockerService: dockerService,
            networkName: "lambda-xcode",
            config: .xcode,
            storageService: storageService
        )
        self.dynamodbService = DynamoDBLocalService(
            dockerService: dockerService,
            config: .xcode,
            storageService: storageService
        )

        // Check for existing build artifacts
        refreshBuildStatus()
    }

    // MARK: - Service Management

    /// Start all services (PostgreSQL + MinIO + DynamoDB)
    /// Services persist between mode switches - only starts if not already running
    public func startAllServices() async throws {
        try await dockerService.ensureDockerRunning()

        // Only start services if not already running (persist between sessions)
        if !(try await minioService.isRunning()) {
            try await minioService.start()
        } else {
            print("✓ MinIO (xcode) already running")
        }

        if !(try await postgresService.isRunning()) {
            try await postgresService.start()
        } else {
            print("✓ PostgreSQL (xcode) already running")
        }

        if !(try await dynamodbService.isRunning()) {
            try await dynamodbService.start()
        } else {
            print("✓ DynamoDB Local (xcode) already running")
        }
    }

    /// Stop all services
    public func stopAllServices() async throws {
        try await minioService.stop()
        try await postgresService.stop()
        try await dynamodbService.stop()
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

    /// Start DynamoDB Local
    public func startDynamoDB() async throws {
        try await dockerService.ensureDockerRunning()
        try await dynamodbService.start()
    }

    /// Stop DynamoDB Local
    public func stopDynamoDB() async throws {
        try await dynamodbService.stop()
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

    // MARK: - LambdaService Protocol: Build

    /// Build Lambda for macOS (native Swift build), updating buildState
    /// - Parameters:
    ///   - clean: Whether to clean build artifacts first
    ///   - output: Optional client-owned stream to receive output (in addition to global stream)
    public func build(clean: Bool = false, output: CLIOutputStream? = nil) async throws {
        buildState.startBuild()

        // Clean if requested
        if clean {
            let cleanMsg = "🧹 Cleaning previous build artifacts...\n"
            buildState.appendOutput(cleanMsg)
            await output?.send(.stdout(commandID: .init(), text: cleanMsg))
            do {
                _ = try await cliService.execute(
                    SwiftCLI.Package.Clean(),
                    workingDirectory: workingDirectory,
                    printCommand: false,
                    output: output
                )
                let successMsg = "  ✅ Cleaned\n"
                buildState.appendOutput(successMsg)
                await output?.send(.stdout(commandID: .init(), text: successMsg))
            } catch {
                let errorMsg = "  ❌ Clean failed: \(error)\n"
                buildState.appendOutput(errorMsg)
                await output?.send(.stderr(commandID: .init(), text: errorMsg))
                buildState.markFailed(exitCode: 1)
                throw BuildError.failed(exitCode: 1)
            }
        }

        let buildMsg = "🔨 Building Lambda for macOS (native)...\n"
        buildState.appendOutput(buildMsg)
        await output?.send(.stdout(commandID: .init(), text: buildMsg))

        // Stream the build output
        let buildCommand = SwiftCLI.Build(product: lambdaProductName)
        let stream = await cliService.stream(
            buildCommand,
            workingDirectory: workingDirectory,
            printCommand: false,
            output: output
        )

        var exitCode: Int32 = 0
        for await streamOutput in stream {
            if let code = buildState.processStreamOutput(streamOutput) {
                exitCode = code
            }
        }

        if exitCode == 0 {
            buildState.markSuccess()
        } else {
            buildState.markFailed(exitCode: exitCode)
            throw BuildError.failed(exitCode: exitCode)
        }
    }

    /// Get the path to the built executable
    private func getExecutablePath() async throws -> String {
        // Get the bin path from Swift build
        let showBinPathCommand = SwiftCLI.Build(product: lambdaProductName, showBinPath: true)
        let result = try await cliService.executeForResult(
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
        // Check synchronously using a known path pattern
        // The actual architecture-specific path is determined at runtime
        let debugDir = "\(workingDirectory)/.build"
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: debugDir) else {
            return false
        }

        // Look for any architecture directory containing SwiftLambda
        for item in contents {
            let executablePath = "\(debugDir)/\(item)/debug/\(lambdaProductName)"
            if FileManager.default.fileExists(atPath: executablePath) {
                return true
            }
        }
        return false
    }

    /// Delete build artifacts and reset build state
    public func deleteBuild() async throws {
        _ = try await cliService.execute(
            SwiftCLI.Package.Clean(),
            workingDirectory: workingDirectory,
            printCommand: false
        )
        buildState.clear()
    }

    // MARK: - LambdaService Protocol: Lifecycle

    /// Start Lambda locally (native process)
    /// - Parameter output: Optional client-owned stream to receive output (in addition to global stream)
    public func startLambda(output: CLIOutputStream? = nil) async throws {
        lambdaState.startLambda()

        let startMsg = "🚀 Starting Lambda locally (native)...\n"
        lambdaState.appendOutput(startMsg)
        await output?.send(.stdout(commandID: .init(), text: startMsg))

        // Build Lambda if not already built
        if !isLambdaBuilt() {
            let buildMsg = "→ Building Lambda first...\n"
            lambdaState.appendOutput(buildMsg)
            await output?.send(.stdout(commandID: .init(), text: buildMsg))
            try await build(output: output)
        }

        // Get the built executable path
        let executablePath = try await getExecutablePath()

        // Start Lambda in background with environment variables
        let portMsg = "→ Starting Lambda on port \(lambdaHostPort)...\n"
        lambdaState.appendOutput(portMsg)
        await output?.send(.stdout(commandID: .init(), text: portMsg))

        var env = getLambdaEnvironmentVariables()
        env["LOCAL_LAMBDA_PORT"] = "\(lambdaHostPort)"

        // Build environment variable string for shell
        let envVars = env.map { "\($0.key)=\($0.value)" }.joined(separator: " ")

        // Run in background using nohup
        _ = try await cliService.execute(
            Sh(command: "\(envVars) \(executablePath) > /tmp/lambda.log 2>&1 & echo $!"),
            workingDirectory: workingDirectory,
            printCommand: false,
            output: output
        )

        // Wait a bit for Lambda to start
        let waitMsg = "→ Waiting for Lambda to start...\n"
        lambdaState.appendOutput(waitMsg)
        await output?.send(.stdout(commandID: .init(), text: waitMsg))
        try await Task.sleep(for: .seconds(3))

        // Check if it's running
        if await isPortInUse(lambdaHostPort) {
            let successMsg = "   Test with: ./tools.sh local xcode test\n   Stop with: ./tools.sh local xcode stop\n"
            lambdaState.appendOutput(successMsg)
            await output?.send(.stdout(commandID: .init(), text: successMsg))
            lambdaState.markRunning()
            let doneMsg = "\n✅ Lambda is running\n"
            await output?.send(.stdout(commandID: .init(), text: doneMsg))
        } else {
            let failMsg = "Failed to start on port \(lambdaHostPort)"
            lambdaState.markFailed(reason: failMsg)
            let errorMsg = "\n❌ Lambda failed: \(failMsg)\n"
            await output?.send(.stderr(commandID: .init(), text: errorMsg))
            throw DeployError.testFailed(message: "Lambda failed to start on port \(lambdaHostPort)")
        }
    }

    /// Stop locally running Lambda
    /// - Parameter output: Optional client-owned stream to receive output (in addition to global stream)
    public func stopLambda(output: CLIOutputStream? = nil) async throws {
        lambdaState.beginStop()

        let stopMsg = "🛑 Stopping Lambda...\n"
        lambdaState.appendOutput(stopMsg)
        await output?.send(.stdout(commandID: .init(), text: stopMsg))

        // Find process on port
        let pids = await getProcessIDsOnPort(lambdaHostPort)

        if !pids.isEmpty {
            let killMsg = "→ Killing process(es): \(pids.joined(separator: ", "))...\n"
            lambdaState.appendOutput(killMsg)
            await output?.send(.stdout(commandID: .init(), text: killMsg))

            // Kill each process
            for pid in pids {
                let killResult = try await cliService.executeForResult(
                    Kill(pid: pid),
                    printCommand: false,
                    output: output
                )

                if !killResult.isSuccess {
                    let failMsg = "Failed to kill process \(pid)"
                    lambdaState.markFailed(reason: failMsg)
                    let errorMsg = "❌ \(failMsg)\n"
                    await output?.send(.stderr(commandID: .init(), text: errorMsg))
                    throw DeployError.commandFailed(
                        command: Kill(pid: pid).commandString,
                        exitCode: killResult.exitCode,
                        output: killResult.output
                    )
                }
            }

            let stoppedMsg = "Stopped \(pids.count) process\(pids.count == 1 ? "" : "es")\n"
            lambdaState.appendOutput(stoppedMsg)
            await output?.send(.stdout(commandID: .init(), text: stoppedMsg))
            lambdaState.markStopped()
            let doneMsg = "\n✅ Lambda stopped\n"
            await output?.send(.stdout(commandID: .init(), text: doneMsg))
        } else {
            let notFoundMsg = "⚠️  No Lambda process found on port \(lambdaHostPort)\n"
            lambdaState.appendOutput(notFoundMsg)
            await output?.send(.stdout(commandID: .init(), text: notFoundMsg))
            lambdaState.markStopped()
        }
    }

    /// Start Lambda with all services (complete flow)
    /// - Parameter output: Optional client-owned stream to receive output (in addition to global stream)
    public func startWithServices(output: CLIOutputStream? = nil) async throws {
        isTransitioning = true
        defer { isTransitioning = false }

        statusSubject.send(.starting)

        // Start services first
        print("\n📦 Starting local services...")
        try await startAllServices()

        // Setup network and bucket for Xcode mode
        try await setupNetworkAndBucket()

        // Then start Lambda
        try await startLambda(output: output)

        refreshStatus()
    }

    /// Setup Docker network and S3 bucket for Xcode mode
    private func setupNetworkAndBucket() async throws {
        let networkName = "lambda-xcode"

        // Create network if it doesn't exist
        if !(try await dockerService.networkExists(name: networkName)) {
            print("→ Creating Docker network: \(networkName)")
            try await dockerService.createNetwork(name: networkName)
        }

        // Connect MinIO to network (needed for bucket creation via aws-cli container)
        let minioContainer = minioService.minioContainerName
        let isConnected = try await dockerService.isConnectedToNetwork(
            container: minioContainer,
            network: networkName
        )
        if !isConnected {
            print("→ Connecting \(minioContainer) to \(networkName)")
            try await dockerService.connectToNetwork(container: minioContainer, network: networkName)
        }

        // Create bucket if needed
        try await minioService.createBucket(bucketName: nil)
    }

    /// Stop Lambda and all services (complete flow)
    /// - Parameter output: Optional client-owned stream to receive output (in addition to global stream)
    public func stopWithServices(output: CLIOutputStream? = nil) async throws {
        isTransitioning = true
        defer { isTransitioning = false }

        statusSubject.send(.stopping)

        // Stop Lambda first
        try await stopLambda(output: output)

        // Then stop services
        print("\n📦 Stopping local services...")
        try await stopAllServices()

        refreshStatus()
    }

    /// Start services if not already running, then refresh status
    /// Sets isTransitioning early to prevent refreshStatus from overwriting .starting state
    public func startIfNecessary() async {
        print("🔄 startIfNecessary called")

        // Set transitioning flag BEFORE checking status to prevent race with refreshStatus
        isTransitioning = true

        do {
            let currentStatus = try await status()
            print("🔄 Lambda state: \(currentStatus.lambdaState), S3: \(currentStatus.s3State), Postgres: \(currentStatus.postgresState), DynamoDB: \(currentStatus.dynamodbState)")

            // Start if any service is stopped
            let anyServiceStopped = currentStatus.lambdaState == .stopped ||
                                    currentStatus.s3State == .stopped ||
                                    currentStatus.postgresState == .stopped ||
                                    currentStatus.dynamodbState == .stopped

            if anyServiceStopped {
                print("🔄 Starting services (some are stopped)...")
                // startWithServices will also set isTransitioning, but that's fine
                try await startWithServices()
            } else {
                print("🔄 All services already running, skipping start")
                isTransitioning = false
                refreshStatus()
            }
        } catch {
            print("⚠️ Failed to start services: \(error)")
            isTransitioning = false
            refreshStatus()
        }
    }

    // MARK: - LambdaService Protocol: Testing

    /// Wait for Lambda to be ready on specified port
    public func waitForReady(maxAttempts: Int = 30) async throws {
        print("🔍 Verifying Lambda is running...")

        // Wait for Lambda to be ready on the port
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
    /// - Parameter sourcePath: Optional path to the config file. If nil, uses "swiftLambdaDemo.json" in current directory
    public func copyConfig(sourcePath: String? = nil) async throws {
        print("\n📝 Copying runtime config file...")

        let storageService = LocalStorageService()

        // Ensure base directory exists
        try storageService.ensureDirectoryExists(at: storageService.baseDataDirectory)

        // Copy swiftLambdaDemo.json (runtime app config)
        let appConfigSource = sourcePath ?? AppConfigFileKey.filename
        let appConfigDest = storageService.filePath(for: AppConfigFileKey.self)

        guard FileManager.default.fileExists(atPath: appConfigSource) else {
            throw CLIServiceError.invalidWorkingDirectory("App config file not found at: \(appConfigSource)")
        }

        if FileManager.default.fileExists(atPath: appConfigDest) {
            try FileManager.default.removeItem(atPath: appConfigDest)
        }
        try FileManager.default.copyItem(atPath: appConfigSource, toPath: appConfigDest)
        print("  ✓ Runtime config: \(appConfigDest)")

        print("\n✅ Runtime config copied to \(storageService.baseDataDirectory)/")
    }

    // MARK: - LambdaService Protocol: Status

    /// Get the status of all services (Lambda, S3, PostgreSQL, DynamoDB)
    public func status() async throws -> DeploymentStatus {
        // Check Lambda (native process on port)
        let lambdaRunning = await isLambdaRunning()

        // Check S3 (MinIO)
        let s3Running = try await minioService.isRunning()

        // Check PostgreSQL
        let postgresRunning = try await postgresService.isRunning()

        // Check DynamoDB Local
        let dynamodbRunning = try await dynamodbService.isRunning()

        return DeploymentStatus(
            lambdaState: lambdaRunning ? .running : .stopped,
            s3State: s3Running ? .running : .stopped,
            postgresState: postgresRunning ? .running : .stopped,
            dynamodbState: dynamodbRunning ? .running : .stopped
        )
    }

    /// Refresh status and publish results via Combine publishers
    /// Skips refresh if currently in a transition (starting/stopping) to avoid overwriting transitional states
    public func refreshStatus() {
        // Don't overwrite transitional states
        guard !isTransitioning else { return }

        let statusSubject = self.statusSubject
        let isLoadingStatusSubject = self.isLoadingStatusSubject

        isLoadingStatusSubject.send(true)
        Task {
            do {
                let newStatus = try await self.status()
                statusSubject.send(newStatus)

                // Sync lambdaState with actual running state (for app restart scenarios)
                if newStatus.lambdaState == .running && lambdaState.status == .stopped {
                    lambdaState.setRunning()
                } else if newStatus.lambdaState == .stopped && lambdaState.status == .running {
                    lambdaState.clear()
                }
            } catch {
                statusSubject.send(.stopped)
            }
            isLoadingStatusSubject.send(false)
        }
    }

    /// Check if Lambda is running (native process on port, not Docker)
    private func isLambdaRunning() async -> Bool {
        let output = await getPortInfo(lambdaHostPort)
        guard !output.isEmpty else { return false }

        // Check if there's a native Lambda process (not Docker)
        // Docker processes show as "com.docke" or "docker" in lsof output
        let lines = output.components(separatedBy: "\n")
        for line in lines {
            let lowercased = line.lowercased()
            // Look for Lambda process, exclude Docker
            if lowercased.contains(lambdaProcessPattern) && !lowercased.contains("docker") {
                return true
            }
        }
        return false
    }

    // MARK: - Private Helpers

    /// Check if any process is using the specified port
    private func isPortInUse(_ port: Int) async -> Bool {
        let output = await getPortInfo(port)
        return !output.isEmpty
    }

    /// Get lsof output for processes using the specified port
    private func getPortInfo(_ port: Int) async -> String {
        do {
            let result = try await cliService.executeForResult(
                Lsof(port: ":\(port)"),
                printCommand: false
            )
            guard result.isSuccess else { return "" }
            return result.stdout
        } catch {
            return ""
        }
    }

    /// Get PIDs of processes using the specified port (excluding current process)
    private func getProcessIDsOnPort(_ port: Int) async -> [String] {
        do {
            let result = try await cliService.executeForResult(
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

    /// Get standard Lambda environment variables for local testing (native macOS process)
    private func getLambdaEnvironmentVariables() -> [String: String] {
        return createEnvironmentVariables(
            postgresService: postgresService,
            minioService: minioService,
            dynamodbService: dynamodbService,
            context: .xcode  // Native process connects via localhost
        )
    }

    /// Create an API client configured for local Lambda testing
    @MainActor
    private func createLocalAPIClient() -> APIClient {
        APIClient(localPort: lambdaHostPort, serviceName: Self.displayName)
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

// MARK: - Storage Keys

/// Storage key for app configuration file
public struct AppConfigFileKey: StorageFileKey {
    public static let filename = "swiftLambdaDemo.json"
}
