import Foundation

/// A service for executing command-line operations with async/await support
public actor CLIService {
    /// Shared instance for convenience
    public static let shared = CLIService()

    /// Pre-computed environment with common paths
    private let defaultEnvironment: [String: String]

    /// Cache for executable paths
    private var executableCache: [String: String] = [:]

    public init() {
        // Pre-compute environment with git paths
        var environment = ProcessInfo.processInfo.environment
        let currentPath = environment["PATH"] ?? ""
        let brewPaths = ["/opt/homebrew/bin", "/usr/local/bin"]
        let pathComponents = currentPath.components(separatedBy: ":")

        // Add brew paths if they're not already in PATH
        var updatedPathComponents = pathComponents
        for brewPath in brewPaths {
            if !pathComponents.contains(brewPath) {
                updatedPathComponents.insert(brewPath, at: 0)
            }
        }

        environment["PATH"] = updatedPathComponents.joined(separator: ":")
        self.defaultEnvironment = environment
    }

    /// Execute a command with full control over the execution environment
    /// - Parameters:
    ///   - command: The command to execute (can be a path or command name)
    ///   - arguments: Arguments to pass to the command
    ///   - workingDirectory: Working directory for the command
    ///   - environment: Custom environment variables (merged with defaults)
    ///   - timeout: Optional timeout in seconds
    ///   - printCommand: If true, prints the formatted command before execution
    ///   - inheritIO: If true, inherits stdin/stdout/stderr from parent process (for interactive commands)
    /// - Returns: ExecutionResult containing exit code, stdout, and stderr
    public func execute(
        command: String,
        arguments: [String] = [],
        workingDirectory: String? = nil,
        environment: [String: String]? = nil,
        timeout: TimeInterval? = nil,
        printCommand: Bool = true,
        inheritIO: Bool = false
    ) async throws -> ExecutionResult {
        let startTime = Date()

        // Resolve command path
        let resolvedCommand = try resolveCommand(command)

        // Merge environments
        var processEnvironment = defaultEnvironment
        if let customEnvironment = environment {
            for (key, value) in customEnvironment {
                processEnvironment[key] = value
            }
        }

        // Print command if requested
        if printCommand {
            let formattedCommand = formatCommand(
                command: resolvedCommand,
                arguments: arguments,
                environment: environment
            )
            print("→ \(formattedCommand)")
        }

        return try await executeProcess(
            command: resolvedCommand,
            arguments: arguments,
            workingDirectory: workingDirectory,
            environment: processEnvironment,
            timeout: timeout,
            startTime: startTime,
            inheritIO: inheritIO
        )
    }

    /// Convenience method for simple command execution
    /// - Parameters:
    ///   - command: Command string (can include arguments)
    ///   - directory: Working directory
    /// - Returns: The stdout output as a string
    public func run(
        _ command: String,
        in directory: String? = nil
    ) async throws -> String {
        let components = command.components(separatedBy: " ")
        guard !components.isEmpty else {
            throw CLIServiceError.invalidCommand("Empty command")
        }

        let executable = components[0]
        let arguments = Array(components.dropFirst())

        let result = try await execute(
            command: executable,
            arguments: arguments,
            workingDirectory: directory
        )

        if result.exitCode != 0 {
            throw CLIServiceError.executionFailed(
                command: command,
                exitCode: result.exitCode,
                stderr: result.stderr
            )
        }

        return result.stdout
    }

    /// Execute a command and stream its output
    /// - Parameters:
    ///   - command: The command to execute
    ///   - arguments: Arguments to pass to the command
    ///   - workingDirectory: Working directory for the command
    ///   - environment: Custom environment variables
    ///   - printCommand: If true, prints the formatted command before execution
    /// - Returns: AsyncStream of output lines
    public func stream(
        command: String,
        arguments: [String] = [],
        workingDirectory: String? = nil,
        environment: [String: String]? = nil,
        printCommand: Bool = true
    ) -> AsyncStream<StreamOutput> {
        AsyncStream { continuation in
            Task {
                do {
                    let resolvedCommand = try resolveCommand(command)

                    var processEnvironment = defaultEnvironment
                    if let customEnvironment = environment {
                        for (key, value) in customEnvironment {
                            processEnvironment[key] = value
                        }
                    }

                    // Print command if requested
                    if printCommand {
                        let formattedCommand = formatCommand(
                            command: resolvedCommand,
                            arguments: arguments,
                            environment: environment
                        )
                        print("→ \(formattedCommand)")
                    }

                    try streamProcess(
                        command: resolvedCommand,
                        arguments: arguments,
                        workingDirectory: workingDirectory,
                        environment: processEnvironment,
                        continuation: continuation
                    )
                } catch {
                    continuation.yield(.error(error))
                    continuation.finish()
                }
            }
        }
    }

    // MARK: - Private Methods

    private func formatCommand(
        command: String,
        arguments: [String] = [],
        environment: [String: String]? = nil
    ) -> String {
        var parts: [String] = []

        // Add environment variables
        if let environment {
            for (key, value) in environment.sorted(by: { $0.key < $1.key }) {
                parts.append("\(key)='\(value)'")
            }
        }

        // Add command
        parts.append(command)

        // Add arguments (properly quoted)
        for arg in arguments {
            if arg.contains(" ") || arg.contains("'") || arg.contains("\"") {
                // Escape single quotes and wrap in single quotes
                let escaped = arg.replacingOccurrences(of: "'", with: "'\\''")
                parts.append("'\(escaped)'")
            } else {
                parts.append(arg)
            }
        }

        return parts.joined(separator: " ")
    }

    private func resolveCommand(_ command: String) throws -> String {
        // If it's already an absolute path, use it
        if command.starts(with: "/") {
            guard FileManager.default.fileExists(atPath: command) else {
                throw CLIServiceError.commandNotFound(command)
            }
            return command
        }

        // Check cache
        if let cached = executableCache[command] {
            return cached
        }

        // Common direct paths
        let commonPaths = [
            "/usr/bin/\(command)",
            "/bin/\(command)",
            "/usr/local/bin/\(command)",
            "/opt/homebrew/bin/\(command)"
        ]

        for path in commonPaths {
            if FileManager.default.fileExists(atPath: path) {
                executableCache[command] = path
                return path
            }
        }

        // Fall back to using 'which' command
        let which = Process()
        which.launchPath = "/usr/bin/which"
        which.arguments = [command]
        which.environment = defaultEnvironment

        let pipe = Pipe()
        which.standardOutput = pipe
        which.standardError = Pipe()

        try which.run()
        which.waitUntilExit()

        if which.terminationStatus == 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !path.isEmpty {
                executableCache[command] = path
                return path
            }
        }

        throw CLIServiceError.commandNotFound(command)
    }

    private func executeProcess(
        command: String,
        arguments: [String],
        workingDirectory: String?,
        environment: [String: String],
        timeout: TimeInterval?,
        startTime: Date,
        inheritIO: Bool
    ) async throws -> ExecutionResult {
        return try self.executeProcessInternal(
            command: command,
            arguments: arguments,
            workingDirectory: workingDirectory,
            environment: environment,
            timeout: timeout,
            startTime: startTime,
            inheritIO: inheritIO
        )
    }

    private func executeProcessInternal(
        command: String,
        arguments: [String],
        workingDirectory: String?,
        environment: [String: String],
        timeout: TimeInterval?,
        startTime: Date,
        inheritIO: Bool
    ) throws -> ExecutionResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments
        process.environment = environment

        if let workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        }

        let outputPipe: Pipe?
        let errorPipe: Pipe?

        if inheritIO {
            // For interactive commands, inherit stdin/stdout/stderr
            process.standardInput = FileHandle.standardInput
            process.standardOutput = FileHandle.standardOutput
            process.standardError = FileHandle.standardError
            outputPipe = nil
            errorPipe = nil
        } else {
            // For non-interactive commands, capture output
            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe
            outputPipe = outPipe
            errorPipe = errPipe
        }

        var timeoutTask: Task<Void, Never>?
        if let timeout {
            timeoutTask = Task {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                if process.isRunning {
                    process.terminate()
                }
            }
        }

        try process.run()
        process.waitUntilExit()

        timeoutTask?.cancel()

        // Read output after process completes (only if not inheriting IO)
        let stdout: String
        let stderr: String

        if inheritIO {
            stdout = ""
            stderr = ""
        } else {
            let outputData = outputPipe!.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe!.fileHandleForReading.readDataToEndOfFile()
            stdout = String(data: outputData, encoding: .utf8) ?? ""
            stderr = String(data: errorData, encoding: .utf8) ?? ""
        }

        let duration = Date().timeIntervalSince(startTime)

        if let timeout, duration >= timeout && process.terminationStatus != 0 {
            throw CLIServiceError.timeout(command: "\(command) \(arguments.joined(separator: " "))", duration: timeout)
        }

        return ExecutionResult(
            exitCode: process.terminationStatus,
            stdout: stdout,
            stderr: stderr,
            duration: duration
        )
    }

    // MARK: - Typed Command Execution

    /// Execute a typed command and return both the parsed output and execution result.
    /// This is the lowest-level typed command API - use when you need both the parsed result
    /// and execution metadata (exit code, stderr, duration).
    /// - Parameters:
    ///   - command: The command to execute
    ///   - parser: Parser to transform stdout into the desired type
    ///   - workingDirectory: Working directory for execution
    ///   - environment: Custom environment variables
    ///   - printCommand: Whether to print the command before execution
    /// - Returns: Tuple of (parsed output, execution result). Parse only attempted if command succeeds.
    /// - Throws: CLIServiceError if command not found or parsing fails
    public func executeWithResult<C: CLICommand, P: CLIOutputParser>(
        _ command: C,
        parser: P,
        workingDirectory: String? = nil,
        environment: [String: String]? = nil,
        printCommand: Bool = true
    ) async throws -> (P.Output?, ExecutionResult) {
        let result = try await execute(
            command: C.Program.programName,
            arguments: command.commandArguments,
            workingDirectory: workingDirectory,
            environment: environment,
            printCommand: printCommand
        )

        if result.isSuccess {
            let parsed = try parser.parse(result.stdout)
            return (parsed, result)
        } else {
            return (nil, result)
        }
    }

    /// Execute a typed command and return just the ExecutionResult.
    /// Use when you only need to check exit codes or inspect stdout/stderr directly.
    /// - Parameters:
    ///   - command: The command to execute
    ///   - workingDirectory: Working directory for execution
    ///   - environment: Custom environment variables
    ///   - printCommand: Whether to print the command before execution
    ///   - inheritIO: If true, inherits stdin/stdout/stderr from parent process (for interactive commands)
    /// - Returns: ExecutionResult containing exit code, stdout, stderr, and duration
    public func executeForResult<C: CLICommand>(
        _ command: C,
        workingDirectory: String? = nil,
        environment: [String: String]? = nil,
        printCommand: Bool = true,
        inheritIO: Bool = false
    ) async throws -> ExecutionResult {
        try await execute(
            command: C.Program.programName,
            arguments: command.commandArguments,
            workingDirectory: workingDirectory,
            environment: environment,
            printCommand: printCommand,
            inheritIO: inheritIO
        )
    }

    /// Execute a typed command and return parsed output.
    /// Throws if the command fails (non-zero exit code).
    /// - Parameters:
    ///   - command: The command to execute
    ///   - parser: Parser to transform stdout into the desired type
    ///   - workingDirectory: Working directory for execution
    ///   - environment: Custom environment variables
    ///   - printCommand: Whether to print the command before execution
    /// - Returns: Parsed output of type `P.Output`
    /// - Throws: CLIServiceError if command fails or parsing fails
    public func execute<C: CLICommand, P: CLIOutputParser>(
        _ command: C,
        parser: P,
        workingDirectory: String? = nil,
        environment: [String: String]? = nil,
        printCommand: Bool = true
    ) async throws -> P.Output {
        let (parsed, result) = try await executeWithResult(
            command,
            parser: parser,
            workingDirectory: workingDirectory,
            environment: environment,
            printCommand: printCommand
        )

        guard let parsed else {
            throw CLIServiceError.executionFailed(
                command: command.commandString,
                exitCode: result.exitCode,
                stderr: result.stderr
            )
        }

        return parsed
    }

    /// Execute a typed command and return trimmed string output.
    /// Throws if the command fails (non-zero exit code).
    /// - Parameters:
    ///   - command: The command to execute
    ///   - workingDirectory: Working directory for execution
    ///   - environment: Custom environment variables
    ///   - printCommand: Whether to print the command before execution
    /// - Returns: Trimmed stdout string
    public func execute<C: CLICommand>(
        _ command: C,
        workingDirectory: String? = nil,
        environment: [String: String]? = nil,
        printCommand: Bool = true
    ) async throws -> String {
        try await execute(
            command,
            parser: StringParser(),
            workingDirectory: workingDirectory,
            environment: environment,
            printCommand: printCommand
        )
    }

    // MARK: - Private Streaming

    private func streamProcess(
        command: String,
        arguments: [String],
        workingDirectory: String?,
        environment: [String: String],
        continuation: AsyncStream<StreamOutput>.Continuation
    ) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments
        process.environment = environment

        if let workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        }

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        // Set up output handling with readability handlers
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty, let text = String(data: data, encoding: .utf8) {
                // Print stdout in real-time and yield to stream
                print(text, terminator: "")
                continuation.yield(.stdout(text))
            }
        }

        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty, let text = String(data: data, encoding: .utf8) {
                // Print stderr in real-time and yield to stream
                print(text, terminator: "")
                continuation.yield(.stderr(text))
            }
        }

        try process.run()
        process.waitUntilExit()

        // Clean up
        outputPipe.fileHandleForReading.readabilityHandler = nil
        errorPipe.fileHandleForReading.readabilityHandler = nil

        continuation.yield(.exit(process.terminationStatus))
        continuation.finish()
    }
}
