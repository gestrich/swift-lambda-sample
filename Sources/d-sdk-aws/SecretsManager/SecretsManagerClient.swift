import d_sdk_cli
import Foundation

/// Generic service for interacting with AWS Secrets Manager via CLI
/// This service provides Secrets Manager operations without app-specific logic.
public actor SecretsManagerClient {
    private let cliClient: CLIClient
    private let credentialProvider: AWSCredentialProvider

    public init(
        credentialProvider: AWSCredentialProvider,
        cliClient: CLIClient
    ) {
        self.cliClient = cliClient
        self.credentialProvider = credentialProvider
    }

    // MARK: - Command Execution

    /// Execute a typed AWS CLI command
    private func execute<C: CLICommand, P: CLIOutputParser>(
        _ command: C,
        parser: P,
        printCommand: Bool = false
    ) async throws -> P.Output where C.Program == Aws {
        let (execCommand, arguments) = credentialProvider.buildCommandLine(command)

        let result = try await cliClient.execute(
            command: execCommand,
            arguments: arguments,
            environment: credentialProvider.environment,
            printCommand: printCommand
        )

        guard result.isSuccess else {
            throw SecretsManagerError.commandFailed(
                command: command.commandString,
                exitCode: result.exitCode,
                output: result.output
            )
        }

        return try parser.parse(result.stdout)
    }

    /// Execute a typed AWS CLI command and return raw output
    private func execute<C: CLICommand>(
        _ command: C,
        printCommand: Bool = false
    ) async throws -> String where C.Program == Aws {
        try await execute(command, parser: StringParser(), printCommand: printCommand)
    }

    // MARK: - Secrets Manager Operations

    /// Get a secret value by ID
    /// - Parameter secretId: The secret ID or ARN
    /// - Returns: The secret string value
    public func getSecretValue(secretId: String) async throws -> String {
        let command = Aws.SecretsManager.GetSecretValue(
            secretId: secretId,
            profile: credentialProvider.profileName,
            query: "SecretString",
            output: "text"
        )

        return try await execute(command, printCommand: false)
    }

    /// Get a secret as parsed JSON
    /// - Parameter secretId: The secret ID or ARN
    /// - Returns: The secret parsed as a JSON dictionary
    public func getSecretJSON(secretId: String) async throws -> [String: Any] {
        let secretString = try await getSecretValue(secretId: secretId)

        guard let data = secretString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SecretsManagerError.parseError("Failed to parse secret as JSON")
        }

        return json
    }

    /// List all secrets
    /// - Returns: Array of secret info
    public func listSecrets() async throws -> [SecretInfo] {
        let command = Aws.SecretsManager.ListSecrets(
            profile: credentialProvider.profileName,
            output: "json"
        )

        let (execCommand, arguments) = credentialProvider.buildCommandLine(command)

        let result = try await cliClient.execute(
            command: execCommand,
            arguments: arguments,
            environment: credentialProvider.environment,
            printCommand: false
        )

        guard result.isSuccess else {
            throw SecretsManagerError.commandFailed(
                command: "aws secretsmanager list-secrets",
                exitCode: result.exitCode,
                output: result.output
            )
        }

        guard let data = result.stdout.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let secrets = json["SecretList"] as? [[String: Any]] else {
            throw SecretsManagerError.parseError("Failed to parse secrets list")
        }

        return secrets.compactMap { secret in
            guard let name = secret["Name"] as? String,
                  let arn = secret["ARN"] as? String else {
                return nil
            }

            let description = secret["Description"] as? String

            var lastChangedDate: Date?
            if let lastChanged = secret["LastChangedDate"] as? Double {
                lastChangedDate = Date(timeIntervalSince1970: lastChanged)
            }

            return SecretInfo(
                name: name,
                arn: arn,
                description: description,
                lastChangedDate: lastChangedDate
            )
        }
    }

    /// Check if a secret exists
    /// - Parameter secretId: The secret ID or ARN
    /// - Returns: True if the secret exists
    public func secretExists(secretId: String) async throws -> Bool {
        do {
            _ = try await getSecretValue(secretId: secretId)
            return true
        } catch let error as SecretsManagerError {
            if case .secretNotFound = error {
                return false
            }
            if case .commandFailed(_, _, let output) = error {
                if output.contains("ResourceNotFoundException") || output.contains("Secrets Manager can't find") {
                    return false
                }
            }
            throw error
        }
    }
}

// MARK: - Models

/// Secret information from list-secrets
public struct SecretInfo: Sendable, Equatable {
    public let name: String
    public let arn: String
    public let description: String?
    public let lastChangedDate: Date?

    public init(
        name: String,
        arn: String,
        description: String? = nil,
        lastChangedDate: Date? = nil
    ) {
        self.name = name
        self.arn = arn
        self.description = description
        self.lastChangedDate = lastChangedDate
    }
}

// MARK: - Errors

public enum SecretsManagerError: LocalizedError {
    case commandFailed(command: String, exitCode: Int32, output: String)
    case parseError(String)
    case secretNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .commandFailed(let command, let exitCode, let output):
            return "Command '\(command)' failed with exit code \(exitCode): \(output)"
        case .parseError(let reason):
            return "Failed to parse Secrets Manager output: \(reason)"
        case .secretNotFound(let secretId):
            return "Secret '\(secretId)' not found"
        }
    }
}
