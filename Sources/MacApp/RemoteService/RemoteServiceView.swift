import AppKit
import CLIKit
import SwiftDeploy
import SwiftUI

/// View for Remote (AWS) Lambda service management
/// Connects directly to RemoteService without going through MacAppModel
struct RemoteServiceView: View {
    @State var service: RemoteService

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // MARK: - CDK Infrastructure Section
                    cdkInfrastructureSection

                    Divider()

                    // MARK: - GitHub CI Section
                    githubCISection

                    Divider()

                    // MARK: - Endpoint Section
                    endpointSection
                }
                .padding(20)
            }

            Divider()

            // Output and command input pinned to bottom
            VStack(alignment: .leading, spacing: 8) {
                outputSection
                commandInputSection
            }
            .padding(20)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            service.refreshStatus()
        }
    }

    // MARK: - CDK Infrastructure Section

    @ViewBuilder
    private var cdkInfrastructureSection: some View {
        if let cdkService = service.cdkInfrastructureService {
            CDKInfrastructureSectionView(service: cdkService)
                .onAppear {
                    Task { await cdkService.refreshStatus() }
                }
        } else {
            CDKInfrastructureLoadingView()
        }
    }

    // MARK: - GitHub CI Section

    @ViewBuilder
    private var githubCISection: some View {
        if let ghService = service.githubService {
            GitHubCISectionView(service: ghService)
                .onAppear {
                    Task { await ghService.refreshStatus() }
                }
        } else {
            GitHubCILoadingView()
        }
    }

    // MARK: - Endpoint Section

    @ViewBuilder
    private var endpointSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Remote Lambda")
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
            VStack(alignment: .leading, spacing: 5) {
                Text(service.endpointLabel)
                    .font(.caption)
                    .foregroundColor(.secondary)

                TextField("Endpoint", text: .constant(service.endpoint))
                    .textFieldStyle(.roundedBorder)
                    .disabled(true)

                Text(service.endpointHelpText)
                    .font(.caption2)
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

    // MARK: - Output Section

    @ViewBuilder
    private var outputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Output")
                .font(.headline)

            StreamingTextView(streamProvider: { await service.cliService.outputStream() })
                .id(RemoteService.persistenceKey)
        }
    }

    // MARK: - Command Input Section

    @State private var commandText = ""

    @ViewBuilder
    private var commandInputSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            CommandInputView(text: $commandText) { command in
                runCommand(command)
            }

            Text("Type a command and press Enter. Tab to autocomplete, arrows to navigate.")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

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
