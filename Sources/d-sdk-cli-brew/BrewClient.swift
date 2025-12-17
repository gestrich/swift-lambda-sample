import CLISDK
import Foundation

/// Client for interacting with Homebrew CLI
public struct BrewClient: Sendable {
    private let cliClient: CLIClient

    public init(cliClient: CLIClient) {
        self.cliClient = cliClient
    }

    /// Check if Homebrew is installed
    public func isInstalled() async -> Bool {
        do {
            let result = try await cliClient.executeForResult(
                Brew.Version(),
                printCommand: false
            )
            return result.isSuccess
        } catch {
            return false
        }
    }

    /// Get Homebrew version if installed
    public func version() async -> String? {
        do {
            let result = try await cliClient.executeForResult(
                Brew.Version(),
                printCommand: false
            )
            guard result.isSuccess else { return nil }
            return result.stdout
                .components(separatedBy: .newlines)
                .first?
                .trimmingCharacters(in: .whitespaces)
        } catch {
            return nil
        }
    }

    /// Install a package
    public func install(_ package: String, cask: Bool = false) async throws {
        let command = Brew.Install(cask: cask, package: package)
        let result = try await cliClient.executeForResult(command)
        guard result.isSuccess else {
            throw BrewError.commandFailed(
                command: command.commandString,
                exitCode: result.exitCode,
                output: result.errorOutput
            )
        }
    }

    /// Uninstall a package
    public func uninstall(_ package: String, cask: Bool = false) async throws {
        let command = Brew.Uninstall(cask: cask, package: package)
        let result = try await cliClient.executeForResult(command)
        guard result.isSuccess else {
            throw BrewError.commandFailed(
                command: command.commandString,
                exitCode: result.exitCode,
                output: result.errorOutput
            )
        }
    }
}
