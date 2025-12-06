import AppKit
import CLIKit
import SwiftDeploy
import SwiftUI

/// View for Remote (AWS) Lambda service management
/// Connects directly to RemoteService without going through MacAppModel
struct RemoteServiceView: View {
    @State var service: RemoteService

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

                    // MARK: - GitHub CI Section
                    githubCISection
                }
                .padding(20)
            }

            // Collapsible output panel pinned to bottom
            CollapsibleOutputPanel(
                streamProvider: { await service.cliService.outputStream() },
                streamId: RemoteService.persistenceKey,
                onCommand: { runCommand($0) }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - CDK Infrastructure Section

    @ViewBuilder
    private var cdkInfrastructureSection: some View {
        if let cdkService = service.cdkInfrastructureService {
            CDKInfrastructureSectionView(service: cdkService, onOpenSettings: onOpenSettings)
        } else {
            CDKInfrastructureLoadingView()
        }
    }

    // MARK: - GitHub CI Section

    @ViewBuilder
    private var githubCISection: some View {
        if let ghService = service.githubService {
            GitHubCISectionView(service: ghService)
        } else {
            GitHubCILoadingView(onOpenSettings: onOpenSettings)
        }
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
    let service = RemoteService(workingDirectory: FileManager.default.currentDirectoryPath)
    return RemoteServiceView(service: service)
        .padding()
        .frame(width: 500)
}
