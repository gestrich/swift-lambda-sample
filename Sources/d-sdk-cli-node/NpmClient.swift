import CLISDK
import Foundation

/// Client for interacting with npm CLI
public struct NpmClient: Sendable {
    private let cliClient: CLIClient

    public init(cliClient: CLIClient) {
        self.cliClient = cliClient
    }

    /// Run an npm script
    public func run(_ script: String, workingDirectory: String? = nil) async throws {
        let command = Npm.Run(script: script)
        let fullCommand: String
        if let workDir = workingDirectory {
            fullCommand = "cd \"\(workDir)\" && \(command.commandString)"
        } else {
            fullCommand = command.commandString
        }

        let result = try await cliClient.executeForResult(Sh(command: fullCommand))
        guard result.isSuccess else {
            throw NodeError.commandFailed(
                command: command.commandString,
                exitCode: result.exitCode,
                output: result.errorOutput
            )
        }
    }

    /// Install npm packages
    public func install(package: String? = nil, global: Bool = false, workingDirectory: String? = nil) async throws {
        let command = Npm.Install(global: global, package: package)
        let fullCommand: String
        if let workDir = workingDirectory {
            fullCommand = "cd \"\(workDir)\" && \(command.commandString)"
        } else {
            fullCommand = command.commandString
        }

        let result = try await cliClient.executeForResult(Sh(command: fullCommand))
        guard result.isSuccess else {
            throw NodeError.commandFailed(
                command: command.commandString,
                exitCode: result.exitCode,
                output: result.errorOutput
            )
        }
    }

    /// Uninstall an npm package
    public func uninstall(_ package: String, global: Bool = false) async throws {
        let command = Npm.Uninstall(global: global, package: package)
        let result = try await cliClient.executeForResult(command)
        guard result.isSuccess else {
            throw NodeError.commandFailed(
                command: command.commandString,
                exitCode: result.exitCode,
                output: result.errorOutput
            )
        }
    }
}
