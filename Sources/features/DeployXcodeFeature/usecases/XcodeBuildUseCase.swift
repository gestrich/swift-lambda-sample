import Foundation
import CLISDK
import DeployCoreService
import LambdaBuildService
import Uniflow

/// Use case for building Lambda for native macOS/Xcode development.
/// Contains all build logic directly, using SDK clients.
public struct XcodeBuildUseCase: StreamingUseCase {
    private let cliClient: CLIClient
    private let workingDirectory: String
    private let lambdaProductName = "LambdaApp"
    private let paths: LambdaPaths

    public init(
        cliClient: CLIClient,
        workingDirectory: String
    ) {
        self.cliClient = cliClient
        self.workingDirectory = workingDirectory
        self.paths = LambdaPaths(workingDirectory: workingDirectory)
    }

    /// Components needed for build operations.
    public struct Components: Sendable {
        public let useCase: XcodeBuildUseCase
    }

    /// Creates a use case and associated components by instantiating required clients.
    /// - Parameter workingDirectory: The working directory for the build
    /// - Returns: Components containing the use case
    public static func create(workingDirectory: String) -> Components {
        let cliClient = CLIClient(defaultWorkingDirectory: workingDirectory)

        let useCase = XcodeBuildUseCase(
            cliClient: cliClient,
            workingDirectory: workingDirectory
        )

        return Components(useCase: useCase)
    }

    public typealias State = XcodeUseCaseState
    public typealias Result = XcodeUseCaseState

    /// Options for the build use case.
    public struct Options: Sendable {
        public let clean: Bool

        public init(clean: Bool = false) {
            self.clean = clean
        }
    }

    /// Stream the build use case.
    /// - Parameter options: Build options
    /// - Returns: AsyncThrowingStream that yields XcodeUseCaseState updates
    public func stream(options: Options) -> AsyncThrowingStream<XcodeUseCaseState, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    try await runUseCase(options: options, continuation: continuation)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func runUseCase(
        options: Options,
        continuation: AsyncThrowingStream<XcodeUseCaseState, Error>.Continuation
    ) async throws {
        let startTime = Date()

        // Clean if requested
        if options.clean {
            continuation.yield(.building(XcodeUseCaseState.BuildProgress(
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
        continuation.yield(.building(XcodeUseCaseState.BuildProgress(
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
                    continuation.yield(.building(XcodeUseCaseState.BuildProgress(
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
        paths.isXcodeBuildComplete()
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
