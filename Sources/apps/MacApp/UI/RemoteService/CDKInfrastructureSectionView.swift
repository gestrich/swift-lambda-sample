import AWSSDK
import CLISDK
import DeployRemoteFeature
import SwiftUI

/// Placeholder when CDK infrastructure is not configured
struct CDKInfrastructureLoadingView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CDK Infrastructure")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                    Text("Not Configured")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }

                Text("Create ~/.swiftSampleDemo/aws-config.json:")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("""
                    {
                      "profileName": "your-profile",
                      "useAWSVault": false
                    }
                    """)
                    .font(.caption)
                    .fontDesign(.monospaced)
                    .foregroundColor(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.1))
            .cornerRadius(8)
        }
    }
}

/// View for the CDK Infrastructure section in Remote mode
/// Shows stack status, configuration, outputs, and deploy/destroy actions
struct CDKInfrastructureSectionView: View {
    @Bindable var service: DeployRemoteModel

    /// Callback to open settings
    var onOpenSettings: (() -> Void)?

    // Timer for updating elapsed time display
    @State private var currentTime = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    // Expand/collapse state for outputs
    @State private var showOutputs = false

    // Confirmation dialog for destroy
    @State private var showDestroyConfirmation = false

    // Expand/collapse state for error details
    @State private var showErrorDetails = false

    private var modelState: DeployRemoteModel.ModelState {
        service.state
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("CDK Infrastructure")
                    .font(.headline)

                Spacer()

                // Refresh button
                Button {
                    Task { await service.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(!modelState.isIdle)
                .help("Refresh status")
            }

            // Credential error banner (shown when AWS credentials are invalid)
            if case .ready(let snapshot) = modelState,
               case .credentialExpired(let message) = snapshot.status {
                AWSCredentialErrorBanner(
                    errorMessage: message,
                    onOpenSettings: onOpenSettings,
                    onRetry: {
                        Task { await service.refresh() }
                    }
                )
            } else if case .ready(let snapshot) = modelState,
                      case .failed(let reason) = snapshot.status,
                      AWSCredentialErrorBanner.isCredentialError(reason) {
                AWSCredentialErrorBanner(
                    errorMessage: reason,
                    onOpenSettings: onOpenSettings,
                    onRetry: {
                        Task { await service.refresh() }
                    }
                )
            } else {
                // Status card
                VStack(alignment: .leading, spacing: 10) {
                    // Stack name and status row
                    statusRow

                    // Configuration display (when deployed)
                    if modelState.isDeployed {
                        configurationRow
                    }

                    // Progress during deploy/destroy
                    if case .operating = modelState {
                        progressRow
                    }

                    // Action buttons
                    actionButtons

                    // Stack outputs (collapsible, when deployed)
                    if modelState.isDeployed, let outputs = modelState.outputs, !outputs.allOutputs.isEmpty {
                        outputsSection
                    }
                }
                .padding(12)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
            }
        }
        .onReceive(timer) { time in
            if case .operating = modelState {
                currentTime = time
            }
        }
    }

    // MARK: - Elapsed Time

    private var elapsedTimeString: String? {
        guard let startTime = modelState.operationStartTime else { return nil }

        let elapsed = currentTime.timeIntervalSince(startTime)
        let minutes = Int(elapsed) / 60
        let seconds = Int(elapsed) % 60

        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        } else {
            return "\(seconds)s"
        }
    }

    // MARK: - Status Row

    @ViewBuilder
    private var statusRow: some View {
        HStack(spacing: 8) {
            // Status badge
            statusBadge

            Spacer()

            // Stack name
            Text(service.stackName)
                .font(.caption)
                .foregroundColor(.secondary)
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
            switch snapshot.status {
            case .notDeployed:
                Image(systemName: "circle")
                    .foregroundColor(.secondary)
            case .deployed:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            case .failed, .credentialExpired:
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
            }
        case .operating:
            ProgressView()
                .scaleEffect(0.7)
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
            switch snapshot.status {
            case .notDeployed:
                Text("Not Deployed")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            case .deployed:
                Text("Deployed")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.green)
            case .failed(let reason):
                failedStatusView(reason: reason)
            case .credentialExpired(let message):
                failedStatusView(reason: message)
            }
        case .operating(let useCaseState, _):
            switch useCaseState {
            case .deploying(let progress):
                HStack(spacing: 6) {
                    Text(operationLabel(for: progress.step))
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.blue)
                    if let elapsed = elapsedTimeString {
                        Text(elapsed)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            case .destroying:
                HStack(spacing: 6) {
                    Text("Destroying...")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.orange)
                    if let elapsed = elapsedTimeString {
                        Text(elapsed)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            case .updatingLambda:
                HStack(spacing: 6) {
                    Text("Updating Lambda...")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.blue)
                    if let elapsed = elapsedTimeString {
                        Text(elapsed)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            case .completed:
                Text("Complete")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.green)
            }
        }
    }

    private func operationLabel(for step: UseCaseState.DeployProgress.Step) -> String {
        switch step {
        case .building: return "Building"
        case .deploying: return "Deploying"
        case .monitoring: return "Monitoring"
        }
    }

    @ViewBuilder
    private func failedStatusView(reason: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showErrorDetails.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Text("Failed")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.red)
                    Image(systemName: showErrorDetails ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundColor(.red)
                }
            }
            .buttonStyle(.plain)

            if showErrorDetails {
                ScrollView {
                    Text(reason)
                        .font(.caption)
                        .fontDesign(.monospaced)
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 150)
                .padding(8)
                .background(Color.black.opacity(0.3))
                .cornerRadius(4)
            } else {
                Text(reason)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
    }

    // MARK: - Configuration Row

    @ViewBuilder
    private var configurationRow: some View {
        let config = service.state.infrastructure ?? CDKInfrastructureConfiguration()
        HStack(spacing: 16) {
            // Database
            HStack(spacing: 4) {
                Image(systemName: config.hasDatabase ? "checkmark.circle.fill" : "xmark.circle")
                    .font(.caption)
                    .foregroundColor(config.hasDatabase ? .green : .secondary)
                Text("Database")
                    .font(.caption)
                    .foregroundColor(config.hasDatabase ? .primary : .secondary)
            }

            // NAT Gateway
            HStack(spacing: 4) {
                Image(systemName: config.hasNATGateway ? "checkmark.circle.fill" : "xmark.circle")
                    .font(.caption)
                    .foregroundColor(config.hasNATGateway ? .green : .secondary)
                Text("NAT Gateway")
                    .font(.caption)
                    .foregroundColor(config.hasNATGateway ? .primary : .secondary)
            }
        }
    }

    // MARK: - Progress Row

    /// Extract DeploymentProgress from current operation
    private var currentProgress: DeploymentProgress {
        guard case .operating(let useCaseState, _) = modelState else {
            return DeploymentProgress()
        }
        switch useCaseState {
        case .deploying(let progress):
            return progress.detail ?? DeploymentProgress()
        case .destroying(let progress):
            return progress.detail ?? DeploymentProgress()
        case .updatingLambda, .completed:
            return DeploymentProgress()
        }
    }

    /// Whether current operation is a deploy (vs destroy)
    private var isDeployOperation: Bool {
        guard case .operating(let useCaseState, _) = modelState else { return false }
        return useCaseState.isDeploying || useCaseState.isUpdatingLambda
    }

    @ViewBuilder
    private var progressRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()

            // Progress summary
            let progress = currentProgress
            if !progress.resources.isEmpty {
                HStack(spacing: 4) {
                    // "X of Y complete"
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                    Text("\(progress.completedCount) of \(progress.resources.count) complete")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    // In progress indicator
                    if progress.inProgressCount > 0 {
                        Text("·")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        ProgressView()
                            .scaleEffect(0.5)
                        Text("\(progress.inProgressCount) in progress")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // Resource list (show in-progress and recent completed)
                resourceProgressList
            } else if progress.hasPolledEnough {
                // We've polled many times but found no new events
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.5)
                    if isDeployOperation {
                        Text("Waiting for CloudFormation to start...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Waiting for resources to be deleted...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } else if progress.hasPolled {
                // Still early - CDK is preparing the operation
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.5)
                    if isDeployOperation {
                        Text("Preparing CloudFormation changeset...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Preparing to delete resources...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                // Still waiting for first poll
                if case .operating(let useCaseState, _) = modelState {
                    switch useCaseState {
                    case .deploying(let deployProgress):
                        Text("\(operationLabel(for: deployProgress.step))...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    case .destroying:
                        Text("Removing AWS resources...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    case .updatingLambda:
                        Text("Updating Lambda...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    case .completed:
                        Text("Complete")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Resource Progress List

    @ViewBuilder
    private var resourceProgressList: some View {
        let progress = currentProgress
        let inProgress = progress.resources.filter { $0.status.isInProgress }
        let completed = progress.resources.filter { $0.status.isComplete }.prefix(3)
        let failed = progress.resources.filter { $0.status.isFailed }

        VStack(alignment: .leading, spacing: 4) {
            // Show failed resources first
            ForEach(failed) { resource in
                resourceRow(resource)
            }

            // Show in-progress resources
            ForEach(inProgress) { resource in
                resourceRow(resource)
            }

            // Show recent completed (up to 3)
            ForEach(completed, id: \.id) { resource in
                resourceRow(resource)
            }
        }
    }

    @ViewBuilder
    private func resourceRow(_ resource: ResourceProgress) -> some View {
        HStack(spacing: 6) {
            // Status icon
            resourceStatusIcon(resource.status)

            // Resource info
            VStack(alignment: .leading, spacing: 1) {
                Text(resource.resourceType)
                    .font(.caption2)
                    .foregroundColor(resource.status.isInProgress ? .primary : .secondary)
                    .lineLimit(1)

                if let reason = resource.statusReason, resource.status.isFailed {
                    Text(reason)
                        .font(.caption2)
                        .foregroundColor(.red)
                        .lineLimit(1)
                }
            }
        }
        .padding(.leading, 8)
    }

    @ViewBuilder
    private func resourceStatusIcon(_ status: ResourceStatus) -> some View {
        switch status {
        case .pending:
            Image(systemName: "circle")
                .font(.system(size: 8))
                .foregroundColor(.secondary)
        case .inProgress:
            ProgressView()
                .scaleEffect(0.4)
                .frame(width: 10, height: 10)
        case .complete:
            Image(systemName: "checkmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(.green)
        case .failed:
            Image(systemName: "xmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(.red)
        }
    }

    // MARK: - Action Buttons

    @ViewBuilder
    private var actionButtons: some View {
        OperationOutputSection { stream, showOutput in
            HStack(spacing: 12) {
                // Deploy button with options menu
                Menu {
                    Button {
                        showOutput()
                        Task {
                            await service.deploy(
                                options: .init(withPostgres: false, withNATGateway: false, output: stream)
                            )
                        }
                    } label: {
                        Label("Minimal (No Database)", systemImage: "leaf")
                    }

                    Button {
                        showOutput()
                        Task {
                            await service.deploy(
                                options: .init(withPostgres: true, withNATGateway: false, output: stream)
                            )
                        }
                    } label: {
                        Label("With PostgreSQL", systemImage: "cylinder")
                    }

                    Button {
                        showOutput()
                        Task {
                            await service.deploy(
                                options: .init(withPostgres: true, withNATGateway: true, output: stream)
                            )
                        }
                    } label: {
                        Label("Full (PostgreSQL + NAT)", systemImage: "server.rack")
                    }

                    if modelState.isDeployed {
                        Divider()

                        Button {
                            showOutput()
                            Task {
                                await service.updateInfrastructure(output: stream)
                            }
                        } label: {
                            Label("Update (Keep Config)", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "cloud.fill")
                        Text(deployButtonLabel)
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                    }
                }
                .menuStyle(.borderedButton)
                .disabled(!modelState.canDeploy)

                // Destroy button
                if modelState.canDestroy {
                    Button {
                        showDestroyConfirmation = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "trash")
                            Text("Destroy")
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
            }
            .confirmationDialog(
                "Destroy Infrastructure?",
                isPresented: $showDestroyConfirmation,
                titleVisibility: .visible
            ) {
                Button("Destroy", role: .destructive) {
                    showOutput()
                    Task {
                        await service.destroy(output: stream)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete all AWS resources including Lambda, API Gateway, S3 bucket, and database (if deployed). This action cannot be undone.")
            }
        }
    }

    private var deployButtonLabel: String {
        switch modelState {
        case .uninitialized, .loading:
            return "Deploy"
        case .ready(let snapshot):
            switch snapshot.status {
            case .notDeployed:
                return "Deploy"
            case .deployed:
                return "Update"
            case .failed, .credentialExpired:
                return "Retry"
            }
        case .operating:
            return "Deploy"
        }
    }

    // MARK: - Outputs Section

    @ViewBuilder
    private var outputsSection: some View {
        let outputs = service.state.outputs ?? CDKStackOutputs()
        VStack(alignment: .leading, spacing: 8) {
            Divider()

            // Collapsible header
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showOutputs.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: showOutputs ? "chevron.down" : "chevron.right")
                        .font(.caption)
                    Text("Stack Outputs")
                        .font(.caption)
                        .fontWeight(.medium)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundColor(.primary)

            if showOutputs {
                VStack(alignment: .leading, spacing: 6) {
                    // API URL (highlighted)
                    if let apiUrl = outputs.apiGatewayUrl {
                        outputRow(key: "API URL", value: apiUrl, copyable: true)
                    }

                    // Other outputs
                    ForEach(outputs.allOutputs.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                        if key != "ApiGatewayUrl" {
                            outputRow(key: key, value: value, copyable: true)
                        }
                    }
                }
                .padding(.leading, 16)
            }
        }
    }

    @ViewBuilder
    private func outputRow(key: String, value: String, copyable: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(key + ":")
                .font(.caption2)
                .foregroundColor(.secondary)
                .frame(width: 100, alignment: .trailing)

            Text(value)
                .font(.caption2)
                .fontDesign(.monospaced)
                .foregroundColor(.primary)
                .lineLimit(1)
                .truncationMode(.middle)

            if copyable {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(value, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption2)
                }
                .buttonStyle(.borderless)
                .help("Copy to clipboard")
            }
        }
    }
}

// MARK: - Preview

#Preview {
    VStack {
        CDKInfrastructureLoadingView()
            .padding()
    }
    .frame(width: 400)
}
