import sdk_cli
import sdk_aws
import Foundation

// Re-export types from sdk-aws for backward compatibility
public typealias CloudWatchLogEntry = sdk_aws.CloudWatchLogEntry
public typealias CloudWatchLogsProgress = sdk_aws.CloudWatchLogsProgress
public typealias CloudWatchLogsError = sdk_aws.CloudWatchLogsError

/// App-specific service for streaming CloudWatch logs from Lambda
/// Provides app-specific defaults (lambda function name) while delegating
/// to the generic CloudWatchLogsService from sdk-aws.
public actor LambdaLogsService {
    private let genericService: sdk_aws.CloudWatchLogsService

    /// Initialize with app-specific configuration
    /// - Parameters:
    ///   - awsConfig: AWS authentication configuration
    ///   - cliService: CLI service for executing commands
    ///   - lambdaFunctionName: Lambda function name (default: "swift-lambda-sample")
    public init(
        awsConfig: AWSAuthConfiguration,
        cliService: CLIClient,
        lambdaFunctionName: String = "swift-lambda-sample"
    ) {
        let logGroup = "/aws/lambda/\(lambdaFunctionName)"
        let credentialProvider = awsConfig.makeCredentialProvider()
        self.genericService = sdk_aws.CloudWatchLogsService(
            logGroup: logGroup,
            credentialProvider: credentialProvider,
            cliService: cliService
        )
    }

    /// Whether logs are currently being streamed
    public var isStreaming: Bool {
        get async {
            await genericService.isStreaming
        }
    }

    /// Stop the current log stream
    public func stopStreaming() async {
        await genericService.stopStreaming()
    }

    /// Stream CloudWatch logs with polling mode
    /// Returns an AsyncStream that yields log entries in real-time
    /// - Parameters:
    ///   - since: Time period to fetch logs from (e.g., "5m", "1h")
    ///   - output: Optional CLIOutputStream for displaying raw output
    /// - Returns: AsyncStream of CloudWatchLogsProgress updates
    public nonisolated func tailLogs(
        since: String = "5m",
        output: CLIOutputStream? = nil
    ) -> AsyncStream<CloudWatchLogsProgress> {
        genericService.tailLogs(since: since, output: output)
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
        try await genericService.fetchRecentLogs(since: since, output: output)
    }
}
