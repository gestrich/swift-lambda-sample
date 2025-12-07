//
//  LambdaBuildService.swift
//  SwiftDeploy
//
//  Shared service for building Lambda for Linux using Docker
//

import CLIKit
import Foundation

/// Service for building Lambda for Linux (AMD64) using Docker
@MainActor
@Observable
public class LambdaBuildService {
    private let workingDirectory: String
    private let cliService: CLIService

    /// Build state for tracking progress
    public let buildState = BuildState()

    /// Lambda build artifact paths
    private var lambdaDir: String { "\(workingDirectory)/lambda" }
    private var lambdaZipPath: String { "\(workingDirectory)/lambda.zip" }
    private var bootstrapPath: String { "\(lambdaDir)/bootstrap" }
    private var awsSamBuildDir: String { ".aws-sam/build-SwiftLambda" }

    /// Paths to clean when deleting build artifacts (relative to workingDirectory)
    private var buildArtifactPaths: [String] { ["lambda", "lambda.zip", awsSamBuildDir] }

    public init(workingDirectory: String, cliService: CLIService) {
        self.workingDirectory = workingDirectory
        self.cliService = cliService
    }

    /// Convenience initializer that creates its own CLIService
    public convenience init(workingDirectory: String) {
        let cliService = CLIService(defaultWorkingDirectory: workingDirectory)
        self.init(workingDirectory: workingDirectory, cliService: cliService)
    }

    /// Build Lambda for Linux (AMD64) using Docker
    /// - Parameter clean: If true, cleans previous build artifacts first
    public func build(clean: Bool = false) async throws {
        buildState.startBuild()

        // Clean if requested
        if clean {
            let cleanMsg = "🧹 Cleaning previous build artifacts...\n"
            buildState.appendOutput(cleanMsg)
            do {
                let rmCmd = Rm(recursive: true, force: true, paths: buildArtifactPaths)
                _ = try await cliService.execute(
                    rmCmd,
                    workingDirectory: workingDirectory,
                    printCommand: false
                )
                let successMsg = "  ✅ Cleaned\n"
                buildState.appendOutput(successMsg)
            } catch {
                let errorMsg = "  ❌ Clean failed: \(error)\n"
                buildState.appendOutput(errorMsg)
                buildState.markFailed(exitCode: 1)
                throw BuildError.failed(exitCode: 1)
            }
        }

        let buildMsg = "🔨 Building Lambda for Linux (Docker)...\n"
        buildState.appendOutput(buildMsg)

        // Stream the build output using typed command
        let buildCmd = BuildScript.Build.lambda(target: "SwiftLambda")
        let stream = await cliService.stream(
            buildCmd,
            workingDirectory: workingDirectory,
            printCommand: false
        )

        var exitCode: Int32 = 0
        for await output in stream {
            if let code = buildState.processStreamOutput(output) {
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
}
