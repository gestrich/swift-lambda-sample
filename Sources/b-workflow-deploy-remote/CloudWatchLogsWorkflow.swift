import Foundation
import d_sdk_aws
import CLISDK

/// Workflow for streaming CloudWatch logs from Lambda.
/// Orchestrates log fetching and yields state updates with accumulated entries.
public struct CloudWatchLogsWorkflow: Sendable {
    private let client: CloudWatchLogsClient
    private let logGroup: String
    private let credentialProvider: AWSCredentialProvider

    public init(
        client: CloudWatchLogsClient,
        logGroup: String,
        credentialProvider: AWSCredentialProvider
    ) {
        self.client = client
        self.logGroup = logGroup
        self.credentialProvider = credentialProvider
    }

    /// Creates a workflow by instantiating required clients.
    /// - Parameters:
    ///   - cliClient: CLI client for executing commands
    ///   - lambdaFunctionName: Lambda function name to fetch logs from
    ///   - credentialProvider: AWS credential provider for authentication
    /// - Returns: Configured CloudWatchLogsWorkflow
    public static func create(
        cliClient: CLIClient,
        lambdaFunctionName: String,
        credentialProvider: AWSCredentialProvider
    ) -> CloudWatchLogsWorkflow {
        let client = CloudWatchLogsClient(cliClient: cliClient)
        let logGroup = "/aws/lambda/\(lambdaFunctionName)"

        return CloudWatchLogsWorkflow(
            client: client,
            logGroup: logGroup,
            credentialProvider: credentialProvider
        )
    }

    /// Stream logs with polling, yielding accumulated entries.
    /// - Parameters:
    ///   - since: Time period to fetch logs from (e.g., "5m", "1h")
    ///   - pollInterval: How often to poll for new logs (default: 3 seconds)
    ///   - maxEntries: Maximum entries to keep (older entries trimmed)
    /// - Returns: AsyncThrowingStream of State updates
    public func stream(
        since: String,
        pollInterval: Duration = .seconds(3),
        maxEntries: Int = 1000
    ) -> AsyncThrowingStream<State, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                continuation.yield(.started)
                var entries: [CloudWatchLogEntry] = []

                do {
                    for try await entry in client.tailLogs(
                        logGroup: logGroup,
                        since: since,
                        credentialProvider: credentialProvider,
                        pollInterval: pollInterval
                    ) {
                        guard !Task.isCancelled else { break }

                        entries.append(entry)
                        entries = Self.trimIfNeeded(entries, maxCount: maxEntries)
                        continuation.yield(.streaming(entries: entries))
                    }
                    continuation.yield(.stopped(entries: entries))
                    continuation.finish()
                } catch is CancellationError {
                    continuation.yield(.stopped(entries: entries))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    /// Fetch logs once (non-streaming).
    /// - Parameter since: Time period to fetch logs from (e.g., "5m", "1h")
    /// - Returns: Array of log entries
    public func fetch(since: String) async throws -> [CloudWatchLogEntry] {
        try await client.fetchLogs(
            logGroup: logGroup,
            since: since,
            credentialProvider: credentialProvider
        )
    }

    private static func trimIfNeeded(_ entries: [CloudWatchLogEntry], maxCount: Int) -> [CloudWatchLogEntry] {
        entries.count > maxCount ? Array(entries.suffix(maxCount)) : entries
    }

    // MARK: - State

    public enum State: Sendable {
        case started
        case streaming(entries: [CloudWatchLogEntry])
        case stopped(entries: [CloudWatchLogEntry])
    }
}
