import sdk_cli
import Foundation

/// Generic service for interacting with AWS S3 via CLI
/// This service provides S3 operations without app-specific logic.
public actor S3Client {
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
            throw S3Error.commandFailed(
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

    // MARK: - S3 Operations

    /// List objects in an S3 bucket
    /// - Parameters:
    ///   - bucket: The bucket name
    ///   - prefix: Optional prefix to filter objects
    /// - Returns: Array of S3 objects
    public func list(bucket: String, prefix: String = "") async throws -> [S3Object] {
        var path = "s3://\(bucket)/"
        if !prefix.isEmpty {
            path += prefix
        }

        let command = Aws.S3.Ls(path: path, profile: credentialProvider.profileName)

        let (execCommand, arguments) = credentialProvider.buildCommandLine(command)

        let result = try await cliClient.execute(
            command: execCommand,
            arguments: arguments,
            environment: credentialProvider.environment,
            printCommand: false
        )

        guard result.isSuccess else {
            if result.output.contains("NoSuchBucket") {
                throw S3Error.bucketNotFound(bucket)
            }
            throw S3Error.commandFailed(
                command: "aws s3 ls",
                exitCode: result.exitCode,
                output: result.output
            )
        }

        return parseListOutput(result.stdout)
    }

    /// List objects and return raw output string
    /// - Parameters:
    ///   - bucket: The bucket name
    ///   - prefix: Optional prefix to filter objects
    /// - Returns: Raw output string from aws s3 ls
    public func listRaw(bucket: String, prefix: String = "") async throws -> String {
        var path = "s3://\(bucket)/"
        if !prefix.isEmpty {
            path += prefix
        }

        let command = Aws.S3.Ls(path: path, profile: credentialProvider.profileName)

        return try await execute(command, printCommand: false)
    }

    /// Copy a file from S3 to local or stdout
    /// - Parameters:
    ///   - source: Source path (S3 URI or local path)
    ///   - destination: Destination path (S3 URI or local path)
    /// - Returns: Command output
    public func copy(source: String, destination: String) async throws -> String {
        let command = Aws.S3.Cp(
            source: source,
            destination: destination,
            profile: credentialProvider.profileName
        )

        let (execCommand, arguments) = credentialProvider.buildCommandLine(command)

        let result = try await cliClient.execute(
            command: execCommand,
            arguments: arguments,
            environment: credentialProvider.environment,
            printCommand: false
        )

        guard result.isSuccess else {
            if result.output.contains("NoSuchKey") || result.output.contains("404") {
                throw S3Error.objectNotFound(path: source)
            }
            throw S3Error.commandFailed(
                command: "aws s3 cp",
                exitCode: result.exitCode,
                output: result.output
            )
        }

        return result.stdout
    }

    /// Check if an object exists in S3
    /// - Parameters:
    ///   - bucket: The bucket name
    ///   - key: The object key
    /// - Returns: True if the object exists
    public func objectExists(bucket: String, key: String) async throws -> Bool {
        let objects = try await list(bucket: bucket, prefix: key)
        return objects.contains { $0.key == key }
    }

    // MARK: - Parsing

    /// Parse the output of `aws s3 ls` command
    /// Format: "2024-01-15 10:30:45      12345 filename.txt"
    /// or for prefixes: "                           PRE prefix/"
    private func parseListOutput(_ output: String) -> [S3Object] {
        let lines = output.components(separatedBy: .newlines).filter { !$0.isEmpty }
        var objects: [S3Object] = []

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip "PRE" entries (prefixes/directories)
            if trimmed.hasPrefix("PRE ") {
                continue
            }

            // Parse format: "2024-01-15 10:30:45      12345 filename.txt"
            // The format is: date time size key
            let parts = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }

            guard parts.count >= 4 else { continue }

            let dateString = "\(parts[0]) \(parts[1])"
            let lastModified = dateFormatter.date(from: dateString)
            let size = Int64(parts[2])
            let key = parts.dropFirst(3).joined(separator: " ")

            objects.append(S3Object(
                key: key,
                size: size,
                lastModified: lastModified
            ))
        }

        return objects
    }
}

// MARK: - Models

/// S3 object information
public struct S3Object: Sendable, Equatable {
    public let key: String
    public let size: Int64?
    public let lastModified: Date?

    public init(
        key: String,
        size: Int64? = nil,
        lastModified: Date? = nil
    ) {
        self.key = key
        self.size = size
        self.lastModified = lastModified
    }
}

// MARK: - Errors

public enum S3Error: LocalizedError {
    case commandFailed(command: String, exitCode: Int32, output: String)
    case parseError(String)
    case bucketNotFound(String)
    case objectNotFound(path: String)

    public var errorDescription: String? {
        switch self {
        case .commandFailed(let command, let exitCode, let output):
            return "Command '\(command)' failed with exit code \(exitCode): \(output)"
        case .parseError(let reason):
            return "Failed to parse S3 output: \(reason)"
        case .bucketNotFound(let bucket):
            return "S3 bucket '\(bucket)' not found"
        case .objectNotFound(let path):
            return "S3 object not found: \(path)"
        }
    }
}
