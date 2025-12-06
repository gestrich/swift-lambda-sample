import CLIKit
import Foundation

/// Service for interacting with AWS CLI
public actor AWSCLIService {
    private let cliService: CLIService
    private let profile: String
    private let vaultService: AWSVaultService?

    public init(awsConfig: AWSAuthConfiguration, cliService: CLIService) {
        self.cliService = cliService
        self.profile = awsConfig.profileName
        self.vaultService = awsConfig.useAWSVault ? AWSVaultService(profile: awsConfig.profileName) : nil
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

        let result = try await cliService.execute(
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
    private func executeForSideEffect<C: CLICommand>(
        _ command: C,
        printCommand: Bool = true
    ) async throws where C.Program == Aws {
        let (execCommand, arguments) = buildCommandLine(command)

        let result = try await cliService.execute(
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
    }

    /// Build command line with optional aws-vault wrapping
    /// - Parameter command: The AWS CLI command
    /// - Returns: Tuple with executable command and arguments
    private func buildCommandLine<C: CLICommand>(_ command: C) -> (command: String, arguments: [String]) where C.Program == Aws {
        let arguments = command.commandArguments

        if let vaultService = vaultService {
            // Remove --profile flags (aws-vault handles auth via environment)
            let filteredArgs = AWSVaultService.removeProfileFlags(from: arguments)
            return vaultService.wrapCommand(command: "aws", arguments: filteredArgs)
        } else {
            // Traditional approach
            return ("aws", arguments)
        }
    }

    // MARK: - CloudFormation

    /// Describe a CloudFormation stack
    public func describeStack(name: String) async throws -> [String: Any] {
        let command = Aws.CloudFormation.DescribeStacks(
            stackName: name,
            profile: profile,
            output: "json"
        )

        let (execCommand, arguments) = buildCommandLine(command)

        let result = try await cliService.execute(
            command: execCommand,
            arguments: arguments,
            environment: ["AWS_PROFILE": profile],
            printCommand: false
        )

        guard result.isSuccess else {
            throw DeployError.commandFailed(
                command: "aws cloudformation describe-stacks",
                exitCode: result.exitCode,
                output: result.output
            )
        }

        guard let data = result.stdout.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let stacks = json["Stacks"] as? [[String: Any]],
              let stack = stacks.first else {
            throw CLIServiceError.invalidOutput(reason: "Failed to parse CloudFormation stack")
        }

        return stack
    }

    /// Get stack status
    public func getStackStatus(name: String) async throws -> String {
        let command = Aws.CloudFormation.DescribeStacks(
            stackName: name,
            profile: profile,
            output: "text",
            query: "Stacks[0].StackStatus"
        )

        return try await execute(command)
    }

    /// Get stack outputs
    public func getStackOutputs(name: String) async throws -> [String: String] {
        let stack = try await describeStack(name: name)

        guard let outputs = stack["Outputs"] as? [[String: Any]] else {
            return [:]
        }

        var outputDict: [String: String] = [:]
        for output in outputs {
            if let key = output["OutputKey"] as? String,
               let value = output["OutputValue"] as? String {
                outputDict[key] = value
            }
        }

        return outputDict
    }

    /// Get a specific stack output value
    public func getStackOutput(stackName: String, outputKey: String) async throws -> String {
        let command = Aws.CloudFormation.DescribeStacks(
            stackName: stackName,
            profile: profile,
            output: "text",
            query: "Stacks[0].Outputs[?OutputKey==`\(outputKey)`].OutputValue"
        )

        let value = try await execute(command)

        guard !value.isEmpty else {
            throw CLIServiceError.invalidOutput(reason: "Output key '\(outputKey)' not found in stack '\(stackName)'")
        }

        return value
    }

    /// Describe stack resources to detect what's deployed
    public func describeStackResources(name: String) async throws -> [CloudFormationStackResource] {
        let command = Aws.CloudFormation.DescribeStackResources(
            stackName: name,
            profile: profile,
            output: "json"
        )

        return try await execute(command, parser: CloudFormationStackResourcesParser())
    }

    /// Get stack events for deployment progress tracking
    public func getStackEvents(name: String, limit: Int = 50) async throws -> [CloudFormationStackEvent] {
        let command = Aws.CloudFormation.DescribeStackEvents(
            stackName: name,
            profile: profile,
            output: "json"
        )

        // Use JSONOutputParser with ISO8601 date decoding
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let parser = JSONOutputParser<CloudFormationStackEventsResponse>(decoder: decoder)

        let response = try await execute(command, parser: parser)
        return Array(response.StackEvents.prefix(limit))
    }

    // MARK: - Lambda

    /// Update Lambda function code
    public func updateLambdaCode(
        functionName: String,
        zipFile: String
    ) async throws {
        let command = Aws.Lambda.UpdateFunctionCode(
            functionName: functionName,
            zipFile: "fileb://\(zipFile)",
            profile: profile
        )

        try await executeForSideEffect(command)
    }

    /// Get Lambda function configuration
    public func getLambdaFunction(name: String) async throws -> [String: Any] {
        let command = Aws.Lambda.GetFunction(
            functionName: name,
            profile: profile,
            output: "json"
        )

        let (execCommand, arguments) = buildCommandLine(command)

        let result = try await cliService.execute(
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
            throw CLIServiceError.invalidOutput(reason: "Failed to parse Lambda function")
        }

        return json
    }

    // MARK: - CloudWatch Logs

    /// Tail CloudWatch logs
    public func tailLogs(
        logGroup: String,
        since: String = "5m",
        format: String = "short",
        follow: Bool = false
    ) async throws {
        let command = Aws.Logs.Tail(
            logGroup: logGroup,
            since: since,
            format: format,
            follow: follow,
            profile: profile
        )

        try await executeForSideEffect(command)
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

        let result = try await cliService.execute(
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
            throw CLIServiceError.invalidOutput(reason: "Failed to parse secrets list")
        }

        return secrets
    }
}

// MARK: - Legacy Types (for backward compatibility)

extension AWSCLIService {
    public typealias StackOutput = CloudFormationStackOutput
    public typealias StackResource = CloudFormationStackResource
}
