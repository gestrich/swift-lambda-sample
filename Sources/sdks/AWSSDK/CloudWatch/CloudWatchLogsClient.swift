import CLISDK
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

/// Stateless client for fetching CloudWatch logs.
/// Each method call is independent - caller manages task lifecycle via Swift's cooperative cancellation.
public struct CloudWatchLogsClient: Sendable {
    private let cliClient: CLIClient

    public init(cliClient: CLIClient) {
        self.cliClient = cliClient
    }

    /// Fetch logs once (non-streaming)
    /// - Parameters:
    ///   - logGroup: CloudWatch log group name (e.g., "/aws/lambda/my-function")
    ///   - since: Time period to fetch logs from (e.g., "5m", "1h")
    ///   - credentialProvider: AWS credential provider for authentication
    /// - Returns: Array of log entries
    public func fetchLogs(
        logGroup: String,
        since: String,
        credentialProvider: AWSCredentialProvider
    ) async throws -> [CloudWatchLogEntry] {
        let (execCommand, arguments) = buildCommandLine(
            logGroup: logGroup,
            since: since,
            follow: false,
            credentialProvider: credentialProvider
        )

        let result = try await cliClient.execute(
            command: execCommand,
            arguments: arguments,
            environment: credentialProvider.environment.merging([
                "PYTHONUNBUFFERED": "1",
                "AWS_PAGER": ""
            ]) { _, new in new },
            printCommand: true,
            output: nil
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

    /// Stream log entries - caller manages cancellation via task cancellation
    /// - Parameters:
    ///   - logGroup: CloudWatch log group name (e.g., "/aws/lambda/my-function")
    ///   - since: Time period to fetch logs from (e.g., "5m", "1h")
    ///   - credentialProvider: AWS credential provider for authentication
    ///   - pollInterval: How often to poll for new logs
    /// - Returns: AsyncThrowingStream of log entries
    public func tailLogs(
        logGroup: String,
        since: String,
        credentialProvider: AWSCredentialProvider,
        pollInterval: Duration
    ) -> AsyncThrowingStream<CloudWatchLogEntry, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var seenLines = Set<String>()

                while !Task.isCancelled {
                    do {
                        let entries = try await self.fetchLogs(
                            logGroup: logGroup,
                            since: since,
                            credentialProvider: credentialProvider
                        )

                        for entry in entries {
                            if !seenLines.contains(entry.rawLine) {
                                seenLines.insert(entry.rawLine)
                                continuation.yield(entry)
                            }
                        }

                        try await Task.sleep(for: pollInterval)
                    } catch is CancellationError {
                        break
                    } catch {
                        continuation.finish(throwing: error)
                        return
                    }
                }

                continuation.finish()
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    // MARK: - Private Helpers

    /// Build command line with credential provider
    private func buildCommandLine(
        logGroup: String,
        since: String,
        follow: Bool,
        credentialProvider: AWSCredentialProvider
    ) -> (command: String, arguments: [String]) {
        let command = Aws.Logs.Tail(
            logGroup: logGroup,
            since: since,
            format: "short",
            follow: follow,
            profile: credentialProvider.profileName
        )

        return credentialProvider.buildCommandLine(command)
    }

    /// Parse a log line from AWS CLI output
    /// AWS logs tail --format short outputs: "2024-01-15T10:30:00 message content here" (no timezone!)
    private func parseLogLine(_ line: String) -> CloudWatchLogEntry? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let timestamp: Date?
        let message: String

        // AWS short format: 2024-01-15T10:30:00 (no timezone, just date and time)
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
            return "CloudWatch logs client is not configured"
        }
    }
}
