import Foundation
import CLISDK
import DockerCLISDK
import DeployCoreService
import DeployLocalService
import DynamoDBSDK
import LambdaBuildService
import MinioSDK
import PostgreSQLSDK
import StorageService
import Uniflow

/// Workflow for starting the Lambda as a Docker container.
/// Contains all start logic directly, using SDK clients.
public struct LinuxStartLambdaWorkflow: StreamingUseCase {
    private let cliClient: CLIClient
    private let dockerClient: DockerClient
    private let postgresClient: PostgreSQLClient
    private let minioClient: MinIOClient
    private let dynamodbClient: DynamoDBClient
    private let config: LinuxContainerConfig
    private let workingDirectory: String

    // Build artifact paths
    private var lambdaDir: String { "\(workingDirectory)/lambda" }
    private var lambdaZipPath: String { "\(workingDirectory)/lambda.zip" }
    private var bootstrapPath: String { "\(lambdaDir)/bootstrap" }

    public init(
        cliClient: CLIClient,
        dockerClient: DockerClient,
        postgresClient: PostgreSQLClient,
        minioClient: MinIOClient,
        dynamodbClient: DynamoDBClient,
        config: LinuxContainerConfig,
        workingDirectory: String
    ) {
        self.cliClient = cliClient
        self.dockerClient = dockerClient
        self.postgresClient = postgresClient
        self.minioClient = minioClient
        self.dynamodbClient = dynamodbClient
        self.config = config
        self.workingDirectory = workingDirectory
    }

    /// Components needed for Lambda start operations.
    public struct Components: Sendable {
        public let workflow: LinuxStartLambdaWorkflow
        public let port: Int
    }

    /// Creates a workflow and associated components by instantiating required clients.
    /// - Parameter workingDirectory: The working directory for the build
    /// - Returns: Components containing the workflow and configuration
    public static func create(workingDirectory: String) -> Components {
        let cliClient = CLIClient(defaultWorkingDirectory: workingDirectory)
        let dockerClient = DockerClient(cliClient: cliClient)
        let storageService = LocalStorageService()
        let config = LinuxContainerConfig.default(workingDirectory: workingDirectory)

        let postgresClient = PostgreSQLClient(
            dockerClient: dockerClient,
            config: .linux,
            dataDirectory: storageService.dataDirectory(for: PostgreSQLLinuxStorageKey.self)
        )
        let minioClient = MinIOClient(
            dockerClient: dockerClient,
            networkName: config.networkName,
            config: .linux,
            dataDirectory: storageService.dataDirectory(for: MinIOLinuxStorageKey.self)
        )
        let dynamodbClient = DynamoDBClient(
            dockerClient: dockerClient,
            config: .linux,
            dataDirectory: storageService.dataDirectory(for: DynamoDBLocalLinuxStorageKey.self)
        )

        let workflow = LinuxStartLambdaWorkflow(
            cliClient: cliClient,
            dockerClient: dockerClient,
            postgresClient: postgresClient,
            minioClient: minioClient,
            dynamodbClient: dynamodbClient,
            config: config,
            workingDirectory: workingDirectory
        )

        return Components(workflow: workflow, port: config.hostPort)
    }

    public typealias State = LinuxWorkflowState
    public typealias Result = State
    public typealias Options = Void

    /// Stream the start Lambda workflow.
    /// - Returns: AsyncThrowingStream that yields LinuxWorkflowState updates
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
        let startTime = Date()

        // Ensure Docker is running
        if !(await dockerClient.isDockerRunning()) {
            try await startDockerDesktop()
        }

        // Check if build exists
        continuation.yield(.startingLambda(LinuxWorkflowState.LambdaProgress(step: .starting, startTime: startTime)))
        let isBuilt = isLambdaBuilt()
        if !isBuilt {
            continuation.yield(.building(LinuxWorkflowState.BuildProgress(step: .building, startTime: startTime, output: "Lambda not built, will build first")))
            try await buildLambda(continuation: continuation, startTime: startTime)
        }

        // Start Lambda container
        continuation.yield(.startingLambda(LinuxWorkflowState.LambdaProgress(step: .starting, startTime: startTime)))
        try await startDetached(continuation: continuation, startTime: startTime)

        // Wait for ready
        continuation.yield(.startingLambda(LinuxWorkflowState.LambdaProgress(step: .waitingForReady, startTime: startTime)))
        try await waitForReady()

        // Build final snapshot - Lambda is running, services status untracked (use stopped as default)
        let snapshot = LinuxSnapshot(
            serviceStatus: DeploymentStatus(
                lambdaState: .running,
                s3State: .stopped,
                postgresState: .stopped,
                dynamodbState: .stopped
            ),
            buildStatus: .available
        )
        continuation.yield(.completed(snapshot))
        continuation.finish()
    }

    // MARK: - Build Check

    /// Check if Lambda is already built (Linux artifacts)
    private func isLambdaBuilt() -> Bool {
        return FileManager.default.fileExists(atPath: lambdaDir) &&
               FileManager.default.fileExists(atPath: bootstrapPath) &&
               FileManager.default.fileExists(atPath: lambdaZipPath)
    }

    /// Build Lambda using LinuxBuildWorkflow
    private func buildLambda(
        continuation: AsyncThrowingStream<State, Error>.Continuation,
        startTime: Date
    ) async throws {
        let buildComponents = LinuxBuildWorkflow.create(workingDirectory: workingDirectory)
        let options = LinuxBuildWorkflow.Options(clean: false)

        for try await buildState in buildComponents.workflow.stream(options: options) {
            if case .building(let progress) = buildState, let text = progress.output {
                continuation.yield(.building(LinuxWorkflowState.BuildProgress(step: .building, startTime: startTime, output: text)))
            }
        }
    }

    // MARK: - Start Lambda Container

    /// Start Lambda container in detached mode
    private func startDetached(
        continuation: AsyncThrowingStream<State, Error>.Continuation,
        startTime: Date
    ) async throws {
        guard FileManager.default.fileExists(atPath: lambdaDir) else {
            throw CLIClientError.invalidWorkingDirectory("lambda directory not found at \(lambdaDir)")
        }

        var options = DockerClient.RunOptions()
        options.detached = true
        options.remove = true
        options.name = config.containerName
        options.platform = "linux/amd64"
        options.network = config.networkName
        options.ports = [(config.hostPort, config.containerPort)]
        options.volumes = [(lambdaDir, "/var/task")]
        options.environment = getEnvironmentVariables()

        try await dockerClient.run(
            image: config.swiftImage,
            command: ["bash", "-c", "cd /var/task && chmod +x bootstrap && exec ./bootstrap"],
            options: options
        )

        continuation.yield(.startingLambda(LinuxWorkflowState.LambdaProgress(step: .starting, startTime: startTime)))
    }

    // MARK: - Wait For Ready

    /// Wait for Lambda to be ready on specified port
    private func waitForReady(maxAttempts: Int = 30) async throws {
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
        }

        if !ready {
            let logsResult = try await cliClient.execute(
                command: "docker",
                arguments: ["logs", config.containerName],
                printCommand: false
            )
            throw DeployError.testFailed(
                message: "Lambda failed to be ready on port \(config.hostPort) after \(maxAttempts) seconds. Logs: \(logsResult.stdout) \(logsResult.stderr)"
            )
        }
    }

    // MARK: - Environment Variables

    /// Get environment variables for Lambda container (Docker network)
    private func getEnvironmentVariables() -> [String: String] {
        return createEnvironmentVariables(
            postgresClient: postgresClient,
            minioClient: minioClient,
            dynamodbClient: dynamodbClient,
            context: .container
        )
    }

    // MARK: - Docker Desktop

    /// Start Docker Desktop application and wait for daemon to be ready
    private func startDockerDesktop() async throws {
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

        let maxAttempts = 60
        for _ in 1...maxAttempts {
            if await dockerClient.isDockerRunning() {
                return
            }
            try await Task.sleep(for: .seconds(1))
        }

        throw DeployError.commandFailed(
            command: "docker",
            exitCode: 1,
            output: "Docker Desktop started but daemon did not become ready within 60 seconds."
        )
    }
}
