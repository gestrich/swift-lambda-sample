import Foundation
import CLISDK
import ClientService
import DeployCoreService
import Uniflow

/// Use case for testing local Lambda endpoints (Xcode mode).
public struct XcodeTestUseCase: StreamingUseCase {
    private let cliClient: CLIClient
    private let lambdaHostPort: Int

    // Lambda configuration
    private let lambdaProcessPattern = "swiftlamb"

    /// Components needed for the test use case.
    public struct Components: Sendable {
        public let useCase: XcodeTestUseCase

        public init(useCase: XcodeTestUseCase) {
            self.useCase = useCase
        }
    }

    /// Creates the use case with all required dependencies.
    /// - Parameter workingDirectory: The working directory for CLI commands
    /// - Returns: Components containing the configured use case
    public static func create(workingDirectory: String) -> Components {
        let cliClient = CLIClient(defaultWorkingDirectory: workingDirectory)
        let useCase = XcodeTestUseCase(
            cliClient: cliClient,
            lambdaHostPort: 8080
        )
        return Components(useCase: useCase)
    }

    public init(
        cliClient: CLIClient,
        lambdaHostPort: Int = 8080
    ) {
        self.cliClient = cliClient
        self.lambdaHostPort = lambdaHostPort
    }

    public typealias State = XcodeUseCaseState
    public typealias Result = XcodeUseCaseState
    public typealias Options = Void

    /// Stream the test use case.
    /// - Returns: AsyncThrowingStream that yields XcodeUseCaseState updates
    public func stream(options: Void) -> AsyncThrowingStream<XcodeUseCaseState, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    try await runUseCase(continuation: continuation)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func runUseCase(
        continuation: AsyncThrowingStream<XcodeUseCaseState, Error>.Continuation
    ) async throws {
        let startTime = Date()

        // Check if Lambda is running
        continuation.yield(.testing(XcodeUseCaseState.TestProgress(
            step: .checkingLambda,
            startTime: startTime
        )))
        let isRunning = await isLambdaRunning()
        if !isRunning {
            continuation.yield(.testing(XcodeUseCaseState.TestProgress(
                step: .checkingLambda,
                startTime: startTime,
                result: .message("Lambda is not running. Please start it first with: ./tools.sh local xcode start")
            )))
            throw DeployError.testFailed(message: "Lambda is not running on port \(lambdaHostPort)")
        }
        continuation.yield(.testing(XcodeUseCaseState.TestProgress(
            step: .checkingLambda,
            startTime: startTime,
            result: .message("Lambda is running")
        )))

        // Run the tests
        try await performLocalLambdaTests(startTime: startTime, continuation: continuation)

        // Completed - yield snapshot with Lambda running
        let snapshot = XcodeSnapshot(
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
        startTime: Date,
        continuation: AsyncThrowingStream<XcodeUseCaseState, Error>.Continuation
    ) async throws {
        let client = await MainActor.run { APIClient(localPort: lambdaHostPort, serviceName: "Local Xcode (Native)") }

        // Test file upload
        continuation.yield(.testing(XcodeUseCaseState.TestProgress(
            step: .testingFileUpload,
            startTime: startTime
        )))
        let testContent = "Hello from test file!"
        guard let testData = testContent.data(using: .utf8) else {
            throw DeployError.testFailed(message: "Failed to create test data")
        }

        let uploadResponse = try await client.uploadFile(fileName: "test-upload.txt", data: testData)
        if uploadResponse.contains("File uploaded: test-upload.txt") {
            continuation.yield(.testing(XcodeUseCaseState.TestProgress(
                step: .testingFileUpload,
                startTime: startTime,
                result: .passed("File upload")
            )))
        } else {
            continuation.yield(.testing(XcodeUseCaseState.TestProgress(
                step: .testingFileUpload,
                startTime: startTime,
                result: .failed("File upload", uploadResponse)
            )))
            throw DeployError.testFailed(message: "File upload endpoint test failed")
        }

        // Test file list
        continuation.yield(.testing(XcodeUseCaseState.TestProgress(
            step: .testingFileList,
            startTime: startTime
        )))
        let fileList = try await client.listFiles()
        if fileList.contains("test-upload.txt") {
            continuation.yield(.testing(XcodeUseCaseState.TestProgress(
                step: .testingFileList,
                startTime: startTime,
                result: .passed("File list (found \(fileList.count) files)")
            )))
        } else {
            continuation.yield(.testing(XcodeUseCaseState.TestProgress(
                step: .testingFileList,
                startTime: startTime,
                result: .failed("File list", "\(fileList)")
            )))
            throw DeployError.testFailed(message: "List files endpoint test failed")
        }

        // Test file download
        continuation.yield(.testing(XcodeUseCaseState.TestProgress(
            step: .testingFileDownload,
            startTime: startTime
        )))
        let downloadedData = try await client.downloadFile(fileName: "test-upload.txt")
        if let downloadedContent = String(data: downloadedData, encoding: .utf8) {
            if downloadedContent.contains("Hello from test file!") {
                continuation.yield(.testing(XcodeUseCaseState.TestProgress(
                    step: .testingFileDownload,
                    startTime: startTime,
                    result: .passed("File download")
                )))
            } else {
                continuation.yield(.testing(XcodeUseCaseState.TestProgress(
                    step: .testingFileDownload,
                    startTime: startTime,
                    result: .failed("File download", "unexpected content")
                )))
                throw DeployError.testFailed(message: "File download endpoint test failed")
            }
        } else {
            continuation.yield(.testing(XcodeUseCaseState.TestProgress(
                step: .testingFileDownload,
                startTime: startTime,
                result: .failed("File download", "could not decode content")
            )))
            throw DeployError.testFailed(message: "File download endpoint test failed")
        }

        // Test database initialization
        continuation.yield(.testing(XcodeUseCaseState.TestProgress(
            step: .testingDatabaseInit,
            startTime: startTime
        )))
        let dbResult = try await client.initializeDatabase()
        if dbResult.contains("Database Initialized") {
            continuation.yield(.testing(XcodeUseCaseState.TestProgress(
                step: .testingDatabaseInit,
                startTime: startTime,
                result: .passed("Database init")
            )))
        } else {
            continuation.yield(.testing(XcodeUseCaseState.TestProgress(
                step: .testingDatabaseInit,
                startTime: startTime,
                result: .failed("Database init", dbResult)
            )))
            throw DeployError.testFailed(message: "Database endpoint test failed")
        }
    }

}
