//
//  LambdaUploadService.swift
//  SwiftDeploy
//
//  Service for building and uploading Lambda code directly to AWS
//

import CLIKit
import Foundation
import Observation

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

/// Service for uploading Lambda code directly to AWS
/// Uses LambdaBuildService for building
@MainActor
@Observable
public class LambdaUploadService {
    private let projectRoot: String
    private let awsConfig: AWSAuthConfiguration
    private let cliService: CLIService

    /// Shared build service for building Lambda
    public let buildService: LambdaBuildService

    /// Upload status (separate from build status)
    public private(set) var status: LambdaUploadStatus = .idle
    public private(set) var lastUploadTime: Date?

    private let functionName = "swift-lambda-sample"

    public init(projectRoot: String, awsConfig: AWSAuthConfiguration, cliService: CLIService) {
        self.projectRoot = projectRoot
        self.awsConfig = awsConfig
        self.cliService = cliService
        self.buildService = LambdaBuildService(workingDirectory: projectRoot, cliService: cliService)
    }

    /// Upload the Lambda package to AWS
    public func upload() async throws {
        status = .uploading

        do {
            let zipPath = "\(projectRoot)/lambda.zip"

            // Verify lambda.zip exists
            guard FileManager.default.fileExists(atPath: zipPath) else {
                throw LambdaUploadError.zipNotCreated(path: zipPath)
            }

            // Build the AWS CLI command
            let command = Aws.Lambda.UpdateFunctionCode(
                functionName: functionName,
                zipFile: "fileb://\(zipPath)",
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
                workingDirectory: projectRoot,
                environment: ["AWS_PROFILE": awsConfig.profileName],
                printCommand: true
            )

            if !result.isSuccess {
                throw LambdaUploadError.uploadFailed(output: result.output)
            }

            lastUploadTime = Date()
            status = .success

        } catch let error as LambdaUploadError {
            status = .failed(reason: error.localizedDescription)
            throw error
        } catch {
            status = .failed(reason: error.localizedDescription)
            throw error
        }
    }

    /// Build and upload in one operation
    public func buildAndUpload() async throws {
        try await buildService.build()
        try await upload()
    }

    /// Reset status to idle
    public func reset() {
        status = .idle
    }
}

// MARK: - Errors

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
