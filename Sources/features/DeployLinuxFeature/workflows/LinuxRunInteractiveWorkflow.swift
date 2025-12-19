import Foundation
import CLISDK
import DockerCLISDK
import PostgreSQLSDK
import MinioSDK
import DynamoDBSDK
import StorageService
import DeployLocalService
import Uniflow

/// Workflow for running interactive container shell.
/// Contains all interactive logic directly, using SDK clients.
public struct LinuxRunInteractiveWorkflow: StreamingUseCase {
    private let dockerClient: DockerClient
    private let postgresClient: PostgreSQLClient
    private let minioClient: MinIOClient
    private let dynamodbClient: DynamoDBClient
    private let config: LinuxContainerConfig
    private let workingDirectory: String

    // Build artifact paths
    private var lambdaDir: String { "\(workingDirectory)/lambda" }

    public init(
        dockerClient: DockerClient,
        postgresClient: PostgreSQLClient,
        minioClient: MinIOClient,
        dynamodbClient: DynamoDBClient,
        config: LinuxContainerConfig,
        workingDirectory: String
    ) {
        self.dockerClient = dockerClient
        self.postgresClient = postgresClient
        self.minioClient = minioClient
        self.dynamodbClient = dynamodbClient
        self.config = config
        self.workingDirectory = workingDirectory
    }

    /// Components needed for interactive operations.
    public struct Components: Sendable {
        public let workflow: LinuxRunInteractiveWorkflow
    }

    /// Creates a workflow and associated components by instantiating required clients.
    /// - Parameter workingDirectory: The working directory for the workflow
    /// - Returns: Components containing the workflow
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

        let workflow = LinuxRunInteractiveWorkflow(
            dockerClient: dockerClient,
            postgresClient: postgresClient,
            minioClient: minioClient,
            dynamodbClient: dynamodbClient,
            config: config,
            workingDirectory: workingDirectory
        )

        return Components(workflow: workflow)
    }

    /// State updates from the run interactive workflow.
    public struct State: Sendable {
        public let step: Step
        public let detail: Detail?

        public enum Step: Sendable, Equatable {
            case preparing
            case launching
            case complete
        }

        public enum Detail: Sendable {
            case output(String)
            case command(String)
        }

        public init(step: Step, detail: Detail? = nil) {
            self.step = step
            self.detail = detail
        }
    }

    public typealias Result = State
    public typealias Options = Void

    /// Stream the interactive workflow.
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
        continuation.yield(State(step: .preparing))

        // Check if Lambda is built
        if !isLambdaBuilt() {
            continuation.yield(State(step: .preparing, detail: .output("Lambda not built, building first...")))
            // Build using LinuxBuildWorkflow
            let buildComponents = LinuxBuildWorkflow.create(workingDirectory: workingDirectory)
            for try await _ in buildComponents.workflow.stream(options: .init()) {
                // Consume build updates silently
            }
        }

        continuation.yield(State(step: .launching))
        continuation.yield(State(step: .launching, detail: .output("Starting interactive container...")))

        // Run interactive container
        try await runInteractive()

        continuation.yield(State(step: .complete))
        continuation.finish()
    }

    // MARK: - Interactive Container Methods

    /// Check if Lambda is already built (Linux artifacts)
    private func isLambdaBuilt() -> Bool {
        FileManager.default.fileExists(atPath: lambdaDir)
    }

    /// Get environment variables for Lambda container (Docker network)
    private func getEnvironmentVariables() -> [String: String] {
        createEnvironmentVariables(
            postgresClient: postgresClient,
            minioClient: minioClient,
            dynamodbClient: dynamodbClient,
            context: .container
        )
    }

    /// Run Lambda in interactive container
    private func runInteractive() async throws {
        guard FileManager.default.fileExists(atPath: lambdaDir) else {
            throw CLIClientError.invalidWorkingDirectory("lambda directory not found")
        }

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

    /// Print the Docker command to run Lambda interactively.
    /// This is useful for debugging or running the command manually.
    public func printRunCommand() -> String {
        let env = getEnvironmentVariables()
        let envFlags = env.map { "-e \($0.key)=\($0.value)" }.joined(separator: " \\\n    ")

        return """
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
        """
    }
}
