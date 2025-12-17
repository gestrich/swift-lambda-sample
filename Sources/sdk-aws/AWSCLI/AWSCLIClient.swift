import sdk_cli
import Foundation

/// Client for checking AWS CLI installation
public struct AWSCLIClient: Sendable {
    private let cliClient: CLIClient

    public init(cliClient: CLIClient) {
        self.cliClient = cliClient
    }

    /// Check if AWS CLI is installed
    public func isInstalled() async -> Bool {
        do {
            let result = try await cliClient.executeForResult(
                Aws.Version(),
                printCommand: false
            )
            return result.isSuccess
        } catch {
            return false
        }
    }

    /// Get AWS CLI version if installed
    public func version() async -> String? {
        do {
            let result = try await cliClient.executeForResult(
                Aws.Version(),
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
