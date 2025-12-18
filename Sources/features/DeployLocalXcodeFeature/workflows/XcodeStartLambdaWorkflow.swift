import Foundation
import CLISDK
import DeployCoreService
import DeployLocalService
import DockerCLISDK
import DynamoDBSDK
import LambdaBuildService
import MinioSDK
import PostgreSQLSDK
import StorageService
import Uniflow

/// Workflow for starting the Lambda as a native macOS process.
/// Contains all Lambda start logic directly, using SDK clients.
public struct XcodeStartLambdaWorkflow: StreamingWorkflow {
    private let cliClient: CLIClient
    private let postgresClient: PostgreSQLClient
    private let minioClient: MinIOClient
    private let dynamodbClient: DynamoDBClient
    private let workingDirectory: String

    // Lambda configuration
    private let lambdaHostPort = 8080
    private let lambdaProductName = "LambdaApp"

    public init(
        cliClient: CLIClient,
        postgresClient: PostgreSQLClient,
        minioClient: MinIOClient,
        dynamodbClient: DynamoDBClient,
        workingDirectory: String
    ) {
        self.cliClient = cliClient
        self.postgresClient = postgresClient
        self.minioClient = minioClient
        self.dynamodbClient = dynamodbClient
        self.workingDirectory = workingDirectory
    }

    /// Backward-compatible initializer for XcodeStartAllWorkflow.
    /// - Parameter service: The Xcode local development service (ignored, clients created internally)
    @available(*, deprecated, message: "Use XcodeStartLambdaWorkflow.create() instead")
    public init(service: XcodeLocalDevelopmentService) {
        let workingDirectory = FileManager.default.currentDirectoryPath
        let components = Self.create(workingDirectory: workingDirectory)
        self.cliClient = components.cliClient
        self.postgresClient = components.postgresClient
        self.minioClient = components.minioClient
        self.dynamodbClient = components.dynamodbClient
        self.workingDirectory = workingDirectory
    }

    /// Components needed for starting Lambda.
    public struct Components: Sendable {
        public let workflow: XcodeStartLambdaWorkflow
        public let cliClient: CLIClient
        public let postgresClient: PostgreSQLClient
        public let minioClient: MinIOClient
        public let dynamodbClient: DynamoDBClient
    }

    /// Creates a workflow and associated components by instantiating required clients.
    /// - Parameter workingDirectory: The working directory for the workflow
    /// - Returns: Components containing the workflow and clients
    public static func create(workingDirectory: String) -> Components {
        let cliClient = CLIClient(defaultWorkingDirectory: workingDirectory)
        let dockerClient = DockerClient(cliClient: cliClient)
        let storageService = LocalStorageService()

        let postgresClient = PostgreSQLClient(
            dockerClient: dockerClient,
            config: .xcode,
            dataDirectory: storageService.dataDirectory(for: PostgreSQLXcodeStorageKey.self)
        )
        let minioClient = MinIOClient(
            dockerClient: dockerClient,
            networkName: "lambda-xcode",
            config: .xcode,
            dataDirectory: storageService.dataDirectory(for: MinIOXcodeStorageKey.self)
        )
        let dynamodbClient = DynamoDBClient(
            dockerClient: dockerClient,
            config: .xcode,
            dataDirectory: storageService.dataDirectory(for: DynamoDBLocalXcodeStorageKey.self)
        )

        let workflow = XcodeStartLambdaWorkflow(
            cliClient: cliClient,
            postgresClient: postgresClient,
            minioClient: minioClient,
            dynamodbClient: dynamodbClient,
            workingDirectory: workingDirectory
        )

        return Components(
            workflow: workflow,
            cliClient: cliClient,
            postgresClient: postgresClient,
            minioClient: minioClient,
            dynamodbClient: dynamodbClient
        )
    }

    /// State updates from the start Lambda workflow.
    public struct State: Sendable {
        public let step: Step
        public let detail: Detail?

        public enum Step: Sendable, Equatable {
            case checkingBuild
            case building
            case starting
            case waitingForReady
            case complete
        }

        public enum Detail: Sendable {
            case output(String)
            case port(Int)
        }

        public init(step: Step, detail: Detail? = nil) {
            self.step = step
            self.detail = detail
        }
    }

    public typealias Result = State
    public typealias Options = Void

    /// Stream the start Lambda workflow.
    /// - Returns: AsyncThrowingStream that yields State updates
    public func stream(options: Void) -> AsyncThrowingStream<State, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    try await runWorkflow(continuation: continuation)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func runWorkflow(
        continuation: AsyncThrowingStream<State, Error>.Continuation
    ) async throws {
        // Check if build exists
        continuation.yield(State(step: .checkingBuild))
        let isBuilt = isLambdaBuilt()
        if !isBuilt {
            continuation.yield(State(step: .checkingBuild, detail: .output("Lambda not built, will build first")))
        }

        // Build if needed
        if !isBuilt {
            continuation.yield(State(step: .building))
            try await buildLambda(continuation: continuation)
        }

        // Get executable path
        let executablePath = try await getExecutablePath()

        // Start Lambda process
        continuation.yield(State(step: .starting))
        continuation.yield(State(step: .starting, detail: .output("Starting Lambda on port \(lambdaHostPort)...")))

        var env = getLambdaEnvironmentVariables()
        env["LOCAL_LAMBDA_PORT"] = "\(lambdaHostPort)"

        let envVars = env.map { "\($0.key)=\($0.value)" }.joined(separator: " ")

        _ = try await cliClient.execute(
            Sh(command: "\(envVars) \(executablePath) > /tmp/lambda.log 2>&1 & echo $!"),
            workingDirectory: workingDirectory,
            printCommand: false
        )

        // Wait for ready
        continuation.yield(State(step: .waitingForReady))
        try await waitForReady(continuation: continuation)

        continuation.yield(State(step: .complete, detail: .port(lambdaHostPort)))
        continuation.finish()
    }

    // MARK: - Build Helpers

    /// Build Lambda for macOS (native Swift build)
    private func buildLambda(
        continuation: AsyncThrowingStream<State, Error>.Continuation
    ) async throws {
        let buildCommand = SwiftCLI.Build(product: lambdaProductName)
        let stream = await cliClient.stream(
            buildCommand,
            workingDirectory: workingDirectory,
            printCommand: false
        )

        var exitCode: Int32 = 0
        for await output in stream {
            switch output {
            case .stdout(_, let text), .stderr(_, let text):
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    continuation.yield(State(step: .building, detail: .output(trimmed)))
                }
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
    private func getExecutablePath() async throws -> String {
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
    private func isLambdaBuilt() -> Bool {
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

    // MARK: - Ready Check Helpers

    /// Wait for Lambda to be ready on specified port
    private func waitForReady(
        continuation: AsyncThrowingStream<State, Error>.Continuation,
        maxAttempts: Int = 30
    ) async throws {
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
                continuation.yield(State(
                    step: .waitingForReady,
                    detail: .output("Still waiting for Lambda on port \(lambdaHostPort)... (\(attempts) seconds)")
                ))
            }
        }

        if !ready {
            throw DeployError.testFailed(
                message: "Lambda failed to be ready on port \(lambdaHostPort) after \(maxAttempts) seconds"
            )
        }
    }

    /// Check if a port is in use
    private func isPortInUse(_ port: Int) async -> Bool {
        let output = await getPortInfo(port)
        return !output.isEmpty
    }

    /// Get information about what's using a port
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

    // MARK: - Environment Variables

    /// Get environment variables for Lambda process
    private func getLambdaEnvironmentVariables() -> [String: String] {
        return createEnvironmentVariables(
            postgresClient: postgresClient,
            minioClient: minioClient,
            dynamodbClient: dynamodbClient,
            context: .xcode
        )
    }
}
