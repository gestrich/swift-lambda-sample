import Foundation
import CLISDK
import DeployCoreService
import LambdaBuildService
import Uniflow

/// Workflow for building Lambda for native macOS/Xcode development.
/// Contains all build logic directly, using SDK clients.
public struct XcodeBuildWorkflow: StreamingUseCase {
    private let cliClient: CLIClient
    private let workingDirectory: String
    private let lambdaProductName = "LambdaApp"

    public init(
        cliClient: CLIClient,
        workingDirectory: String
    ) {
        self.cliClient = cliClient
        self.workingDirectory = workingDirectory
    }

    /// Components needed for build operations.
    public struct Components: Sendable {
        public let workflow: XcodeBuildWorkflow
    }

    /// Creates a workflow and associated components by instantiating required clients.
    /// - Parameter workingDirectory: The working directory for the build
    /// - Returns: Components containing the workflow
    public static func create(workingDirectory: String) -> Components {
        let cliClient = CLIClient(defaultWorkingDirectory: workingDirectory)

        let workflow = XcodeBuildWorkflow(
            cliClient: cliClient,
            workingDirectory: workingDirectory
        )

        return Components(workflow: workflow)
    }

    public typealias State = XcodeWorkflowState
    public typealias Result = XcodeWorkflowState

    /// Options for the build workflow.
    public struct Options: Sendable {
        public let clean: Bool

        public init(clean: Bool = false) {
            self.clean = clean
        }
    }

    /// Stream the build workflow.
    /// - Parameter options: Build options
    /// - Returns: AsyncThrowingStream that yields XcodeWorkflowState updates
    public func stream(options: Options) -> AsyncThrowingStream<XcodeWorkflowState, Error> {
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
        continuation: AsyncThrowingStream<XcodeWorkflowState, Error>.Continuation
    ) async throws {
        let startTime = Date()

        // Clean if requested
        if options.clean {
            continuation.yield(.building(XcodeWorkflowState.BuildProgress(
                step: .cleaning,
                startTime: startTime
            )))
            _ = try await cliClient.execute(
                SwiftCLI.Package.Clean(),
                workingDirectory: workingDirectory,
                printCommand: false
            )
        }

        // Build
        continuation.yield(.building(XcodeWorkflowState.BuildProgress(
            step: .building,
            startTime: startTime
        )))

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
                    continuation.yield(.building(XcodeWorkflowState.BuildProgress(
                        step: .building,
                        startTime: startTime,
                        output: trimmed
                    )))
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

        // Build completed successfully - yield completed snapshot
        let snapshot = XcodeSnapshot(
            serviceStatus: .stopped,
            buildStatus: .available
        )
        continuation.yield(.completed(snapshot))
        continuation.finish()
    }

    // MARK: - Additional Build Utilities

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
}
