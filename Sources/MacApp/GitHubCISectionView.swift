import SwiftDeploy
import SwiftUI

/// Loading placeholder while GitHubService initializes
struct GitHubCILoadingView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("GitHub CI")
                .font(.headline)

            HStack {
                ProgressView()
                    .scaleEffect(0.7)
                Text("Loading...")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
        }
    }
}

/// View for the GitHub CI section in Remote mode
/// Shows workflow status, job/step progress during deployment, and action buttons
struct GitHubCISectionView: View {
    var service: GitHubService
    let onPushAndDeploy: () -> Void
    let onViewLogs: (String) -> Void
    let onRefresh: () -> Void

    private var ciStatus: GitHubCIStatus {
        service.ciStatus
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("GitHub CI")
                    .font(.headline)

                Spacer()

                // Refresh button
                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(ciStatus.status.isDeploying)
                .help("Refresh status")
            }

            // Status card
            VStack(alignment: .leading, spacing: 10) {
                // Status row
                statusRow

                // Git status
                if !ciStatus.currentBranch.isEmpty {
                    gitStatusRow
                }

                // Job/Step progress during deployment
                if ciStatus.status.isDeploying, let detail = ciStatus.runDetail {
                    jobStepsView(detail: detail)
                }

                // Action buttons
                actionButtons
            }
            .padding(12)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
        }
    }

    // MARK: - Status Row

    @ViewBuilder
    private var statusRow: some View {
        HStack(spacing: 8) {
            // Status badge
            statusBadge

            Spacer()

            // Last run info
            if case .idle(let lastRun) = ciStatus.status, let run = lastRun {
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
        switch ciStatus.status {
        case .unknown:
            Image(systemName: "questionmark.circle")
                .foregroundColor(.secondary)
        case .loading:
            ProgressView()
                .scaleEffect(0.7)
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
        case .deploying:
            ProgressView()
                .scaleEffect(0.7)
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
        switch ciStatus.status {
        case .unknown:
            Text("Unknown")
                .font(.subheadline)
                .foregroundColor(.secondary)
        case .loading:
            Text("Loading...")
                .font(.subheadline)
                .foregroundColor(.secondary)
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
        case .deploying:
            VStack(alignment: .leading, spacing: 2) {
                Text("Deploying...")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.blue)
                if let detail = ciStatus.runDetail {
                    Text(detail.displayTitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
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

    private func statusLabel(for run: GitHubCIStatus.WorkflowRunInfo) -> String {
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

    private func statusColor(for run: GitHubCIStatus.WorkflowRunInfo) -> Color {
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
        HStack(spacing: 12) {
            // Branch
            HStack(spacing: 4) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.caption)
                Text(ciStatus.currentBranch)
                    .font(.caption)
            }
            .foregroundColor(.secondary)

            // Uncommitted changes indicator
            if ciStatus.hasUncommittedChanges {
                HStack(spacing: 4) {
                    Image(systemName: "pencil.circle.fill")
                        .font(.caption)
                    Text("Uncommitted")
                        .font(.caption)
                }
                .foregroundColor(.orange)
            }

            // Unpushed commits indicator
            if ciStatus.hasUnpushedCommits {
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
            ProgressView()
                .scaleEffect(0.5)
                .frame(width: 12, height: 12)
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
        HStack(spacing: 12) {
            // Push & Deploy button
            Button(action: onPushAndDeploy) {
                HStack(spacing: 4) {
                    if ciStatus.status.isDeploying {
                        ProgressView()
                            .scaleEffect(0.6)
                    } else {
                        Image(systemName: "arrow.up.circle")
                    }
                    Text(buttonLabel)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!ciStatus.status.canDeploy)

            // View Logs button
            if let runId = ciStatus.status.runId {
                Button(action: { onViewLogs(runId) }) {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.text")
                        Text("View Logs")
                    }
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var buttonLabel: String {
        if ciStatus.status.isDeploying {
            return "Deploying..."
        } else if ciStatus.hasUnpushedCommits {
            return "Push & Deploy"
        } else {
            return "Trigger Deploy"
        }
    }
}

// MARK: - Preview

#Preview {
    VStack {
        GitHubCILoadingView()
            .padding()
    }
    .frame(width: 400)
}
