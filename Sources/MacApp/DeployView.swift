import AppKit
import Client
import CLIKit
import SwiftDeploy
import SwiftUI

struct DeployView: View {
    @Environment(MacAppModel.self) var model

    private var modeBinding: Binding<String> {
        Binding(
            get: { model.mode.persistenceKey },
            set: { key in
                switch key {
                case RemoteService.persistenceKey:
                    model.setRemote()
                case XcodeLocalService.persistenceKey:
                    model.setLocalXcode()
                case LinuxLocalService.persistenceKey:
                    model.setLocalLinux()
                default:
                    break
                }
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // MARK: - Mode Picker
                    modePickerSection

                    Divider()

                    // MARK: - About Section
                    aboutSection

                    Divider()

                    // MARK: - Remote-Only Sections (GitHub CI)
                    if model.mode.isRemote {
                        githubCISection
                    }

                    // MARK: - Local-Only Sections (Docker Services, Build, Lambda)
                    if !model.mode.isRemote {
                        dockerServicesSection

                        Divider()

                        buildSection

                        Divider()

                        lambdaSection
                    }
                }
                .padding(20)
            }

            Divider()

            // Output and command input pinned to bottom
            VStack(alignment: .leading, spacing: 8) {
                unifiedOutputSection
                commandInputSection
            }
            .padding(20)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            model.refreshStatus()
        }
    }

    // MARK: - Mode Picker Section

    @ViewBuilder
    private var modePickerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Lambda Mode")
                .font(.headline)

            Picker("Lambda Mode", selection: modeBinding) {
                Text("Remote").tag(RemoteService.persistenceKey)
                Text("Local Xcode").tag(XcodeLocalService.persistenceKey)
                Text("Local Linux").tag(LinuxLocalService.persistenceKey)
            }
            .pickerStyle(.segmented)

            Text(model.mode.detailText)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - About Section

    @ViewBuilder
    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("About")
                .font(.headline)

            Text("Swift Lambda Sample")
                .font(.title2)
                .fontWeight(.semibold)

            Text("This application connects to either a remote AWS Lambda API Gateway or a local Lambda instance for managing users and testing S3 file operations.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Docker Services Section

    @ViewBuilder
    private var dockerServicesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Docker Services")
                .font(.headline)

            // S3 (MinIO) Row
            DockerServiceRow(
                name: "S3 (MinIO)",
                state: model.status.s3State,
                dataDirectory: model.s3DataDirectory,
                onStart: { try await model.startS3() },
                onStop: { try await model.stopS3() }
            )

            // PostgreSQL Row
            DockerServiceRow(
                name: "PostgreSQL",
                state: model.status.postgresState,
                dataDirectory: model.postgresDataDirectory,
                onStart: { try await model.startDatabase() },
                onStop: { try await model.stopDatabase() }
            )
        }
    }

    // MARK: - Build Section

    @ViewBuilder
    private var buildSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Build")
                    .font(.headline)

                Spacer()

                // Build status badge
                buildStatusBadge

                Button(action: {
                    Task {
                        try? await model.buildLambda(clean: false)
                    }
                }) {
                    if model.mode.buildState.status.isBuilding {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Image(systemName: "hammer")
                    }
                }
                .buttonStyle(.borderless)
                .disabled(model.mode.buildState.status.isBuilding)
                .help("Build Lambda")

                Button(action: {
                    Task {
                        try? await model.buildLambda(clean: true)
                    }
                }) {
                    Image(systemName: "sparkles")
                }
                .buttonStyle(.borderless)
                .disabled(model.mode.buildState.status.isBuilding)
                .help("Clean and Build Lambda")

                if model.mode.buildState.status.hasArtifact {
                    Button(action: {
                        Task {
                            try? await model.deleteBuild()
                        }
                    }) {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .disabled(model.mode.buildState.status.isBuilding)
                    .help("Delete Build")
                }
            }
        }
    }

    @ViewBuilder
    private var buildStatusBadge: some View {
        let status = model.mode.buildState.status
        HStack(spacing: 4) {
            if status.showProgress {
                ProgressView()
                    .scaleEffect(0.6)
            } else {
                Image(systemName: status.iconName)
                    .foregroundColor(buildStatusColor)
            }
            Text(status.displayText)
                .font(.caption2)
                .foregroundColor(buildStatusColor)
        }
    }

    private var buildStatusColor: Color {
        switch model.mode.buildState.status.colorName {
        case "blue": return .blue
        case "green": return .green
        case "orange": return .orange
        case "red": return .red
        case "secondary": return .secondary
        default: return .primary
        }
    }

    // MARK: - Lambda Section

    @ViewBuilder
    private var lambdaSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Lambda")
                    .font(.headline)

                Spacer()

                // Lambda status badge
                lambdaStatusBadge

                Button(action: {
                    Task {
                        await model.startServices()
                    }
                }) {
                    if model.mode.lambdaState.status.isTransitioning {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Image(systemName: "play.circle")
                    }
                }
                .buttonStyle(.borderless)
                .disabled(model.mode.lambdaState.status.isTransitioning)
                .help("Start Lambda")

                Button(action: {
                    Task {
                        try? await model.stopWithServices()
                    }
                }) {
                    Image(systemName: "stop.circle")
                }
                .buttonStyle(.borderless)
                .disabled(model.mode.lambdaState.status.isTransitioning || model.mode.lambdaState.status == .stopped)
                .help("Stop Lambda")

                Button(action: { model.refreshStatus() }) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(model.mode.lambdaState.status.isTransitioning)
                .help("Refresh status")
            }

            // Endpoint
            VStack(alignment: .leading, spacing: 5) {
                Text("Endpoint")
                    .font(.caption)
                    .foregroundColor(.secondary)

                TextField("Endpoint", text: .constant(model.endpoint))
                    .textFieldStyle(.roundedBorder)
                    .disabled(true)

                Text(model.endpointHelpText)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private var lambdaStatusBadge: some View {
        let status = model.mode.lambdaState.status
        HStack(spacing: 4) {
            if status.showProgress {
                ProgressView()
                    .scaleEffect(0.6)
            } else {
                Image(systemName: status.iconName)
                    .foregroundColor(lambdaStatusColor)
            }
            Text(status.displayText)
                .font(.caption2)
                .foregroundColor(lambdaStatusColor)
        }
    }

    private var lambdaStatusColor: Color {
        switch model.mode.lambdaState.status.colorName {
        case "blue": return .blue
        case "green": return .green
        case "orange": return .orange
        case "red": return .red
        case "secondary": return .secondary
        default: return .primary
        }
    }

    // MARK: - GitHub CI Section

    @ViewBuilder
    private var githubCISection: some View {
        if let ghService = model.githubService {
            GitHubCISectionView(service: ghService)
                .onAppear {
                    Task { await ghService.refreshStatus() }
                }
        } else {
            // Show loading/placeholder while GitHubService initializes
            GitHubCILoadingView()
        }
    }

    // MARK: - Unified Output Section

    @ViewBuilder
    private var unifiedOutputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Output")
                .font(.headline)

            // Use global CLI output stream - each view gets its own subscription
            StreamingTextView(streamProvider: { await CLIService.shared.outputStream() })
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
            _ = try? await CLIService.shared.execute(
                command: command,
                arguments: arguments
            )
        }
    }
}

// MARK: - Docker Service Row

private struct DockerServiceRow: View {
    let name: String
    let state: ServiceState
    let dataDirectory: String?
    let onStart: () async throws -> Void
    let onStop: () async throws -> Void

    @State private var isLoading = false

    private var stateColor: Color {
        switch state {
        case .running: return .green
        case .starting, .stopping: return .orange
        case .stopped: return .gray
        }
    }

    private var stateText: String {
        switch state {
        case .running: return "Running"
        case .starting: return "Starting..."
        case .stopping: return "Stopping..."
        case .stopped: return "Stopped"
        }
    }

    var body: some View {
        HStack {
            // Status indicator
            Circle()
                .fill(stateColor)
                .frame(width: 8, height: 8)

            // Service name and status
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(stateText)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Data directory button
            if let dataDir = dataDirectory {
                Button(action: {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: dataDir)
                }) {
                    Image(systemName: "folder")
                }
                .buttonStyle(.borderless)
                .help("Open data directory: \(dataDir)")
            }

            // Start/Stop button
            if isLoading || state.isTransitioning {
                ProgressView()
                    .scaleEffect(0.7)
                    .frame(width: 20)
            } else if state == .running {
                Button(action: {
                    Task {
                        isLoading = true
                        defer { isLoading = false }
                        try? await onStop()
                    }
                }) {
                    Image(systemName: "stop.circle")
                }
                .buttonStyle(.borderless)
                .help("Stop \(name)")
            } else {
                Button(action: {
                    Task {
                        isLoading = true
                        defer { isLoading = false }
                        try? await onStart()
                    }
                }) {
                    Image(systemName: "play.circle")
                }
                .buttonStyle(.borderless)
                .help("Start \(name)")
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(6)
    }
}

// MARK: - Status Indicator View

private struct StatusIndicator: View {
    let label: String
    let state: ServiceState

    private var color: Color {
        switch state {
        case .running: return .green
        case .starting, .stopping: return .orange
        case .stopped: return .gray
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.caption2)
        }
    }
}

#Preview {
    let model = MacAppModel()
    return DeployView()
        .environment(model)
}
