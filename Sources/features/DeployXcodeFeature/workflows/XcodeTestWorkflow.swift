import Foundation
import CLISDK
import ClientService
import DeployCoreService
import Uniflow

/// Workflow for testing local Lambda endpoints (Xcode mode).
public struct XcodeTestWorkflow: StreamingWorkflow {
    private let cliClient: CLIClient
    private let lambdaHostPort: Int

    // Lambda configuration
    private let lambdaProcessPattern = "swiftlamb"

    /// Components needed for the test workflow.
    public struct Components: Sendable {
        public let workflow: XcodeTestWorkflow

        public init(workflow: XcodeTestWorkflow) {
            self.workflow = workflow
        }
    }

    /// Creates the workflow with all required dependencies.
    /// - Parameter workingDirectory: The working directory for CLI commands
    /// - Returns: Components containing the configured workflow
    public static func create(workingDirectory: String) -> Components {
        let cliClient = CLIClient(defaultWorkingDirectory: workingDirectory)
        let workflow = XcodeTestWorkflow(
            cliClient: cliClient,
            lambdaHostPort: 8080
        )
        return Components(workflow: workflow)
    }

    public init(
        cliClient: CLIClient,
        lambdaHostPort: Int = 8080
    ) {
        self.cliClient = cliClient
        self.lambdaHostPort = lambdaHostPort
    }

    /// State updates from the test workflow.
    public struct State: Sendable {
        public let step: Step
        public let detail: Detail?

        public enum Step: Sendable, Equatable {
            case checkingLambda
            case testingFileUpload
            case testingFileList
            case testingFileDownload
            case testingDatabaseInit
            case complete
        }

        public enum Detail: Sendable {
            case output(String)
            case testPassed(String)
            case testFailed(String, String)
        }

        public init(step: Step, detail: Detail? = nil) {
            self.step = step
            self.detail = detail
        }
    }

    public typealias Result = State
    public typealias Options = Void

    /// Stream the test workflow.
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
        // Check if Lambda is running
        continuation.yield(State(step: .checkingLambda))
        let isRunning = await isLambdaRunning()
        if !isRunning {
            continuation.yield(State(
                step: .checkingLambda,
                detail: .output("Lambda is not running. Please start it first with: ./tools.sh local xcode start")
            ))
            throw DeployError.testFailed(message: "Lambda is not running on port \(lambdaHostPort)")
        }
        continuation.yield(State(step: .checkingLambda, detail: .output("Lambda is running")))

        // Run the tests
        try await performLocalLambdaTests(continuation: continuation)

        continuation.yield(State(step: .complete))
        continuation.finish()
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

    private func performLocalLambdaTests(
        continuation: AsyncThrowingStream<State, Error>.Continuation
    ) async throws {
        let client = await MainActor.run { APIClient(localPort: lambdaHostPort, serviceName: "Local Xcode (Native)") }

        // Test file upload
        continuation.yield(State(step: .testingFileUpload))
        let testContent = "Hello from test file!"
        guard let testData = testContent.data(using: .utf8) else {
            throw DeployError.testFailed(message: "Failed to create test data")
        }

        let uploadResponse = try await client.uploadFile(fileName: "test-upload.txt", data: testData)
        if uploadResponse.contains("File uploaded: test-upload.txt") {
            continuation.yield(State(step: .testingFileUpload, detail: .testPassed("File upload")))
        } else {
            continuation.yield(State(step: .testingFileUpload, detail: .testFailed("File upload", uploadResponse)))
            throw DeployError.testFailed(message: "File upload endpoint test failed")
        }

        // Test file list
        continuation.yield(State(step: .testingFileList))
        let fileList = try await client.listFiles()
        if fileList.contains("test-upload.txt") {
            continuation.yield(State(step: .testingFileList, detail: .testPassed("File list (found \(fileList.count) files)")))
        } else {
            continuation.yield(State(step: .testingFileList, detail: .testFailed("File list", "\(fileList)")))
            throw DeployError.testFailed(message: "List files endpoint test failed")
        }

        // Test file download
        continuation.yield(State(step: .testingFileDownload))
        let downloadedData = try await client.downloadFile(fileName: "test-upload.txt")
        if let downloadedContent = String(data: downloadedData, encoding: .utf8) {
            if downloadedContent.contains("Hello from test file!") {
                continuation.yield(State(step: .testingFileDownload, detail: .testPassed("File download")))
            } else {
                continuation.yield(State(step: .testingFileDownload, detail: .testFailed("File download", "unexpected content")))
                throw DeployError.testFailed(message: "File download endpoint test failed")
            }
        } else {
            continuation.yield(State(step: .testingFileDownload, detail: .testFailed("File download", "could not decode content")))
            throw DeployError.testFailed(message: "File download endpoint test failed")
        }

        // Test database initialization
        continuation.yield(State(step: .testingDatabaseInit))
        let dbResult = try await client.initializeDatabase()
        if dbResult.contains("Database Initialized") {
            continuation.yield(State(step: .testingDatabaseInit, detail: .testPassed("Database init")))
        } else {
            continuation.yield(State(step: .testingDatabaseInit, detail: .testFailed("Database init", dbResult)))
            throw DeployError.testFailed(message: "Database endpoint test failed")
        }
    }

}
