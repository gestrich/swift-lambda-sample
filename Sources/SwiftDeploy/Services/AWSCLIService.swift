import Foundation

/// Service for interacting with AWS CLI
public actor AWSCLIService {
    private let cliService: CLIService
    private let profile: String
    private let vaultService: AWSVaultService?

    public init(awsConfig: AWSAuthConfiguration) {
        self.cliService = CLIService.shared
        self.profile = awsConfig.profileName
        self.vaultService = awsConfig.useAWSVault ? AWSVaultService(profile: awsConfig.profileName) : nil
    }

    // MARK: - Command Building

    /// Build AWS CLI command with optional aws-vault wrapping
    /// - Parameter arguments: AWS CLI arguments (without "aws" command)
    /// - Returns: Tuple with command and full arguments
    private func buildCommand(arguments: [String]) -> (command: String, arguments: [String]) {
        if let vaultService = vaultService {
            // Remove --profile flags (aws-vault handles auth via environment)
            let filteredArgs = AWSVaultService.removeProfileFlags(from: arguments)
            return vaultService.wrapCommand(command: "aws", arguments: filteredArgs)
        } else {
            // Traditional approach with --profile
            return ("aws", arguments)
        }
    }

    // MARK: - CloudFormation

    public struct StackOutput {
        public let key: String
        public let value: String
        public let description: String?
        public let exportName: String?
    }

    public struct StackResource: Sendable {
        public let logicalResourceId: String
        public let resourceType: String
        public let resourceStatus: String
    }

    /// Describe a CloudFormation stack
    public func describeStack(name: String) async throws -> [String: Any] {
        let (command, arguments) = buildCommand(arguments: [
            "cloudformation", "describe-stacks",
            "--stack-name", name,
            "--profile", profile,
            "--output", "json"
        ])

        let result = try await cliService.execute(
            command: command,
            arguments: arguments,
            environment: ["AWS_PROFILE": profile],
            printCommand: false
        )

        guard result.isSuccess else {
            throw DeployError.commandFailed(
                command: "aws cloudformation describe-stacks",
                exitCode: result.exitCode,
                stderr: result.stderr
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
        let (command, arguments) = buildCommand(arguments: [
            "cloudformation", "describe-stacks",
            "--stack-name", name,
            "--profile", profile,
            "--query", "Stacks[0].StackStatus",
            "--output", "text"
        ])

        let result = try await cliService.execute(
            command: command,
            arguments: arguments,
            environment: ["AWS_PROFILE": profile],
            printCommand: false
        )

        guard result.isSuccess else {
            throw DeployError.commandFailed(
                command: "aws cloudformation describe-stacks",
                exitCode: result.exitCode,
                stderr: result.stderr
            )
        }

        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
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
        let (command, arguments) = buildCommand(arguments: [
            "cloudformation", "describe-stacks",
            "--stack-name", stackName,
            "--profile", profile,
            "--query", "Stacks[0].Outputs[?OutputKey==`\(outputKey)`].OutputValue",
            "--output", "text"
        ])

        let result = try await cliService.execute(
            command: command,
            arguments: arguments,
            environment: ["AWS_PROFILE": profile],
            printCommand: false
        )

        guard result.isSuccess else {
            throw DeployError.commandFailed(
                command: "aws cloudformation describe-stacks",
                exitCode: result.exitCode,
                stderr: result.stderr
            )
        }

        let value = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !value.isEmpty else {
            throw CLIServiceError.invalidOutput(reason: "Output key '\(outputKey)' not found in stack '\(stackName)'")
        }

        return value
    }

    /// Describe stack resources to detect what's deployed
    public func describeStackResources(name: String) async throws -> [StackResource] {
        let (command, arguments) = buildCommand(arguments: [
            "cloudformation", "describe-stack-resources",
            "--stack-name", name,
            "--profile", profile,
            "--output", "json"
        ])

        let result = try await cliService.execute(
            command: command,
            arguments: arguments,
            environment: ["AWS_PROFILE": profile],
            printCommand: false
        )

        guard result.isSuccess else {
            throw DeployError.commandFailed(
                command: "aws cloudformation describe-stack-resources",
                exitCode: result.exitCode,
                stderr: result.stderr
            )
        }

        guard let data = result.stdout.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let resourcesArray = json["StackResources"] as? [[String: Any]] else {
            throw CLIServiceError.invalidOutput(reason: "Failed to parse CloudFormation stack resources")
        }

        return resourcesArray.compactMap { resource in
            guard let logicalId = resource["LogicalResourceId"] as? String,
                  let resourceType = resource["ResourceType"] as? String,
                  let resourceStatus = resource["ResourceStatus"] as? String else {
                return nil
            }

            return StackResource(
                logicalResourceId: logicalId,
                resourceType: resourceType,
                resourceStatus: resourceStatus
            )
        }
    }

    // MARK: - Lambda

    /// Update Lambda function code
    public func updateLambdaCode(
        functionName: String,
        zipFile: String
    ) async throws {
        let (command, arguments) = buildCommand(arguments: [
            "lambda", "update-function-code",
            "--function-name", functionName,
            "--zip-file", "fileb://\(zipFile)",
            "--profile", profile
        ])

        let result = try await cliService.execute(
            command: command,
            arguments: arguments,
            environment: ["AWS_PROFILE": profile]
        )

        guard result.isSuccess else {
            throw DeployError.commandFailed(
                command: "aws lambda update-function-code",
                exitCode: result.exitCode,
                stderr: result.stderr
            )
        }
    }

    /// Get Lambda function configuration
    public func getLambdaFunction(name: String) async throws -> [String: Any] {
        let (command, arguments) = buildCommand(arguments: [
            "lambda", "get-function",
            "--function-name", name,
            "--profile", profile,
            "--output", "json"
        ])

        let result = try await cliService.execute(
            command: command,
            arguments: arguments,
            environment: ["AWS_PROFILE": profile],
            printCommand: false
        )

        guard result.isSuccess else {
            throw DeployError.commandFailed(
                command: "aws lambda get-function",
                exitCode: result.exitCode,
                stderr: result.stderr
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
        var awsArguments = [
            "logs", "tail",
            logGroup,
            "--since", since,
            "--format", format,
            "--profile", profile
        ]

        if follow {
            awsArguments.append("--follow")
        }

        let (command, arguments) = buildCommand(arguments: awsArguments)

        let result = try await cliService.execute(
            command: command,
            arguments: arguments,
            environment: ["AWS_PROFILE": profile]
        )

        guard result.isSuccess else {
            throw DeployError.commandFailed(
                command: "aws logs tail",
                exitCode: result.exitCode,
                stderr: result.stderr
            )
        }
    }

    // MARK: - S3

    /// List objects in an S3 bucket
    public func s3List(bucket: String, prefix: String = "") async throws -> String {
        var path = "s3://\(bucket)/"
        if !prefix.isEmpty {
            path += prefix
        }

        let (command, arguments) = buildCommand(arguments: [
            "s3", "ls",
            path,
            "--profile", profile
        ])

        let result = try await cliService.execute(
            command: command,
            arguments: arguments,
            environment: ["AWS_PROFILE": profile],
            printCommand: false
        )

        guard result.isSuccess else {
            throw DeployError.commandFailed(
                command: "aws s3 ls",
                exitCode: result.exitCode,
                stderr: result.stderr
            )
        }

        return result.stdout
    }

    /// Copy a file from S3 to local or stdout
    public func s3Copy(
        source: String,
        destination: String
    ) async throws -> String {
        let (command, arguments) = buildCommand(arguments: [
            "s3", "cp",
            source,
            destination,
            "--profile", profile
        ])

        let result = try await cliService.execute(
            command: command,
            arguments: arguments,
            environment: ["AWS_PROFILE": profile],
            printCommand: false
        )

        guard result.isSuccess else {
            throw DeployError.commandFailed(
                command: "aws s3 cp",
                exitCode: result.exitCode,
                stderr: result.stderr
            )
        }

        return result.stdout
    }

    // MARK: - Secrets Manager

    /// Get a secret value
    public func getSecretValue(secretId: String) async throws -> String {
        let (command, arguments) = buildCommand(arguments: [
            "secretsmanager", "get-secret-value",
            "--secret-id", secretId,
            "--profile", profile,
            "--query", "SecretString",
            "--output", "text"
        ])

        let result = try await cliService.execute(
            command: command,
            arguments: arguments,
            environment: ["AWS_PROFILE": profile],
            printCommand: false
        )

        guard result.isSuccess else {
            throw DeployError.commandFailed(
                command: "aws secretsmanager get-secret-value",
                exitCode: result.exitCode,
                stderr: result.stderr
            )
        }

        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// List secrets
    public func listSecrets() async throws -> [[String: Any]] {
        let (command, arguments) = buildCommand(arguments: [
            "secretsmanager", "list-secrets",
            "--profile", profile,
            "--output", "json"
        ])

        let result = try await cliService.execute(
            command: command,
            arguments: arguments,
            environment: ["AWS_PROFILE": profile],
            printCommand: false
        )

        guard result.isSuccess else {
            throw DeployError.commandFailed(
                command: "aws secretsmanager list-secrets",
                exitCode: result.exitCode,
                stderr: result.stderr
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
