//
//  LambdaBuildService.swift
//  SwiftDeploy
//
//  Service for building and uploading Lambda for Linux using Docker
//

import sdk_cli
import sdk_aws
import Foundation

/// Service for building and uploading Lambda for Linux (AMD64) using Docker
@MainActor
@Observable
public class LambdaBuildService {
    private let workingDirectory: String
    private let cliService: CLIService
    private var awsConfig: AWSAuthConfiguration?

    /// Build state for tracking progress
    public var buildState = BuildState()

    /// Upload status (separate from build status)
    public private(set) var uploadStatus: LambdaUploadStatus = .idle
    public private(set) var lastUploadTime: Date?

    /// Lambda build artifact paths
    private var lambdaDir: String { "\(workingDirectory)/lambda" }
    private var lambdaZipPath: String { "\(workingDirectory)/lambda.zip" }
    private var bootstrapPath: String { "\(lambdaDir)/bootstrap" }
    private var awsSamBuildDir: String { ".aws-sam/build-SwiftLambda" }

    /// Paths to clean when deleting build artifacts (relative to workingDirectory)
    private var buildArtifactPaths: [String] { ["lambda", "lambda.zip", awsSamBuildDir] }

    private let functionName = "swift-lambda-sample"

    public init(workingDirectory: String, cliService: CLIService, awsConfig: AWSAuthConfiguration? = nil) {
        self.workingDirectory = workingDirectory
        self.cliService = cliService
        self.awsConfig = awsConfig
    }

    /// Convenience initializer that creates its own CLIService
    public init(workingDirectory: String, awsConfig: AWSAuthConfiguration? = nil) {
        self.workingDirectory = workingDirectory
        self.cliService = CLIService(defaultWorkingDirectory: workingDirectory)
        self.awsConfig = awsConfig
    }

    /// Convenience initializer that creates its own CLIService
    public convenience init(workingDirectory: String) {
        let cliService = CLIService(defaultWorkingDirectory: workingDirectory)
        self.init(workingDirectory: workingDirectory, cliService: cliService)
    }

    /// Convenience initializer with AWS config for upload capability
    public convenience init(workingDirectory: String, awsConfig: AWSAuthConfiguration) {
        let cliService = CLIService(defaultWorkingDirectory: workingDirectory)
        self.init(workingDirectory: workingDirectory, cliService: cliService, awsConfig: awsConfig)
    }

    // MARK: - Build Operations

    /// Build Lambda for Linux (AMD64) using Docker
    /// - Parameters:
    ///   - clean: If true, cleans previous build artifacts first
    ///   - output: Optional client-owned stream to receive output (in addition to global stream)
    public func build(clean: Bool = false, output: CLIOutputStream? = nil) async throws {
        buildState.startBuild()

        // Clean if requested
        if clean {
            let cleanMsg = "🧹 Cleaning previous build artifacts...\n"
            buildState.appendOutput(cleanMsg)
            await output?.send(.stdout(commandID: .init(), text: cleanMsg))
            do {
                let rmCmd = Rm(recursive: true, force: true, paths: buildArtifactPaths)
                _ = try await cliService.execute(
                    rmCmd,
                    workingDirectory: workingDirectory,
                    printCommand: false,
                    output: output
                )
                let successMsg = "  ✅ Cleaned\n"
                buildState.appendOutput(successMsg)
                await output?.send(.stdout(commandID: .init(), text: successMsg))
            } catch {
                let errorMsg = "  ❌ Clean failed: \(error)\n"
                buildState.appendOutput(errorMsg)
                await output?.send(.stderr(commandID: .init(), text: errorMsg))
                buildState.markFailed(exitCode: 1)
                throw BuildError.failed(exitCode: 1)
            }
        }

        let buildMsg = "🔨 Building Lambda for Linux (Docker)...\n"
        buildState.appendOutput(buildMsg)
        await output?.send(.stdout(commandID: .init(), text: buildMsg))

        // Stream the build output using typed command
        let buildCmd = BuildScript.Build.lambda(target: "feature-lambda")
        let stream = await cliService.stream(
            buildCmd,
            workingDirectory: workingDirectory,
            printCommand: false,
            output: output
        )

        var exitCode: Int32 = 0
        for await streamOutput in stream {
            if let code = buildState.processStreamOutput(streamOutput) {
                exitCode = code
            }
        }

        if exitCode == 0 {
            buildState.markSuccess()
        } else {
            buildState.markFailed(exitCode: exitCode)
            throw BuildError.failed(exitCode: exitCode)
        }
    }

    /// Check if Lambda is already built (Linux artifacts exist)
    public func isLambdaBuilt() -> Bool {
        FileManager.default.fileExists(atPath: lambdaDir) &&
        FileManager.default.fileExists(atPath: bootstrapPath) &&
        FileManager.default.fileExists(atPath: lambdaZipPath)
    }

    /// Delete build artifacts and reset build state
    public func deleteBuild() async throws {
        let rmCmd = Rm(recursive: true, force: true, paths: buildArtifactPaths)
        _ = try await cliService.execute(
            rmCmd,
            workingDirectory: workingDirectory,
            printCommand: false
        )
        buildState.clear()
    }

    // MARK: - Upload Operations

    /// Upload the Lambda package to AWS
    /// Requires awsConfig to be set
    /// - Parameter output: Optional client-owned stream to receive output (in addition to global stream)
    public func upload(output: CLIOutputStream? = nil) async throws {
        guard let awsConfig = awsConfig else {
            throw LambdaUploadError.uploadFailed(output: "AWS config not provided")
        }

        uploadStatus = .uploading

        do {
            // Verify lambda.zip exists
            guard FileManager.default.fileExists(atPath: lambdaZipPath) else {
                throw LambdaUploadError.zipNotCreated(path: lambdaZipPath)
            }

            // Build the AWS CLI command
            let command = Aws.Lambda.UpdateFunctionCode(
                functionName: functionName,
                zipFile: "fileb://\(lambdaZipPath)",
                profile: awsConfig.profileName
            )

            // Build command line with optional aws-vault wrapping
            let execCommand: String
            let arguments: [String]

            if awsConfig.useAWSVault {
                let vaultService = AWSVaultService(profile: awsConfig.profileName)
                let filteredArgs = AWSVaultService.removeProfileFlags(from: command.commandArguments)
                (execCommand, arguments) = vaultService.wrapCommand(command: "aws", arguments: filteredArgs)
            } else {
                execCommand = "aws"
                arguments = command.commandArguments
            }

            let result = try await cliService.execute(
                command: execCommand,
                arguments: arguments,
                workingDirectory: workingDirectory,
                environment: ["AWS_PROFILE": awsConfig.profileName],
                printCommand: true,
                output: output
            )

            if !result.isSuccess {
                throw LambdaUploadError.uploadFailed(output: result.output)
            }

            lastUploadTime = Date()
            uploadStatus = .success

        } catch let error as LambdaUploadError {
            uploadStatus = .failed(reason: error.localizedDescription)
            throw error
        } catch {
            uploadStatus = .failed(reason: error.localizedDescription)
            throw error
        }
    }

    /// Build and upload in one operation
    /// - Parameter output: Optional client-owned stream to receive output (in addition to global stream)
    public func buildAndUpload(output: CLIOutputStream? = nil) async throws {
        try await build(output: output)
        try await upload(output: output)
    }

    /// Reset upload status to idle
    public func resetUploadStatus() {
        uploadStatus = .idle
    }
}

/// Status of the Lambda upload process
public enum LambdaUploadStatus: Equatable, Sendable {
    case idle
    case uploading
    case success
    case failed(reason: String)

    public var isInProgress: Bool {
        switch self {
        case .uploading:
            return true
        default:
            return false
        }
    }

    public var canUpload: Bool {
        switch self {
        case .idle, .success, .failed:
            return true
        default:
            return false
        }
    }
}

/// Errors for Lambda upload operations
public enum LambdaUploadError: LocalizedError {
    case zipNotCreated(path: String)
    case uploadFailed(output: String)

    public var errorDescription: String? {
        switch self {
        case .zipNotCreated(let path):
            return "Lambda zip file not created at: \(path)"
        case .uploadFailed(let output):
            return "Upload failed: \(output.suffix(200))"
        }
    }
}
