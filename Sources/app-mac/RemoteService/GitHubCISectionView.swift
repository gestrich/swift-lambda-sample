import sdk_github
import service_deploy
import SwiftUI

/// Placeholder when GitHubCIModel is not available (config missing or loading)
struct GitHubCILoadingView: View {
    /// Callback to open settings
    var onOpenSettings: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("GitHub CI")
                .font(.headline)

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("Not Configured")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }

                Text("Configure your GitHub repository in Settings to enable CI/CD integration.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if let onOpenSettings {
                    Button {
                        onOpenSettings()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "gearshape")
                            Text("Open Settings")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.1))
            .cornerRadius(8)
        }
    }
}

/// View for the GitHub CI section in Remote mode
/// Shows workflow status, job/step progress during deployment, and action buttons
struct GitHubCISectionView: View {
    @State var model: GitHubCIModel

    // Timer for updating elapsed time display
    @State private var currentTime = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var modelState: GitHubCIModel.ModelState {
        model.state
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("GitHub CI")
                    .font(.headline)

                Spacer()

                // Refresh button
                Button {
                    Task { await model.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(modelState.isDeploying)
                .help("Refresh status")
            }

            // Status card
            VStack(alignment: .leading, spacing: 10) {
                // Status row
                statusRow

                // Git status
                if !modelState.currentBranch.isEmpty {
                    gitStatusRow
                }

                // Job/Step progress during deployment
                if modelState.isDeploying, let detail = modelState.runDetail {
                    jobStepsView(detail: detail)
                }

                // Action buttons
                actionButtons
            }
            .padding(12)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
        }
        .onReceive(timer) { time in
            if modelState.isDeploying {
                currentTime = time
            }
        }
        .task {
            await model.refresh()
        }
    }

    // MARK: - Elapsed Time

    private func elapsedTimeString(from dateString: String) -> String? {
        guard let startDate = parseGitHubDate(dateString) else { return nil }

        let elapsed = currentTime.timeIntervalSince(startDate)
        let minutes = Int(elapsed) / 60
        let seconds = Int(elapsed) % 60

        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        } else {
            return "\(seconds)s"
        }
    }

    private func parseGitHubDate(_ dateString: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: dateString) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: dateString)
    }

    // MARK: - Status Row

    @ViewBuilder
    private var statusRow: some View {
        HStack(spacing: 8) {
            // Status badge
            statusBadge

            Spacer()

            // Last run info
            if case .ready(let snapshot) = modelState,
               case .idle(let lastRun) = snapshot.status,
               let run = lastRun {
                Text(run.relativeTime)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        HStack(spacing: 6) {
            statusIcon
            statusText
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch modelState {
        case .uninitialized:
            Image(systemName: "questionmark.circle")
                .foregroundColor(.secondary)
        case .loading:
            ProgressView()
                .scaleEffect(0.7)
        case .ready(let snapshot):
            snapshotIcon(for: snapshot)
        case .operating:
            ProgressView()
                .scaleEffect(0.7)
        }
    }

    @ViewBuilder
    private func snapshotIcon(for snapshot: GitHubCIWorkflow.Snapshot) -> some View {
        switch snapshot.status {
        case .idle(let lastRun):
            if let run = lastRun {
                if run.isInProgress {
                    ProgressView()
                        .scaleEffect(0.7)
                } else if run.isSuccess {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                } else if run.isFailed {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                } else {
                    Image(systemName: "circle")
                        .foregroundColor(.secondary)
                }
            } else {
                Image(systemName: "circle")
                    .foregroundColor(.secondary)
            }
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(.red)
        }
    }

    @ViewBuilder
    private var statusText: some View {
        switch modelState {
        case .uninitialized:
            Text("Unknown")
                .font(.subheadline)
                .foregroundColor(.secondary)
        case .loading:
            Text("Loading...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        case .ready(let snapshot):
            snapshotText(for: snapshot)
        case .operating:
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Deploying...")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.blue)
                    if let detail = modelState.runDetail {
                        Text("#\(detail.number)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    if let createdAt = modelState.runDetail?.createdAt,
                       let elapsed = elapsedTimeString(from: createdAt) {
                        Text(elapsed)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                if let detail = modelState.runDetail {
                    Text(detail.displayTitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    @ViewBuilder
    private func snapshotText(for snapshot: GitHubCIWorkflow.Snapshot) -> some View {
        switch snapshot.status {
        case .idle(let lastRun):
            if let run = lastRun {
                VStack(alignment: .leading, spacing: 2) {
                    Text(statusLabel(for: run))
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(statusColor(for: run))
                    Text(run.title)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            } else {
                Text("No runs")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        case .success:
            Text("Success")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.green)
        case .failed(_, let reason):
            VStack(alignment: .leading, spacing: 2) {
                Text("Failed")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.red)
                Text(reason)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func statusLabel(for run: WorkflowRunInfo) -> String {
        if run.isInProgress {
            return "In Progress"
        } else if run.isSuccess {
            return "Success"
        } else if run.isFailed {
            return "Failed"
        } else {
            return run.status.capitalized
        }
    }

    private func statusColor(for run: WorkflowRunInfo) -> Color {
        if run.isInProgress {
            return .blue
        } else if run.isSuccess {
            return .green
        } else if run.isFailed {
            return .red
        } else {
            return .secondary
        }
    }

    // MARK: - Git Status Row

    @ViewBuilder
    private var gitStatusRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Repository
            HStack(spacing: 4) {
                Image(systemName: "link")
                    .font(.caption)
                Text(model.repository)
                    .font(.caption)
                    .textSelection(.enabled)
            }
            .foregroundColor(.secondary)

            HStack(spacing: 12) {
                // Branch
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.caption)
                    Text(modelState.currentBranch)
                        .font(.caption)
                }
                .foregroundColor(.secondary)

                // Uncommitted changes indicator
                if modelState.hasUncommittedChanges {
                    HStack(spacing: 4) {
                        Image(systemName: "pencil.circle.fill")
                            .font(.caption)
                        Text("Uncommitted")
                            .font(.caption)
                    }
                    .foregroundColor(.orange)
                }

                // Unpushed commits indicator
                if modelState.hasUnpushedCommits {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.caption)
                        Text("Unpushed")
                            .font(.caption)
                    }
                    .foregroundColor(.blue)
                }
            }
        }
    }

    // MARK: - Job Steps View

    @ViewBuilder
    private func jobStepsView(detail: GitHubRunDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()

            ForEach(detail.jobs.filter { !$0.isSkipped }, id: \.databaseId) { job in
                jobView(job: job)
            }
        }
    }

    @ViewBuilder
    private func jobView(job: GitHubJob) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            // Job header
            HStack(spacing: 6) {
                jobStatusIcon(job: job)
                Text(job.name)
                    .font(.caption)
                    .fontWeight(.medium)
            }

            // Steps
            VStack(alignment: .leading, spacing: 2) {
                ForEach(job.steps.filter { !$0.isSkipped }, id: \.number) { step in
                    stepView(step: step)
                }
            }
            .padding(.leading, 16)
        }
    }

    @ViewBuilder
    private func jobStatusIcon(job: GitHubJob) -> some View {
        if job.isInProgress {
            Image(systemName: "play.circle.fill")
                .font(.caption)
                .foregroundColor(.blue)
        } else if job.isSuccess {
            Image(systemName: "checkmark.circle.fill")
                .font(.caption)
                .foregroundColor(.green)
        } else if job.isFailed {
            Image(systemName: "xmark.circle.fill")
                .font(.caption)
                .foregroundColor(.red)
        } else {
            Image(systemName: "circle")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private func stepView(step: GitHubStep) -> some View {
        HStack(spacing: 6) {
            stepStatusIcon(step: step)
            Text(step.name)
                .font(.caption2)
                .foregroundColor(step.isInProgress ? .primary : .secondary)
        }
    }

    @ViewBuilder
    private func stepStatusIcon(step: GitHubStep) -> some View {
        if step.isInProgress {
            ProgressView()
                .scaleEffect(0.4)
                .frame(width: 10, height: 10)
        } else if step.isSuccess {
            Image(systemName: "checkmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(.green)
        } else if step.isFailed {
            Image(systemName: "xmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(.red)
        } else if step.isPending {
            Image(systemName: "circle")
                .font(.system(size: 6))
                .foregroundColor(.secondary)
        } else {
            Image(systemName: "minus")
                .font(.system(size: 8))
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Action Buttons

    @ViewBuilder
    private var actionButtons: some View {
        OperationOutputSection { _, showOutput in
            HStack(spacing: 12) {
                // Push & Deploy button
                Button {
                    showOutput()
                    Task {
                        await model.pushAndDeploy()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.circle")
                        Text(buttonLabel)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!modelState.canDeploy)

                // View Logs button
                if let runId = modelState.runId {
                    Button {
                        model.viewWorkflowLogs(runId: runId)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.text")
                            Text("View Logs")
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var buttonLabel: String {
        if modelState.hasUnpushedCommits {
            return "Push & Deploy"
        } else {
            return "Trigger Deploy"
        }
    }
}

// MARK: - Preview

#Preview {
    VStack {
        GitHubCILoadingView(onOpenSettings: {})
            .padding()
    }
    .frame(width: 400)
}
