import sdk_cli
import Foundation

/// Generic service for interacting with AWS CloudFormation via CLI
/// This service provides CloudFormation operations without app-specific logic.
public actor CloudFormationClient {
    private let cliService: CLIClient
    private let credentialProvider: AWSCredentialProvider

    public init(
        credentialProvider: AWSCredentialProvider,
        cliService: CLIClient
    ) {
        self.cliService = cliService
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

        let result = try await cliService.execute(
            command: execCommand,
            arguments: arguments,
            environment: credentialProvider.environment,
            printCommand: printCommand
        )

        guard result.isSuccess else {
            throw CloudFormationError.commandFailed(
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

    // MARK: - Stack Operations

    /// Describe a CloudFormation stack
    /// - Parameter name: The stack name
    /// - Returns: Stack information as a dictionary
    public func describeStack(name: String) async throws -> [String: Any] {
        let command = Aws.CloudFormation.DescribeStacks(
            stackName: name,
            profile: credentialProvider.profileName,
            output: "json"
        )

        let (execCommand, arguments) = credentialProvider.buildCommandLine(command)

        let result = try await cliService.execute(
            command: execCommand,
            arguments: arguments,
            environment: credentialProvider.environment,
            printCommand: false
        )

        guard result.isSuccess else {
            throw CloudFormationError.commandFailed(
                command: "aws cloudformation describe-stacks",
                exitCode: result.exitCode,
                output: result.output
            )
        }

        guard let data = result.stdout.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let stacks = json["Stacks"] as? [[String: Any]],
              let stack = stacks.first else {
            throw CloudFormationError.parseError("Failed to parse CloudFormation stack")
        }

        return stack
    }

    /// Get stack status
    /// - Parameter name: The stack name
    /// - Returns: Stack status string
    public func getStackStatus(name: String) async throws -> String {
        let command = Aws.CloudFormation.DescribeStacks(
            stackName: name,
            profile: credentialProvider.profileName,
            output: "text",
            query: "Stacks[0].StackStatus"
        )

        return try await execute(command)
    }

    /// Get stack outputs as a dictionary
    /// - Parameter name: The stack name
    /// - Returns: Dictionary of output key to value
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
    /// - Parameters:
    ///   - stackName: The stack name
    ///   - outputKey: The output key to retrieve
    /// - Returns: The output value
    public func getStackOutput(stackName: String, outputKey: String) async throws -> String {
        let command = Aws.CloudFormation.DescribeStacks(
            stackName: stackName,
            profile: credentialProvider.profileName,
            output: "text",
            query: "Stacks[0].Outputs[?OutputKey==`\(outputKey)`].OutputValue"
        )

        let value = try await execute(command)

        guard !value.isEmpty else {
            throw CloudFormationError.outputNotFound(key: outputKey, stackName: stackName)
        }

        return value
    }

    /// Describe stack resources
    /// - Parameter name: The stack name
    /// - Returns: Array of stack resources
    public func describeStackResources(name: String) async throws -> [CloudFormationStackResource] {
        let command = Aws.CloudFormation.DescribeStackResources(
            stackName: name,
            profile: credentialProvider.profileName,
            output: "json"
        )

        return try await execute(command, parser: CloudFormationStackResourcesParser())
    }

    /// Get stack events for deployment progress tracking
    /// - Parameters:
    ///   - name: The stack name
    ///   - limit: Maximum number of events to return (default: 50)
    /// - Returns: Array of stack events
    public func getStackEvents(name: String, limit: Int = 50) async throws -> [CloudFormationStackEvent] {
        let command = Aws.CloudFormation.DescribeStackEvents(
            stackName: name,
            profile: credentialProvider.profileName,
            output: "json"
        )

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let parser = JSONOutputParser<CloudFormationStackEventsResponse>(decoder: decoder)

        let response = try await execute(command, parser: parser)
        return Array(response.StackEvents.prefix(limit))
    }

    /// Check if a stack exists
    /// - Parameter name: The stack name
    /// - Returns: True if the stack exists
    public func stackExists(name: String) async throws -> Bool {
        do {
            _ = try await describeStack(name: name)
            return true
        } catch let error as CloudFormationError {
            if case .commandFailed(_, _, let output) = error,
               output.contains("does not exist") {
                return false
            }
            throw error
        }
    }
}

// MARK: - Errors

public enum CloudFormationError: LocalizedError {
    case commandFailed(command: String, exitCode: Int32, output: String)
    case parseError(String)
    case outputNotFound(key: String, stackName: String)
    case stackNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .commandFailed(let command, let exitCode, let output):
            return "Command '\(command)' failed with exit code \(exitCode): \(output)"
        case .parseError(let reason):
            return "Failed to parse CloudFormation output: \(reason)"
        case .outputNotFound(let key, let stackName):
            return "Output key '\(key)' not found in stack '\(stackName)'"
        case .stackNotFound(let name):
            return "Stack '\(name)' not found"
        }
    }
}
