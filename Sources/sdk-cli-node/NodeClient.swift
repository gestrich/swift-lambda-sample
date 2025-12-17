import sdk_cli
import Foundation

/// Client for interacting with Node.js CLI
public struct NodeClient: Sendable {
    private let cliClient: CLIClient

    public init(cliClient: CLIClient) {
        self.cliClient = cliClient
    }

    /// Check if Node.js is installed
    public func isInstalled() async -> Bool {
        do {
            let result = try await cliClient.executeForResult(
                Node.Version(),
                printCommand: false
            )
            return result.isSuccess
        } catch {
            return false
        }
    }

    /// Get Node.js version if installed
    public func version() async -> String? {
        do {
            let result = try await cliClient.executeForResult(
                Node.Version(),
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
}
