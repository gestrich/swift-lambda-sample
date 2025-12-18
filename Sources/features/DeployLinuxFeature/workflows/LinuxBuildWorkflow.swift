import Foundation
import CLISDK
import DockerCLISDK
import LambdaBuildService
import DeployCoreService
import Uniflow

/// Workflow for building Lambda for Linux/Docker container development.
/// Contains all build logic directly, using SDK clients.
public struct LinuxBuildWorkflow: StreamingWorkflow {
    private let cliClient: CLIClient
    private let dockerClient: DockerClient
    private let workingDirectory: String

    // Build artifact paths
    private var lambdaDir: String { "\(workingDirectory)/lambda" }
    private var lambdaZipPath: String { "\(workingDirectory)/lambda.zip" }
    private var bootstrapPath: String { "\(lambdaDir)/bootstrap" }
    private var awsSamBuildDir: String { ".aws-sam/build-SwiftLambda" }
    private var buildArtifactPaths: [String] { ["lambda", "lambda.zip", awsSamBuildDir] }

    public init(
        cliClient: CLIClient,
        dockerClient: DockerClient,
        workingDirectory: String
    ) {
        self.cliClient = cliClient
        self.dockerClient = dockerClient
        self.workingDirectory = workingDirectory
    }

    /// Components needed for build operations.
    public struct Components: Sendable {
        public let workflow: LinuxBuildWorkflow
    }

    /// Creates a workflow and associated components by instantiating required clients.
    /// - Parameter workingDirectory: The working directory for the build
    /// - Returns: Components containing the workflow
    public static func create(workingDirectory: String) -> Components {
        let cliClient = CLIClient(defaultWorkingDirectory: workingDirectory)
        let dockerClient = DockerClient(cliClient: cliClient)

        let workflow = LinuxBuildWorkflow(
            cliClient: cliClient,
            dockerClient: dockerClient,
            workingDirectory: workingDirectory
        )

        return Components(workflow: workflow)
    }

    /// State updates from the build workflow.
    public struct State: Sendable {
        public let step: Step
        public let detail: Detail?

        public enum Step: Sendable, Equatable {
            case cleaning
            case building
            case complete
        }

        public enum Detail: Sendable {
            case output(String)
            case buildPath(String)
        }

        public init(step: Step, detail: Detail? = nil) {
            self.step = step
            self.detail = detail
        }
    }

    public typealias Result = State

    /// Options for the build workflow.
    public struct Options: Sendable {
        public let clean: Bool

        public init(clean: Bool = false) {
            self.clean = clean
        }
    }

    /// Stream the build workflow.
    /// - Parameter options: Build options
    /// - Returns: AsyncThrowingStream that yields State updates
    public func stream(options: Options) -> AsyncThrowingStream<State, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    try await runWorkflow(options: options, continuation: continuation)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func runWorkflow(
        options: Options,
        continuation: AsyncThrowingStream<State, Error>.Continuation
    ) async throws {
        // Ensure Docker is running
        if !(await dockerClient.isDockerRunning()) {
            try await startDockerDesktop()
        }

        // Clean if requested
        if options.clean {
            continuation.yield(State(step: .cleaning))
            let rmCmd = Rm(recursive: true, force: true, paths: buildArtifactPaths)
            _ = try await cliClient.execute(rmCmd, workingDirectory: workingDirectory, printCommand: false)
        }

        // Build
        continuation.yield(State(step: .building))

        let buildCmd = BuildScript.Build.lambda(target: "LambdaApp")
        let stream = await cliClient.stream(buildCmd, workingDirectory: workingDirectory, printCommand: false)

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

        continuation.yield(State(step: .complete, detail: .buildPath(lambdaDir)))
        continuation.finish()
    }

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

    // MARK: - Additional Build Utilities

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
}
