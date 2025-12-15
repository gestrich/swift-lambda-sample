import sdk_aws
import sdk_cli
import Foundation
import Observation
import service_deploy

/// Observable model for CloudWatch logs viewing
/// Holds UI state and delegates operations to CloudWatchLogsService
@MainActor
@Observable
public final class CloudWatchLogsModel {
    // MARK: - State

    /// Current log entries being displayed
    public private(set) var logEntries: [CloudWatchLogEntry] = []

    /// Current streaming status
    public private(set) var status: LogsStatus = .idle

    /// Selected time period for log fetching
    public var sincePeriod: String = "1h"

    /// Error message if any
    public private(set) var errorMessage: String?

    // MARK: - Private

    private let logsService: LambdaLogsService
    private let output: CLIOutputStream
    private var streamTask: Task<Void, Never>?

    // MARK: - Computed

    /// Whether logs are currently being streamed
    public var isStreaming: Bool {
        if case .streaming = status { return true }
        return false
    }

    /// Whether an operation is in progress
    public var isLoading: Bool {
        switch status {
        case .loading, .streaming:
            return true
        default:
            return false
        }
    }

    /// Whether the start button should be enabled
    public var canStart: Bool {
        switch status {
        case .idle, .error, .stopped:
            return true
        default:
            return false
        }
    }

    // MARK: - Init

    public init(
        awsConfig: AWSAuthConfiguration,
        cliService: CLIService,
        lambdaFunctionName: String = "swift-lambda-sample"
    ) {
        self.logsService = LambdaLogsService(
            awsConfig: awsConfig,
            cliService: cliService,
            lambdaFunctionName: lambdaFunctionName
        )
        self.output = CLIOutputStream()
    }

    // MARK: - Public Methods

    /// Start streaming logs in real-time
    public func startStreaming() {
        guard canStart else { return }

        stopStreaming()
        logEntries = []
        errorMessage = nil
        status = .streaming

        streamTask = Task {
            for await progress in logsService.tailLogs(since: sincePeriod, output: output) {
                guard !Task.isCancelled else { break }

                switch progress {
                case .started:
                    status = .streaming
                case .entry(let entry):
                    logEntries.append(entry)
                    trimEntriesIfNeeded()
                case .error(let message):
                    errorMessage = message
                case .stopped:
                    if status == .streaming {
                        status = .stopped
                    }
                }
            }

            if status == .streaming {
                status = .stopped
            }
        }
    }

    /// Stop streaming logs
    public func stopStreaming() {
        streamTask?.cancel()
        streamTask = nil

        Task {
            await logsService.stopStreaming()
        }

        if isStreaming {
            status = .stopped
        }
    }

    /// Fetch recent logs (one-shot, non-streaming)
    public func fetchRecentLogs() async {
        guard canStart else { return }

        stopStreaming()
        logEntries = []
        errorMessage = nil
        status = .loading

        do {
            let entries = try await logsService.fetchRecentLogs(since: sincePeriod, output: output)
            logEntries = entries
            status = .idle
        } catch {
            errorMessage = error.localizedDescription
            status = .error(error.localizedDescription)
        }
    }

    /// Clear all log entries
    public func clearLogs() {
        logEntries = []
        errorMessage = nil
    }

    /// Get the output stream for StreamingTextView
    public func makeOutputStream() async -> AsyncStream<StreamOutput> {
        await output.makeStream()
    }

    // MARK: - Private

    private func trimEntriesIfNeeded() {
        let maxEntries = 1000
        if logEntries.count > maxEntries {
            logEntries = Array(logEntries.suffix(maxEntries))
        }
    }
}

// MARK: - Status Enum

public enum LogsStatus: Equatable {
    case idle
    case loading
    case streaming
    case stopped
    case error(String)

    public var displayText: String {
        switch self {
        case .idle:
            return "Ready"
        case .loading:
            return "Loading..."
        case .streaming:
            return "Streaming"
        case .stopped:
            return "Stopped"
        case .error(let message):
            return "Error: \(message)"
        }
    }
}
