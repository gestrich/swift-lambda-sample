import CLIKit
import Client
import Combine
import Foundation
import LocalStorageService

/// Service for native macOS Xcode development workflow (fast iteration)
/// Uses native Swift toolchain for builds and direct process execution
@MainActor
public class XcodeLocalService: LambdaService, LocalDockerServicesProvider, LocalBuildProvider {
    private let dockerService: DockerService
    private let cliService: CLIService
    private let storageService: LocalStorageService

    private let postgresService: PostgreSQLService
    private let minioService: MinIOService

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

    public static let persistenceKey = "localXcode"

    public var port: Int { lambdaHostPort }

    public var endpoint: String {
        "http://localhost:\(lambdaHostPort)/invoke"
    }

    public var endpointLabel: String { "Local Lambda Endpoint" }

    public var endpointHelpText: String {
        "Make sure local Lambda is running on port \(lambdaHostPort)"
    }

    public var apiClient: APIClient {
        APIClient(localPort: lambdaHostPort)
    }

    public var isConfigured: Bool { true }

    public init(workingDirectory: String) {
        self.dockerService = DockerService()
        self.cliService = CLIService.shared
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
            print("✓ MinIO (xcode) already running")
        }

        if !(try await postgresService.isRunning()) {
            try await postgresService.start()
        } else {
            print("✓ PostgreSQL (xcode) already running")
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
        storageService.dataDirectory(for: MinIOXcodeStorageKey.self)
    }

    /// Data directory for PostgreSQL
    public var postgresDataDirectory: String {
        storageService.dataDirectory(for: PostgreSQLXcodeStorageKey.self)
    }

    // MARK: - LambdaService Protocol: Build

    /// Build Lambda for macOS (native Swift build), updating buildState
    public func build(clean: Bool = false) async throws {
        buildState.startBuild()
        unifiedOutput.startOperation()

        // Clean if requested
        if clean {
            let cleanMsg = "🧹 Cleaning previous build artifacts...\n"
            buildState.appendOutput(cleanMsg)
            unifiedOutput.appendOutput(cleanMsg)
            do {
                _ = try await cliService.execute(
                    SwiftCLI.Package.Clean(),
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

        let buildMsg = "🔨 Building Lambda for macOS (native)...\n"
        buildState.appendOutput(buildMsg)
        unifiedOutput.appendOutput(buildMsg)

        // Stream the build output
        let buildCommand = SwiftCLI.Build(product: lambdaProductName)
        let stream = await cliService.stream(
            buildCommand,
            workingDirectory: workingDirectory,
            printCommand: false
        )

        var exitCode: Int32 = 0
        for await output in stream {
            // Process for both build state and unified output
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
                stderr: result.stderr
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
    public func startLambda() async throws {
        lambdaState.startLambda()
        unifiedOutput.startOperation()

        let startMsg = "🚀 Starting Lambda locally (native)...\n"
        lambdaState.appendOutput(startMsg)
        unifiedOutput.appendOutput(startMsg)

        // Build Lambda if not already built
        if !isLambdaBuilt() {
            let buildMsg = "→ Building Lambda first...\n"
            lambdaState.appendOutput(buildMsg)
            unifiedOutput.appendOutput(buildMsg)
            try await build()
        }

        // Get the built executable path
        let executablePath = try await getExecutablePath()

        // Start Lambda in background with environment variables
        let portMsg = "→ Starting Lambda on port \(lambdaHostPort)...\n"
        lambdaState.appendOutput(portMsg)
        unifiedOutput.appendOutput(portMsg)

        var env = getLambdaEnvironmentVariables()
        env["LOCAL_LAMBDA_PORT"] = "\(lambdaHostPort)"

        // Build environment variable string for shell
        let envVars = env.map { "\($0.key)=\($0.value)" }.joined(separator: " ")

        // Run in background using nohup
        _ = try await cliService.execute(
            Sh(command: "\(envVars) \(executablePath) > /tmp/lambda.log 2>&1 & echo $!"),
            workingDirectory: workingDirectory,
            printCommand: false
        )

        // Wait a bit for Lambda to start
        let waitMsg = "→ Waiting for Lambda to start...\n"
        lambdaState.appendOutput(waitMsg)
        unifiedOutput.appendOutput(waitMsg)
        try await Task.sleep(for: .seconds(3))

        // Check if it's running
        if await isPortInUse(lambdaHostPort) {
            let successMsg = "   Test with: ./tools.sh local xcode test\n   Stop with: ./tools.sh local xcode stop\n"
            lambdaState.appendOutput(successMsg)
            unifiedOutput.appendOutput(successMsg)
            lambdaState.markRunning()
            unifiedOutput.appendOutput("\n✅ Lambda is running\n")
        } else {
            let failMsg = "Failed to start on port \(lambdaHostPort)"
            lambdaState.markFailed(reason: failMsg)
            unifiedOutput.appendOutput("\n❌ Lambda failed: \(failMsg)\n")
            unifiedOutput.endOperation()
            throw DeployError.testFailed(message: "Lambda failed to start on port \(lambdaHostPort)")
        }
        unifiedOutput.endOperation()
    }

    /// Stop locally running Lambda
    public func stopLambda() async throws {
        lambdaState.beginStop()
        unifiedOutput.startOperation()

        let stopMsg = "🛑 Stopping Lambda...\n"
        lambdaState.appendOutput(stopMsg)
        unifiedOutput.appendOutput(stopMsg)

        // Find process on port
        let pids = await getProcessIDsOnPort(lambdaHostPort)

        if !pids.isEmpty {
            let killMsg = "→ Killing process(es): \(pids.joined(separator: ", "))...\n"
            lambdaState.appendOutput(killMsg)
            unifiedOutput.appendOutput(killMsg)

            // Kill each process
            for pid in pids {
                let killResult = try await cliService.executeForResult(
                    Kill(pid: pid),
                    printCommand: false
                )

                if !killResult.isSuccess {
                    let failMsg = "Failed to kill process \(pid)"
                    lambdaState.markFailed(reason: failMsg)
                    unifiedOutput.appendOutput("❌ \(failMsg)\n")
                    unifiedOutput.endOperation()
                    throw DeployError.commandFailed(
                        command: Kill(pid: pid).commandString,
                        exitCode: killResult.exitCode,
                        stderr: killResult.stderr
                    )
                }
            }

            let stoppedMsg = "Stopped \(pids.count) process\(pids.count == 1 ? "" : "es")\n"
            lambdaState.appendOutput(stoppedMsg)
            unifiedOutput.appendOutput(stoppedMsg)
            lambdaState.markStopped()
            unifiedOutput.appendOutput("\n✅ Lambda stopped\n")
        } else {
            let notFoundMsg = "⚠️  No Lambda process found on port \(lambdaHostPort)\n"
            lambdaState.appendOutput(notFoundMsg)
            unifiedOutput.appendOutput(notFoundMsg)
            lambdaState.markStopped()
        }
        unifiedOutput.endOperation()
    }

    /// Start Lambda with all services (complete flow)
    public func startWithServices() async throws {
        statusSubject.send(.starting)

        // Start services first
        print("\n📦 Starting local services...")
        try await startAllServices()

        // Setup network and bucket for Xcode mode
        try await setupNetworkAndBucket()

        // Then start Lambda
        try await startLambda()

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
    public func stopWithServices() async throws {
        statusSubject.send(.stopping)

        // Stop Lambda first
        try await stopLambda()

        // Then stop services
        print("\n📦 Stopping local services...")
        try await stopAllServices()

        refreshStatus()
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

    /// Get the status of all services (Lambda, S3, PostgreSQL)
    public func status() async throws -> DeploymentStatus {
        // Check Lambda (native process on port)
        let lambdaRunning = await isLambdaRunning()

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
            context: .xcode  // Native process connects via localhost
        )
    }

    /// Create an API client configured for local Lambda testing
    @MainActor
    private func createLocalAPIClient() -> APIClient {
        APIClient(localPort: lambdaHostPort)
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
