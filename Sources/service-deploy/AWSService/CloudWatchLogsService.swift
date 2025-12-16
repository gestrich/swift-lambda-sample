import sdk_cli
import sdk_aws
import Foundation

// Re-export types from sdk-aws for backward compatibility
public typealias CloudWatchLogEntry = sdk_aws.CloudWatchLogEntry
public typealias CloudWatchLogsError = sdk_aws.CloudWatchLogsError

/// Progress updates from CloudWatch log streaming
public enum CloudWatchLogsProgress: Sendable {
    case started
    case entry(CloudWatchLogEntry)
    case error(String)
    case stopped
}

/// App-specific service for streaming CloudWatch logs from Lambda
/// Provides app-specific defaults (lambda function name) while delegating
/// to the generic CloudWatchLogsClient from sdk-aws.
public actor LambdaLogsService {
    private let client: sdk_aws.CloudWatchLogsClient
    private let logGroup: String
    private let credentialProvider: AWSCredentialProvider

    /// Initialize with app-specific configuration
    /// - Parameters:
    ///   - awsConfig: AWS authentication configuration
    ///   - cliClient: CLI service for executing commands
    ///   - lambdaFunctionName: Lambda function name (default: "swift-lambda-sample")
    public init(
        awsConfig: AWSAuthConfiguration,
        cliClient: CLIClient,
        lambdaFunctionName: String = "swift-lambda-sample"
    ) {
        self.logGroup = "/aws/lambda/\(lambdaFunctionName)"
        self.credentialProvider = awsConfig.makeCredentialProvider()
        self.client = sdk_aws.CloudWatchLogsClient(cliClient: cliClient)
    }

    /// Stream CloudWatch logs with polling mode
    /// Returns an AsyncStream that yields log entries in real-time
    /// - Parameters:
    ///   - since: Time period to fetch logs from (e.g., "5m", "1h")
    /// - Returns: AsyncStream of CloudWatchLogsProgress updates
    public nonisolated func tailLogs(
        since: String = "5m",
        output: CLIOutputStream? = nil
    ) -> AsyncStream<CloudWatchLogsProgress> {
        let logGroup = self.logGroup
        let credentialProvider = self.credentialProvider
        let client = self.client

        return AsyncStream { continuation in
            let task = Task {
                continuation.yield(.started)

                do {
                    for try await entry in client.tailLogs(
                        logGroup: logGroup,
                        since: since,
                        credentialProvider: credentialProvider,
                        pollInterval: .seconds(3)
                    ) {
                        guard !Task.isCancelled else { break }
                        continuation.yield(.entry(entry))
                    }
                    continuation.yield(.stopped)
                    continuation.finish()
                } catch {
                    if !Task.isCancelled {
                        continuation.yield(.error(error.localizedDescription))
                    }
                    continuation.yield(.stopped)
                    continuation.finish()
                }
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    /// Fetch recent logs (non-streaming, one-shot)
    /// - Parameters:
    ///   - since: Time period to fetch logs from (e.g., "5m", "1h")
    /// - Returns: Array of log entries
    public func fetchRecentLogs(
        since: String = "5m",
        output: CLIOutputStream? = nil
    ) async throws -> [CloudWatchLogEntry] {
        try await client.fetchLogs(
            logGroup: logGroup,
            since: since,
            credentialProvider: credentialProvider
        )
    }
}
