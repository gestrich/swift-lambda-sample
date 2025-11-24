import Foundation

/// Service for wrapping AWS commands with aws-vault
public struct AWSVaultService {
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
    /// - Throws: CLIError if aws-vault is not found
    public static func checkInstallation() async throws {
        let cliService = CLIService.shared
        let result = try? await cliService.execute(
            command: "which",
            arguments: ["aws-vault"],
            printCommand: false
        )

        guard let result = result, result.isSuccess else {
            throw CLIError.invalidCommand(
                "aws-vault is not installed. Install it with:\n" +
                "  brew install --cask aws-vault\n\n" +
                "Or disable aws-vault in ~/.swiftSampleDemo/aws-config.json by setting:\n" +
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
