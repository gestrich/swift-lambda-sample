import Foundation
import ClientService
import CLISDK
import DeployCoreService
import DockerCLISDK
import Uniflow

/// Workflow for testing local Lambda endpoints (Linux mode).
/// Contains all test logic directly, using SDK clients.
public struct LinuxTestWorkflow: StreamingWorkflow {
    private let dockerClient: DockerClient
    private let config: LinuxContainerConfig
    private let workingDirectory: String

    public init(
        dockerClient: DockerClient,
        config: LinuxContainerConfig,
        workingDirectory: String
    ) {
        self.dockerClient = dockerClient
        self.config = config
        self.workingDirectory = workingDirectory
    }

    /// Components needed for Lambda test operations.
    public struct Components: Sendable {
        public let workflow: LinuxTestWorkflow
        public let port: Int
    }

    /// Creates a workflow and associated components by instantiating required clients.
    /// - Parameter workingDirectory: The working directory
    /// - Returns: Components containing the workflow and configuration
    public static func create(workingDirectory: String) -> Components {
        let cliClient = CLIClient(defaultWorkingDirectory: workingDirectory)
        let dockerClient = DockerClient(cliClient: cliClient)
        let config = LinuxContainerConfig.default(workingDirectory: workingDirectory)

        let workflow = LinuxTestWorkflow(
            dockerClient: dockerClient,
            config: config,
            workingDirectory: workingDirectory
        )

        return Components(workflow: workflow, port: config.hostPort)
    }

    public typealias State = LinuxWorkflowState
    public typealias Result = State
    public typealias Options = Void

    /// Stream the test workflow.
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

        // Check if Lambda container is running
        continuation.yield(.testing(LinuxWorkflowState.TestProgress(step: .checkingLambda, startTime: startTime)))
        let running = try await isRunning()
        if !running {
            continuation.yield(.testing(LinuxWorkflowState.TestProgress(
                step: .checkingLambda,
                startTime: startTime,
                result: .message("Lambda container is not running, will start it")
            )))
            try await startLambda()
        }
        continuation.yield(.testing(LinuxWorkflowState.TestProgress(
            step: .checkingLambda,
            startTime: startTime,
            result: .message("Lambda container is running")
        )))

        // Run the actual tests
        try await performLocalLambdaTests(continuation: continuation, startTime: startTime)

        // Build final snapshot
        let snapshot = LinuxSnapshot(
            serviceStatus: DeploymentStatus(
                lambdaState: .running,
                s3State: .running,
                postgresState: .running,
                dynamodbState: .running
            ),
            buildStatus: .available
        )
        continuation.yield(.completed(snapshot))
        continuation.finish()
    }

    // MARK: - Private Helpers

    /// Check if Lambda container is running
    private func isRunning() async throws -> Bool {
        return try await dockerClient.containerIsRunning(name: config.containerName)
    }

    /// Start Lambda container using LinuxStartLambdaWorkflow
    private func startLambda() async throws {
        let startComponents = LinuxStartLambdaWorkflow.create(workingDirectory: workingDirectory)

        for try await _ in startComponents.workflow.stream() {
            // Consume the stream to ensure Lambda starts and is ready
        }
    }

    /// Perform the actual Lambda endpoint tests
    private func performLocalLambdaTests(
        continuation: AsyncThrowingStream<State, Error>.Continuation,
        startTime: Date
    ) async throws {
        let client = await MainActor.run {
            APIClient(localPort: config.hostPort, serviceName: "Local Linux (Container)")
        }

        // Test file upload
        continuation.yield(.testing(LinuxWorkflowState.TestProgress(step: .testingFileUpload, startTime: startTime)))
        let testContent = "Hello from test file!"
        guard let testData = testContent.data(using: .utf8) else {
            throw DeployError.testFailed(message: "Failed to create test data")
        }

        let uploadResponse = try await client.uploadFile(fileName: "test-upload.txt", data: testData)
        if uploadResponse.contains("File uploaded: test-upload.txt") {
            continuation.yield(.testing(LinuxWorkflowState.TestProgress(step: .testingFileUpload, startTime: startTime, result: .passed("File upload"))))
        } else {
            continuation.yield(.testing(LinuxWorkflowState.TestProgress(step: .testingFileUpload, startTime: startTime, result: .failed("File upload", uploadResponse))))
            throw DeployError.testFailed(message: "File upload endpoint test failed")
        }

        // Test list files
        continuation.yield(.testing(LinuxWorkflowState.TestProgress(step: .testingFileList, startTime: startTime)))
        let fileList = try await client.listFiles()
        if fileList.contains("test-upload.txt") {
            continuation.yield(.testing(LinuxWorkflowState.TestProgress(step: .testingFileList, startTime: startTime, result: .passed("File list (found \(fileList.count) files)"))))
        } else {
            continuation.yield(.testing(LinuxWorkflowState.TestProgress(step: .testingFileList, startTime: startTime, result: .failed("File list", "\(fileList)"))))
            throw DeployError.testFailed(message: "List files endpoint test failed")
        }

        // Test file download
        continuation.yield(.testing(LinuxWorkflowState.TestProgress(step: .testingFileDownload, startTime: startTime)))
        let downloadedData = try await client.downloadFile(fileName: "test-upload.txt")
        if let downloadedContent = String(data: downloadedData, encoding: .utf8),
           downloadedContent.contains("Hello from test file!") {
            continuation.yield(.testing(LinuxWorkflowState.TestProgress(step: .testingFileDownload, startTime: startTime, result: .passed("File download"))))
        } else {
            continuation.yield(.testing(LinuxWorkflowState.TestProgress(step: .testingFileDownload, startTime: startTime, result: .failed("File download", "Unexpected content"))))
            throw DeployError.testFailed(message: "File download endpoint test failed")
        }

        // Test database initialization
        continuation.yield(.testing(LinuxWorkflowState.TestProgress(step: .testingDatabaseInit, startTime: startTime)))
        let dbResult = try await client.initializeDatabase()
        if dbResult.contains("Database Initialized") {
            continuation.yield(.testing(LinuxWorkflowState.TestProgress(step: .testingDatabaseInit, startTime: startTime, result: .passed("Database init"))))
        } else {
            continuation.yield(.testing(LinuxWorkflowState.TestProgress(step: .testingDatabaseInit, startTime: startTime, result: .failed("Database init", dbResult))))
            throw DeployError.testFailed(message: "Database endpoint test failed")
        }
    }
}
