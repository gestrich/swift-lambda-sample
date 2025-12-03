import Foundation
import Synchronization

/// A service for executing command-line operations with async/await support
public actor CLIService {
    /// Global output stream - broadcasts all CLI output to any subscriber.
    private let globalOutput = CLIOutputStream()

    /// Create a new stream subscription for CLI output.
    /// Each caller gets an independent stream receiving all future output.
    public func outputStream() async -> AsyncStream<StreamOutput> {
        await globalOutput.makeStream()
    }

    /// Pre-computed environment with common paths
    private let defaultEnvironment: [String: String]

    /// Default working directory for commands (nil uses current directory)
    private var defaultWorkingDirectory: String?

    /// Cache for executable paths
    private var executableCache: [String: String] = [:]

    public init(defaultWorkingDirectory: String? = nil) {
        self.defaultWorkingDirectory = defaultWorkingDirectory

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

    /// Set the default working directory for all commands
    public func setDefaultWorkingDirectory(_ directory: String?) {
        self.defaultWorkingDirectory = directory
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
        // Resolve and prepare command - this handles errors and sends to global stream
        let prepared = await prepareCommand(
            command: command,
            arguments: arguments,
            workingDirectory: workingDirectory,
            environment: environment,
            printCommand: printCommand
        )

        switch prepared {
        case .success(let info):
            return try await executeProcess(
                command: info.resolvedCommand,
                arguments: arguments,
                workingDirectory: info.effectiveWorkingDirectory,
                environment: info.processEnvironment,
                timeout: timeout,
                startTime: Date(),
                inheritIO: inheritIO,
                commandID: info.commandID
            )
        case .failure(let error):
            throw error
        }
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
                // Prepare command - handles resolution, environment merging, and error reporting
                let prepared = await self.prepareCommand(
                    command: command,
                    arguments: arguments,
                    workingDirectory: workingDirectory,
                    environment: environment,
                    printCommand: printCommand,
                    continuation: continuation
                )

                guard case .success(let info) = prepared else {
                    // prepareCommand already sent error to continuation and finished it
                    return
                }

                do {
                    try self.streamProcess(
                        command: info.resolvedCommand,
                        arguments: arguments,
                        workingDirectory: info.effectiveWorkingDirectory,
                        environment: info.processEnvironment,
                        commandID: info.commandID,
                        continuation: continuation
                    )
                } catch {
                    // Error during process execution (not resolution)
                    let errorOutput = StreamOutput.error(commandID: info.commandID, error: error)
                    continuation.yield(errorOutput)
                    continuation.finish()
                    await self.globalOutput.send(errorOutput)
                }
            }
        }
    }

    /// Execute a typed CLI command and stream its output
    /// - Parameters:
    ///   - command: The typed CLI command to execute
    ///   - workingDirectory: Working directory for the command
    ///   - environment: Custom environment variables
    ///   - printCommand: If true, prints the formatted command before execution
    /// - Returns: AsyncStream of output lines
    public func stream<C: CLICommand>(
        _ command: C,
        workingDirectory: String? = nil,
        environment: [String: String]? = nil,
        printCommand: Bool = true
    ) -> AsyncStream<StreamOutput> {
        let commandLine = command.commandLine
        guard let programName = commandLine.first else {
            let errorID = CommandID()
            return AsyncStream { (continuation: AsyncStream<StreamOutput>.Continuation) in
                continuation.yield(.error(commandID: errorID, error: CLIServiceError.invalidCommand("Empty command line")))
                continuation.finish()
            }
        }
        let arguments = Array(commandLine.dropFirst())
        return stream(
            command: programName,
            arguments: arguments,
            workingDirectory: workingDirectory,
            environment: environment,
            printCommand: printCommand
        )
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

    /// Information needed to execute a prepared command
    private struct PreparedCommand {
        let commandID: CommandID
        let resolvedCommand: String
        let effectiveWorkingDirectory: String?
        let processEnvironment: [String: String]
    }

    /// Prepare a command for execution: resolve path, merge environment, send to global stream
    /// This is the single place that handles command resolution errors for both execute and stream
    private func prepareCommand(
        command: String,
        arguments: [String],
        workingDirectory: String?,
        environment: [String: String]?,
        printCommand: Bool,
        continuation: AsyncStream<StreamOutput>.Continuation? = nil
    ) async -> Result<PreparedCommand, Error> {
        let commandID = CommandID()

        // Use provided working directory or fall back to default
        let effectiveWorkingDirectory = workingDirectory ?? defaultWorkingDirectory

        // Resolve command path
        let resolvedCommand: String
        do {
            resolvedCommand = try resolveCommand(command, workingDirectory: effectiveWorkingDirectory)
        } catch {
            // Send command and error to streams so UI shows what failed
            let commandLine = "→ \(command) \(arguments.joined(separator: " "))\n"
            let commandOutput = StreamOutput.command(id: commandID, text: commandLine)
            let errorOutput = StreamOutput.error(commandID: commandID, error: error)

            await globalOutput.send(commandOutput)
            await globalOutput.send(errorOutput)

            continuation?.yield(commandOutput)
            continuation?.yield(errorOutput)
            continuation?.finish()

            if printCommand {
                print(commandLine, terminator: "")
                print("❌ Error: \(error.localizedDescription)")
            }
            return .failure(error)
        }

        // Merge environments
        var processEnvironment = defaultEnvironment
        if let customEnvironment = environment {
            for (key, value) in customEnvironment {
                processEnvironment[key] = value
            }
        }

        // Send command to streams
        let formattedCommand = formatCommand(
            command: resolvedCommand,
            arguments: arguments,
            environment: environment
        )
        let commandLine = "→ \(formattedCommand)\n"
        let commandOutput = StreamOutput.command(id: commandID, text: commandLine)

        await globalOutput.send(commandOutput)
        continuation?.yield(commandOutput)

        if printCommand {
            print(commandLine, terminator: "")
        }

        return .success(PreparedCommand(
            commandID: commandID,
            resolvedCommand: resolvedCommand,
            effectiveWorkingDirectory: effectiveWorkingDirectory,
            processEnvironment: processEnvironment
        ))
    }

    private func resolveCommand(_ command: String, workingDirectory: String? = nil) throws -> String {
        // If it's already an absolute path, use it
        if command.starts(with: "/") {
            guard FileManager.default.fileExists(atPath: command) else {
                throw CLIServiceError.commandNotFound(command)
            }
            return command
        }

        // If it's a relative path (starts with ./ or ../), resolve relative to working directory
        if command.starts(with: "./") || command.starts(with: "../") {
            let baseDir = workingDirectory ?? FileManager.default.currentDirectoryPath
            let resolvedPath = (baseDir as NSString).appendingPathComponent(command)
            let standardizedPath = (resolvedPath as NSString).standardizingPath
            guard FileManager.default.fileExists(atPath: standardizedPath) else {
                throw CLIServiceError.commandNotFound(command)
            }
            return standardizedPath
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
        inheritIO: Bool,
        commandID: CommandID
    ) async throws -> ExecutionResult {
        return try self.runProcess(
            command: command,
            arguments: arguments,
            workingDirectory: workingDirectory,
            environment: environment,
            timeout: timeout,
            inheritIO: inheritIO,
            commandID: commandID,
            commandContinuation: nil
        )
    }

    /// Unified process execution - always streams output in real-time and broadcasts to global stream
    /// - Parameters:
    ///   - command: Executable path
    ///   - arguments: Command arguments
    ///   - workingDirectory: Working directory
    ///   - environment: Environment variables
    ///   - timeout: Optional timeout
    ///   - inheritIO: If true, inherit stdin/stdout/stderr (no capture)
    ///   - commandID: Unique ID for this command execution
    ///   - commandContinuation: Optional per-command stream continuation
    /// - Returns: ExecutionResult with accumulated stdout/stderr
    private func runProcess(
        command: String,
        arguments: [String],
        workingDirectory: String?,
        environment: [String: String],
        timeout: TimeInterval?,
        inheritIO: Bool,
        commandID: CommandID,
        commandContinuation: AsyncStream<StreamOutput>.Continuation?
    ) throws -> ExecutionResult {
        let startTime = Date()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments
        process.environment = environment

        if let workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        }

        // Thread-safe accumulators for ExecutionResult
        let stdoutAccumulator = OutputAccumulator()
        let stderrAccumulator = OutputAccumulator()

        // Capture globalOutput for use in closures
        let output = self.globalOutput

        let outputPipe: Pipe?
        let errorPipe: Pipe?

        if inheritIO {
            process.standardInput = FileHandle.standardInput
            process.standardOutput = FileHandle.standardOutput
            process.standardError = FileHandle.standardError
            outputPipe = nil
            errorPipe = nil
        } else {
            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe
            outputPipe = outPipe
            errorPipe = errPipe

            // Real-time output handling (always)
            outPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty, let text = String(data: data, encoding: .utf8) {
                    stdoutAccumulator.append(text)
                    print(text, terminator: "")

                    // Yield to per-command stream (if provided)
                    commandContinuation?.yield(.stdout(commandID: commandID, text: text))

                    // Broadcast to global stream
                    Task {
                        await output.send(.stdout(commandID: commandID, text: text))
                    }
                }
            }

            errPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty, let text = String(data: data, encoding: .utf8) {
                    stderrAccumulator.append(text)
                    print(text, terminator: "")

                    commandContinuation?.yield(.stderr(commandID: commandID, text: text))

                    // Broadcast to global stream
                    Task {
                        await output.send(.stderr(commandID: commandID, text: text))
                    }
                }
            }
        }

        // Timeout handling
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

        // Clean up handlers
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        errorPipe?.fileHandleForReading.readabilityHandler = nil

        let exitCode = process.terminationStatus
        let duration = Date().timeIntervalSince(startTime)

        // Ensure output ends with newline for clean separation between commands
        let stdout = stdoutAccumulator.value
        if !stdout.isEmpty && !stdout.hasSuffix("\n") {
            let newline = "\n"
            print(newline, terminator: "")
            commandContinuation?.yield(.stdout(commandID: commandID, text: newline))
            Task {
                await output.send(.stdout(commandID: commandID, text: newline))
            }
        }

        // Yield exit to streams
        commandContinuation?.yield(.exit(commandID: commandID, code: exitCode))
        commandContinuation?.finish()

        Task {
            await self.globalOutput.send(.exit(commandID: commandID, code: exitCode))
        }

        // Check timeout
        if let timeout, duration >= timeout && exitCode != 0 {
            throw CLIServiceError.timeout(
                command: "\(command) \(arguments.joined(separator: " "))",
                duration: timeout
            )
        }

        return ExecutionResult(
            exitCode: exitCode,
            stdout: stdoutAccumulator.value,
            stderr: stderrAccumulator.value,
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
        commandID: CommandID,
        continuation: AsyncStream<StreamOutput>.Continuation
    ) throws {
        // Use unified runProcess - it handles continuation and global broadcast
        _ = try runProcess(
            command: command,
            arguments: arguments,
            workingDirectory: workingDirectory,
            environment: environment,
            timeout: nil,
            inheritIO: false,
            commandID: commandID,
            commandContinuation: continuation
        )
    }
}

/// Thread-safe string accumulator for capturing output in concurrent contexts
private final class OutputAccumulator: Sendable {
    private let storage = Mutex("")

    var value: String {
        storage.withLock { $0 }
    }

    func append(_ text: String) {
        storage.withLock { $0 += text }
    }
}
