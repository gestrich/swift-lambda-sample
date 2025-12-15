import AppKit
import sdk_cli
import SwiftUI

/// View for Remote (AWS) Lambda service management
/// Connects directly to RemoteModel without going through MacAppModel
struct RemoteServiceView: View {
    @State var service: RemoteModel

    /// Callback to open settings
    var onOpenSettings: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // MARK: - CDK Infrastructure Section
                    cdkInfrastructureSection

                    Divider()

                    // MARK: - Endpoint Section
                    endpointSection

                    Divider()

                    // MARK: - CloudWatch Logs Section
                    cloudWatchLogsSection

                    Divider()

                    // MARK: - Lambda Update Section
                    lambdaUpdateSection
                }
                .padding(20)
            }

            // Collapsible output panel pinned to bottom
            CollapsibleOutputPanel(
                streamProvider: { await service.cliService.outputStream() },
                streamId: RemoteModel.persistenceKey,
                onCommand: { runCommand($0) }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - CDK Infrastructure Section

    @ViewBuilder
    private var cdkInfrastructureSection: some View {
        if service.isCDKConfigured {
            CDKInfrastructureSectionView(
                model: service,
                onOpenSettings: onOpenSettings
            )
        } else {
            CDKInfrastructureLoadingView()
        }
    }

    // MARK: - Lambda Update Section

    @ViewBuilder
    private var lambdaUpdateSection: some View {
        LambdaUpdateView(service: service, onOpenSettings: onOpenSettings)
    }

    // MARK: - Endpoint Section

    @ViewBuilder
    private var endpointSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("API Gateway")
                    .font(.headline)

                Spacer()

                // Status badge
                remoteStatusBadge

                Button(action: { service.refreshStatus() }) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh status")
            }

            // Endpoint
            CopyableEndpointView(
                label: service.endpointLabel,
                endpoint: service.endpoint,
                helpText: service.endpointHelpText
            )
        }
    }

    // MARK: - CloudWatch Logs Section

    @ViewBuilder
    private var cloudWatchLogsSection: some View {
        if let logsModel = service.cloudWatchLogsModel {
            CloudWatchLogsSectionView(model: logsModel)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("CloudWatch Logs")
                    .font(.headline)
                Text("AWS configuration required")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private var remoteStatusBadge: some View {
        HStack(spacing: 4) {
            if service.isConfigured {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Connected")
                    .font(.caption2)
                    .foregroundColor(.green)
            } else {
                Image(systemName: "circle")
                    .foregroundColor(.secondary)
                Text("Not Configured")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Command Execution

    private func runCommand(_ commandString: String) {
        let parts = commandString.components(separatedBy: " ").filter { !$0.isEmpty }
        guard let command = parts.first else { return }
        let arguments = Array(parts.dropFirst())

        Task {
            _ = try? await service.cliService.execute(
                command: command,
                arguments: arguments
            )
        }
    }
}

// MARK: - Preview

#Preview {
    let service = RemoteModel(workingDirectory: FileManager.default.currentDirectoryPath)
    return RemoteServiceView(service: service)
        .padding()
        .frame(width: 500)
}
