import d_sdk_cli
import Foundation

/// Client for wrapping AWS commands with aws-vault
public struct AWSVaultClient: Sendable {
    private let profile: String

    public init(profile: String) {
        self.profile = profile
    }

    // MARK: - Command Wrapping

    /// Wrap a command with aws-vault exec
    /// - Parameters:
    ///   - command: The command to wrap (e.g., "aws", "cdk")
    ///   - arguments: Arguments for the command
    /// - Returns: Tuple with aws-vault command and combined arguments
    public func wrapCommand(
        command: String,
        arguments: [String]
    ) -> (command: String, arguments: [String]) {
        var vaultArgs = ["exec", profile, "--", command]
        vaultArgs.append(contentsOf: arguments)
        return ("aws-vault", vaultArgs)
    }

    // MARK: - Installation Check

    /// Check if aws-vault is installed
    /// - Parameter cliClient: The CLI service to use for checking
    /// - Throws: CLIError if aws-vault is not found
    public static func checkInstallation(using cliClient: CLIClient) async throws {
        let result = try? await cliClient.executeForResult(
            Which(command: "aws-vault"),
            printCommand: false
        )

        guard let result = result, result.isSuccess else {
            throw CLIClientError.invalidCommand(
                "aws-vault is not installed. Install it with:\n" +
                "  brew install --cask aws-vault\n\n" +
                "Or disable aws-vault in your config by setting:\n" +
                "  \"useAWSVault\": false"
            )
        }
    }

    // MARK: - Utilities

    /// Remove --profile flags from arguments (aws-vault handles auth via environment)
    /// - Parameter arguments: Original arguments
    /// - Returns: Filtered arguments without --profile flags
    public static func removeProfileFlags(from arguments: [String]) -> [String] {
        var filtered: [String] = []
        var skipNext = false

        for (_, arg) in arguments.enumerated() {
            if skipNext {
                skipNext = false
                continue
            }

            if arg == "--profile" {
                // Skip this and the next argument
                skipNext = true
                continue
            }

            filtered.append(arg)
        }

        return filtered
    }
}
