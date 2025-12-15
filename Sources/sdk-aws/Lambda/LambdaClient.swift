import sdk_cli
import Foundation

/// Generic service for interacting with AWS Lambda via CLI
/// This service provides Lambda operations without app-specific logic.
public actor LambdaClient {
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
            throw LambdaError.commandFailed(
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

    /// Execute a typed AWS CLI command without returning output (for side-effect commands)
    private func executeForSideEffect<C: CLICommand>(
        _ command: C,
        printCommand: Bool = true,
        output: CLIOutputStream? = nil
    ) async throws where C.Program == Aws {
        let (execCommand, arguments) = credentialProvider.buildCommandLine(command)

        let result = try await cliClient.execute(
            command: execCommand,
            arguments: arguments,
            environment: credentialProvider.environment,
            printCommand: printCommand,
            output: output
        )

        guard result.isSuccess else {
            throw LambdaError.commandFailed(
                command: command.commandString,
                exitCode: result.exitCode,
                output: result.output
            )
        }
    }

    // MARK: - Lambda Operations

    /// Update Lambda function code from a zip file
    /// - Parameters:
    ///   - functionName: Name of the Lambda function
    ///   - zipFile: Path to the zip file
    ///   - output: Optional client-owned stream to receive output (in addition to global stream)
    public func updateFunctionCode(
        functionName: String,
        zipFile: String,
        output: CLIOutputStream? = nil
    ) async throws {
        let command = Aws.Lambda.UpdateFunctionCode(
            functionName: functionName,
            zipFile: "fileb://\(zipFile)",
            profile: credentialProvider.profileName
        )

        try await executeForSideEffect(command, output: output)
    }

    /// Get Lambda function configuration
    /// - Parameter name: The function name
    /// - Returns: Lambda function information
    public func getFunction(name: String) async throws -> LambdaFunction {
        let command = Aws.Lambda.GetFunction(
            functionName: name,
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
            if result.output.contains("ResourceNotFoundException") || result.output.contains("Function not found") {
                throw LambdaError.functionNotFound(name)
            }
            throw LambdaError.commandFailed(
                command: "aws lambda get-function",
                exitCode: result.exitCode,
                output: result.output
            )
        }

        guard let data = result.stdout.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let configuration = json["Configuration"] as? [String: Any] else {
            throw LambdaError.parseError("Failed to parse Lambda function response")
        }

        return LambdaFunction(
            functionName: configuration["FunctionName"] as? String ?? name,
            functionArn: configuration["FunctionArn"] as? String ?? "",
            runtime: configuration["Runtime"] as? String,
            handler: configuration["Handler"] as? String,
            codeSize: configuration["CodeSize"] as? Int64,
            lastModified: configuration["LastModified"] as? String
        )
    }

    /// Check if a Lambda function exists
    /// - Parameter name: The function name
    /// - Returns: True if the function exists
    public func functionExists(name: String) async throws -> Bool {
        do {
            _ = try await getFunction(name: name)
            return true
        } catch let error as LambdaError {
            if case .functionNotFound = error {
                return false
            }
            throw error
        }
    }
}

// MARK: - Models

/// Lambda function information
public struct LambdaFunction: Sendable, Equatable {
    public let functionName: String
    public let functionArn: String
    public let runtime: String?
    public let handler: String?
    public let codeSize: Int64?
    public let lastModified: String?

    public init(
        functionName: String,
        functionArn: String,
        runtime: String? = nil,
        handler: String? = nil,
        codeSize: Int64? = nil,
        lastModified: String? = nil
    ) {
        self.functionName = functionName
        self.functionArn = functionArn
        self.runtime = runtime
        self.handler = handler
        self.codeSize = codeSize
        self.lastModified = lastModified
    }
}

// MARK: - Errors

public enum LambdaError: LocalizedError {
    case commandFailed(command: String, exitCode: Int32, output: String)
    case parseError(String)
    case functionNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .commandFailed(let command, let exitCode, let output):
            return "Command '\(command)' failed with exit code \(exitCode): \(output)"
        case .parseError(let reason):
            return "Failed to parse Lambda output: \(reason)"
        case .functionNotFound(let name):
            return "Lambda function '\(name)' not found"
        }
    }
}
