import sdk_cli
import sdk_aws
import Foundation

/// Service for interacting with AWS CLI
public actor AWSCLIService {
    private let cliClient: CLIClient
    private let profile: String
    private let vaultClient: AWSVaultClient?

    public init(awsConfig: AWSAuthConfiguration, cliClient: CLIClient) {
        self.cliClient = cliClient
        self.profile = awsConfig.profileName
        self.vaultClient = awsConfig.useAWSVault ? AWSVaultClient(profile: awsConfig.profileName) : nil
    }

    // MARK: - Command Execution

    /// Execute a typed AWS CLI command
    /// - Parameters:
    ///   - command: The AWS CLI command to execute
    ///   - parser: Parser to transform output
    ///   - printCommand: Whether to print the command
    /// - Returns: Parsed output
    private func execute<C: CLICommand, P: CLIOutputParser>(
        _ command: C,
        parser: P,
        printCommand: Bool = false
    ) async throws -> P.Output where C.Program == Aws {
        let (execCommand, arguments) = buildCommandLine(command)

        let result = try await cliClient.execute(
            command: execCommand,
            arguments: arguments,
            environment: ["AWS_PROFILE": profile],
            printCommand: printCommand
        )

        guard result.isSuccess else {
            throw DeployError.commandFailed(
                command: command.commandString,
                exitCode: result.exitCode,
                output: result.output
            )
        }

        return try parser.parse(result.stdout)
    }

    /// Execute a typed AWS CLI command and return raw output
    /// - Parameters:
    ///   - command: The AWS CLI command to execute
    ///   - printCommand: Whether to print the command
    /// - Returns: Trimmed stdout string
    private func execute<C: CLICommand>(
        _ command: C,
        printCommand: Bool = false
    ) async throws -> String where C.Program == Aws {
        try await execute(command, parser: StringParser(), printCommand: printCommand)
    }

    /// Execute a typed AWS CLI command without returning output (for side-effect commands)
    /// - Parameters:
    ///   - command: The AWS CLI command to execute
    ///   - printCommand: Whether to print the command
    ///   - output: Optional client-owned stream to receive output (in addition to global stream)
    private func executeForSideEffect<C: CLICommand>(
        _ command: C,
        printCommand: Bool = true,
        output: CLIOutputStream? = nil
    ) async throws where C.Program == Aws {
        let (execCommand, arguments) = buildCommandLine(command)

        let result = try await cliClient.execute(
            command: execCommand,
            arguments: arguments,
            environment: ["AWS_PROFILE": profile],
            printCommand: printCommand,
            output: output
        )

        guard result.isSuccess else {
            throw DeployError.commandFailed(
                command: command.commandString,
                exitCode: result.exitCode,
                output: result.output
            )
        }
    }

    /// Build command line with optional aws-vault wrapping
    /// - Parameter command: The AWS CLI command
    /// - Returns: Tuple with executable command and arguments
    private func buildCommandLine<C: CLICommand>(_ command: C) -> (command: String, arguments: [String]) where C.Program == Aws {
        let arguments = command.commandArguments

        if let vaultClient = vaultClient {
            // Remove --profile flags (aws-vault handles auth via environment)
            let filteredArgs = AWSVaultClient.removeProfileFlags(from: arguments)
            return vaultClient.wrapCommand(command: "aws", arguments: filteredArgs)
        } else {
            // Traditional approach
            return ("aws", arguments)
        }
    }

    // MARK: - Lambda

    /// Update Lambda function code
    /// - Parameters:
    ///   - functionName: Name of the Lambda function
    ///   - zipFile: Path to the zip file
    ///   - output: Optional client-owned stream to receive output (in addition to global stream)
    public func updateLambdaCode(
        functionName: String,
        zipFile: String,
        output: CLIOutputStream? = nil
    ) async throws {
        let command = Aws.Lambda.UpdateFunctionCode(
            functionName: functionName,
            zipFile: "fileb://\(zipFile)",
            profile: profile
        )

        try await executeForSideEffect(command, output: output)
    }

    /// Get Lambda function configuration
    public func getLambdaFunction(name: String) async throws -> [String: Any] {
        let command = Aws.Lambda.GetFunction(
            functionName: name,
            profile: profile,
            output: "json"
        )

        let (execCommand, arguments) = buildCommandLine(command)

        let result = try await cliClient.execute(
            command: execCommand,
            arguments: arguments,
            environment: ["AWS_PROFILE": profile],
            printCommand: false
        )

        guard result.isSuccess else {
            throw DeployError.commandFailed(
                command: "aws lambda get-function",
                exitCode: result.exitCode,
                output: result.output
            )
        }

        guard let data = result.stdout.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CLIClientError.invalidOutput(reason: "Failed to parse Lambda function")
        }

        return json
    }

    // MARK: - S3

    /// List objects in an S3 bucket
    public func s3List(bucket: String, prefix: String = "") async throws -> String {
        var path = "s3://\(bucket)/"
        if !prefix.isEmpty {
            path += prefix
        }

        let command = Aws.S3.Ls(path: path, profile: profile)

        return try await execute(command, printCommand: false)
    }

    /// Copy a file from S3 to local or stdout
    public func s3Copy(
        source: String,
        destination: String
    ) async throws -> String {
        let command = Aws.S3.Cp(
            source: source,
            destination: destination,
            profile: profile
        )

        return try await execute(command, printCommand: false)
    }

    // MARK: - Secrets Manager

    /// Get a secret value
    public func getSecretValue(secretId: String) async throws -> String {
        let command = Aws.SecretsManager.GetSecretValue(
            secretId: secretId,
            profile: profile,
            query: "SecretString",
            output: "text"
        )

        return try await execute(command, printCommand: false)
    }

    /// List secrets
    public func listSecrets() async throws -> [[String: Any]] {
        let command = Aws.SecretsManager.ListSecrets(
            profile: profile,
            output: "json"
        )

        let (execCommand, arguments) = buildCommandLine(command)

        let result = try await cliClient.execute(
            command: execCommand,
            arguments: arguments,
            environment: ["AWS_PROFILE": profile],
            printCommand: false
        )

        guard result.isSuccess else {
            throw DeployError.commandFailed(
                command: "aws secretsmanager list-secrets",
                exitCode: result.exitCode,
                output: result.output
            )
        }

        guard let data = result.stdout.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let secrets = json["SecretList"] as? [[String: Any]] else {
            throw CLIClientError.invalidOutput(reason: "Failed to parse secrets list")
        }

        return secrets
    }
}

