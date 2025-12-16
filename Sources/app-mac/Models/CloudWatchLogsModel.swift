import sdk_aws
import sdk_cli
import Foundation
import Observation
import service_deploy

/// Observable model for CloudWatch logs viewing.
/// Holds UI state and delegates operations to CloudWatchLogsWorkflow.
@MainActor
@Observable
public final class CloudWatchLogsModel {
    // MARK: - State

    /// Current state of the logs model
    public private(set) var state: State = .idle(entries: [])

    /// Selected time period for log fetching
    public var sincePeriod: String = "1h"

    // MARK: - Private

    private let workflow: CloudWatchLogsWorkflow
    private var streamTask: Task<Void, Never>?

    // MARK: - Computed

    /// Whether logs are currently being streamed
    public var isStreaming: Bool {
        if case .streaming = state { return true }
        return false
    }

    /// Whether an operation is in progress
    public var isLoading: Bool {
        switch state {
        case .loading, .streaming:
            return true
        default:
            return false
        }
    }

    /// Whether the start button should be enabled
    public var canStart: Bool {
        switch state {
        case .idle, .stopped, .error:
            return true
        default:
            return false
        }
    }

    /// Current log entries
    public var entries: [CloudWatchLogEntry] {
        state.entries
    }

    /// Error message if any
    public var errorMessage: String? {
        state.errorMessage
    }

    // MARK: - Init

    public init(workflow: CloudWatchLogsWorkflow) {
        self.workflow = workflow
    }

    // MARK: - Public Methods

    /// Start streaming logs in real-time
    public func startStreaming() {
        guard canStart else { return }

        stopStreaming()
        state = .streaming(entries: [])

        streamTask = Task {
            do {
                for try await workflowState in workflow.stream(since: sincePeriod) {
                    guard !Task.isCancelled else { break }

                    switch workflowState {
                    case .started:
                        state = .streaming(entries: [])
                    case .streaming(let entries):
                        state = .streaming(entries: entries)
                    case .stopped(let entries):
                        state = .stopped(entries: entries)
                    }
                }
            } catch {
                state = .error(error.localizedDescription)
            }
        }
    }

    /// Stop streaming logs
    public func stopStreaming() {
        streamTask?.cancel()
        streamTask = nil

        if case .streaming(let entries) = state {
            state = .stopped(entries: entries)
        }
    }

    /// Fetch recent logs (one-shot, non-streaming)
    public func fetchRecentLogs() async {
        guard canStart else { return }

        stopStreaming()
        state = .loading

        do {
            let entries = try await workflow.fetch(since: sincePeriod)
            state = .idle(entries: entries)
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    /// Clear all log entries
    public func clearLogs() {
        state = .idle(entries: [])
    }

    // MARK: - State Enum

    public enum State: Equatable {
        case idle(entries: [CloudWatchLogEntry])
        case loading
        case streaming(entries: [CloudWatchLogEntry])
        case stopped(entries: [CloudWatchLogEntry])
        case error(String)

        public var entries: [CloudWatchLogEntry] {
            switch self {
            case .idle(let entries): return entries
            case .loading: return []
            case .streaming(let entries): return entries
            case .stopped(let entries): return entries
            case .error: return []
            }
        }

        public var errorMessage: String? {
            if case .error(let message) = self { return message }
            return nil
        }

        public var displayText: String {
            switch self {
            case .idle: return "Ready"
            case .loading: return "Loading..."
            case .streaming: return "Streaming"
            case .stopped: return "Stopped"
            case .error(let message): return "Error: \(message)"
            }
        }
    }
}
