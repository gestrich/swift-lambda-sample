import sdk_cli
import Foundation

/// A log entry from CloudWatch Logs
public struct CloudWatchLogEntry: Sendable, Identifiable, Equatable {
    public let id: UUID
    public let timestamp: Date?
    public let message: String
    public let rawLine: String

    public init(timestamp: Date?, message: String, rawLine: String) {
        self.id = UUID()
        self.timestamp = timestamp
        self.message = message
        self.rawLine = rawLine
    }
}

/// Progress updates from CloudWatch log streaming
public enum CloudWatchLogsProgress: Sendable {
    case started
    case entry(CloudWatchLogEntry)
    case error(String)
    case stopped
}

/// Service for streaming CloudWatch logs from Lambda
/// Provides AsyncStream-based log tailing for real-time log viewing
public actor CloudWatchLogsService {
    private let awsConfig: AWSAuthConfiguration
    private let cliService: CLIService
    private let lambdaFunctionName: String
    private let vaultService: AWSVaultService?

    /// Currently running stream task (for cancellation)
    private var streamTask: Task<Void, Never>?

    /// Log group name derived from Lambda function name
    private var logGroup: String {
        "/aws/lambda/\(lambdaFunctionName)"
    }

    public init(
        awsConfig: AWSAuthConfiguration,
        cliService: CLIService,
        lambdaFunctionName: String = "swift-lambda-sample"
    ) {
        self.awsConfig = awsConfig
        self.cliService = cliService
        self.lambdaFunctionName = lambdaFunctionName
        self.vaultService = awsConfig.useAWSVault ? AWSVaultService(profile: awsConfig.profileName) : nil
    }

    /// Whether logs are currently being streamed
    public var isStreaming: Bool {
        streamTask != nil && !streamTask!.isCancelled
    }

    /// Stop the current log stream
    public func stopStreaming() {
        streamTask?.cancel()
        streamTask = nil
    }

    /// Stream CloudWatch logs with --follow mode
    /// Returns an AsyncStream that yields log entries in real-time
    /// - Parameters:
    ///   - since: Time period to fetch logs from (e.g., "5m", "1h")
    ///   - output: Optional CLIOutputStream for displaying raw output
    /// - Returns: AsyncStream of CloudWatchLogsProgress updates
    public nonisolated func tailLogs(
        since: String = "5m",
        output: CLIOutputStream? = nil
    ) -> AsyncStream<CloudWatchLogsProgress> {
        AsyncStream { continuation in
            Task {
                await self.startTailingInternal(
                    since: since,
                    output: output,
                    continuation: continuation
                )
            }
        }
    }

    /// Fetch recent logs (non-streaming, one-shot)
    /// - Parameters:
    ///   - since: Time period to fetch logs from (e.g., "5m", "1h")
    ///   - output: Optional CLIOutputStream for displaying raw output
    /// - Returns: Array of log entries
    public func fetchRecentLogs(
        since: String = "5m",
        output: CLIOutputStream? = nil
    ) async throws -> [CloudWatchLogEntry] {
        let (execCommand, arguments) = buildCommandLine(since: since, follow: false)

        // Use execute() instead of stream() for one-shot fetch
        let result = try await cliService.execute(
            command: execCommand,
            arguments: arguments,
            environment: [
                "AWS_PROFILE": awsConfig.profileName,
                "PYTHONUNBUFFERED": "1",
                "AWS_PAGER": ""
            ],
            printCommand: true,
            output: output
        )

        if result.exitCode != 0 {
            throw CloudWatchLogsError.commandFailed(exitCode: result.exitCode)
        }

        var entries: [CloudWatchLogEntry] = []
        let lines = result.stdout.components(separatedBy: .newlines)
        for line in lines where !line.isEmpty {
            if let entry = parseLogLine(line) {
                entries.append(entry)
            }
        }

        return entries
    }

    // MARK: - Private Helpers

    private func startTailingInternal(
        since: String,
        output: CLIOutputStream?,
        continuation: AsyncStream<CloudWatchLogsProgress>.Continuation
    ) async {
        stopStreaming()

        continuation.yield(.started)

        // Use polling instead of --follow since AWS CLI doesn't stream well to non-TTY
        let task = Task { [self] in
            var seenLines = Set<String>()
            let pollInterval: Duration = .seconds(3)
            var isFirstPoll = true

            while !Task.isCancelled {
                do {
                    // Fetch recent logs (without --follow)
                    let entries = try await self.fetchRecentLogs(since: since, output: isFirstPoll ? output : nil)

                    for entry in entries {
                        // Only yield entries we haven't seen before
                        if !seenLines.contains(entry.rawLine) {
                            seenLines.insert(entry.rawLine)
                            continuation.yield(.entry(entry))
                        }
                    }

                    isFirstPoll = false

                    // Wait before next poll
                    try await Task.sleep(for: pollInterval)
                } catch {
                    if !Task.isCancelled {
                        continuation.yield(.error(error.localizedDescription))
                    }
                    break
                }
            }

            continuation.yield(.stopped)
            continuation.finish()
        }

        streamTask = task

        continuation.onTermination = { @Sendable _ in
            task.cancel()
        }
    }

    /// Build command line with optional aws-vault wrapping
    private func buildCommandLine(since: String, follow: Bool) -> (command: String, arguments: [String]) {
        let command = Aws.Logs.Tail(
            logGroup: logGroup,
            since: since,
            format: "short",
            follow: follow,
            profile: awsConfig.profileName
        )

        var arguments = command.commandArguments

        if let vaultService = vaultService {
            // Remove --profile flags (aws-vault handles auth via environment)
            arguments = AWSVaultService.removeProfileFlags(from: arguments)
            return vaultService.wrapCommand(command: "aws", arguments: arguments)
        } else {
            return ("aws", arguments)
        }
    }

    /// Parse a log line from AWS CLI output
    /// AWS logs tail --format short outputs: "2024-01-15T10:30:00 message content here" (no timezone!)
    private nonisolated func parseLogLine(_ line: String) -> CloudWatchLogEntry? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let timestamp: Date?
        let message: String

        // AWS short format: 2024-01-15T10:30:00 (no timezone, just date and time)
        // Also handle optional timezone suffix for other formats
        let isoPattern = #"^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:?\d{2})?)\s+"#
        if let regex = try? NSRegularExpression(pattern: isoPattern),
           let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) {
            let timestampRange = Range(match.range(at: 1), in: trimmed)!
            let timestampStr = String(trimmed[timestampRange])

            timestamp = Self.parseTimestamp(timestampStr)

            if let matchEnd = Range(match.range, in: trimmed)?.upperBound {
                message = String(trimmed[matchEnd...]).trimmingCharacters(in: .whitespaces)
            } else {
                message = trimmed
            }
        } else {
            timestamp = nil
            message = trimmed
        }

        return CloudWatchLogEntry(
            timestamp: timestamp,
            message: message,
            rawLine: trimmed
        )
    }

    /// Parse timestamp string with multiple format attempts
    private static func parseTimestamp(_ string: String) -> Date? {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone(identifier: "UTC")

        // AWS short format: 2024-01-15T10:30:00 (no timezone - most common!)
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        if let date = dateFormatter.date(from: string) {
            return date
        }

        // With milliseconds, no timezone: 2024-01-15T10:30:00.123
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
        if let date = dateFormatter.date(from: string) {
            return date
        }

        // Try ISO8601 with timezone
        let formatter1 = ISO8601DateFormatter()
        formatter1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter1.date(from: string) {
            return date
        }

        let formatter2 = ISO8601DateFormatter()
        formatter2.formatOptions = [.withInternetDateTime]
        if let date = formatter2.date(from: string) {
            return date
        }

        // With timezone: 2024-01-15T10:30:00+00:00
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
        if let date = dateFormatter.date(from: string) {
            return date
        }

        return nil
    }
}

// MARK: - Errors

public enum CloudWatchLogsError: LocalizedError {
    case fetchFailed(String)
    case commandFailed(exitCode: Int32)
    case notConfigured

    public var errorDescription: String? {
        switch self {
        case .fetchFailed(let message):
            return "Failed to fetch logs: \(message)"
        case .commandFailed(let exitCode):
            return "Command failed with exit code \(exitCode)"
        case .notConfigured:
            return "CloudWatch logs service is not configured"
        }
    }
}
