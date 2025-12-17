import d_sdk_aws
import d_sdk_cli
import c_service_deploy_remote
import b_workflow_deploy_remote
import SwiftUI

/// View for CloudWatch logs section in Remote tab
/// Displays Lambda logs with streaming support and auto-scroll
struct CloudWatchLogsSectionView: View {
    @Bindable var model: CloudWatchLogsModel

    /// Available time periods for log fetching
    private let timePeriods = ["1m", "5m", "15m", "30m", "1h", "3h", "12h", "1d"]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            headerView

            // Controls
            controlsView

            // Log output
            logOutputView
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var headerView: some View {
        HStack {
            Text("CloudWatch Logs")
                .font(.headline)

            Spacer()

            statusBadge
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        HStack(spacing: 4) {
            switch model.state {
            case .idle:
                Image(systemName: "circle")
                    .foregroundColor(.secondary)
                Text("Ready")
                    .font(.caption2)
                    .foregroundColor(.secondary)

            case .loading:
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 12, height: 12)
                Text("Loading")
                    .font(.caption2)
                    .foregroundColor(.secondary)

            case .streaming:
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
                Text("Streaming")
                    .font(.caption2)
                    .foregroundColor(.green)

            case .stopped:
                Image(systemName: "stop.circle")
                    .foregroundColor(.orange)
                Text("Stopped")
                    .font(.caption2)
                    .foregroundColor(.orange)

            case .error:
                Image(systemName: "exclamationmark.circle")
                    .foregroundColor(.red)
                Text("Error")
                    .font(.caption2)
                    .foregroundColor(.red)
            }
        }
    }

    // MARK: - Controls

    @ViewBuilder
    private var controlsView: some View {
        HStack(spacing: 12) {
            // Time period picker
            Picker("Since", selection: $model.sincePeriod) {
                ForEach(timePeriods, id: \.self) { period in
                    Text(formatPeriod(period)).tag(period)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 100)
            .disabled(model.isStreaming)

            Spacer()

            // Action buttons
            if model.isStreaming {
                Button(action: { model.stopStreaming() }) {
                    Label("Stop", systemImage: "stop.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            } else {
                Button(action: { model.startStreaming() }) {
                    Label("Start", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.canStart)
            }

            Button(action: {
                Task { await model.fetchRecentLogs() }
            }) {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(model.isLoading)

            Button(action: { model.clearLogs() }) {
                Label("Clear", systemImage: "trash")
            }
            .disabled(model.entries.isEmpty && model.errorMessage == nil)
        }
    }

    // MARK: - Log Output

    @ViewBuilder
    private var logOutputView: some View {
        VStack(spacing: 0) {
            // Error banner if present
            if let error = model.errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Dismiss") {
                        model.clearLogs()
                    }
                    .font(.caption)
                    .buttonStyle(.borderless)
                }
                .padding(8)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(6)
            }

            // Log entries with auto-scroll
            LogEntriesScrollView(entries: model.entries, isStreaming: model.isStreaming)
        }
    }

    // MARK: - Helpers

    private func formatPeriod(_ period: String) -> String {
        switch period {
        case "1m": return "1 minute"
        case "5m": return "5 minutes"
        case "15m": return "15 minutes"
        case "30m": return "30 minutes"
        case "1h": return "1 hour"
        case "3h": return "3 hours"
        case "12h": return "12 hours"
        case "1d": return "1 day"
        default: return period
        }
    }
}

// MARK: - Log Entries Scroll View

/// Scrollable view of log entries with auto-scroll to bottom
private struct LogEntriesScrollView: View {
    let entries: [CloudWatchLogEntry]
    let isStreaming: Bool

    /// Track the last entry count to detect new entries
    @State private var lastEntryCount = 0

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    if entries.isEmpty {
                        emptyStateView
                    } else {
                        ForEach(entries) { entry in
                            LogEntryRow(entry: entry)
                                .id(entry.id)
                        }
                    }
                }
                .padding(8)
            }
            .frame(minHeight: 200, maxHeight: 400)
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            )
            .onChange(of: entries.count) { _, newCount in
                if newCount > lastEntryCount, let lastEntry = entries.last {
                    withAnimation(.easeOut(duration: 0.1)) {
                        proxy.scrollTo(lastEntry.id, anchor: .bottom)
                    }
                }
                lastEntryCount = newCount
            }
        }
    }

    @ViewBuilder
    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text(isStreaming ? "Waiting for logs..." : "No logs to display")
                .font(.subheadline)
                .foregroundColor(.secondary)
            if !isStreaming {
                Text("Click Start to stream logs or Refresh to fetch recent logs")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 150)
        .padding()
    }
}

// MARK: - Log Entry Row

/// Individual log entry row
private struct LogEntryRow: View {
    let entry: CloudWatchLogEntry

    private var timestampText: String {
        guard let timestamp = entry.timestamp else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: timestamp)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if !timestampText.isEmpty {
                Text(timestampText)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 85, alignment: .leading)
            }

            Text(entry.message)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(messageColor)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
    }

    private var messageColor: Color {
        let msg = entry.message.lowercased()
        if msg.contains("error") || msg.contains("exception") || msg.contains("failed") {
            return .red
        } else if msg.contains("warning") || msg.contains("warn") {
            return .orange
        } else if msg.contains("info") {
            return .blue
        } else if msg.contains("debug") {
            return .secondary
        }
        return .primary
    }
}

// MARK: - Preview

#Preview {
    let awsConfig = AWSAuthConfiguration(profileName: "default", useAWSVault: false)
    let cliClient = CLIClient()
    let workflow = CloudWatchLogsWorkflow.create(
        cliClient: cliClient,
        lambdaFunctionName: "swift-lambda-sample",
        credentialProvider: awsConfig.makeCredentialProvider()
    )
    let model = CloudWatchLogsModel(workflow: workflow)

    CloudWatchLogsSectionView(model: model)
        .padding()
        .frame(width: 600)
}
