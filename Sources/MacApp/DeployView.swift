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

                    // MARK: - Remote-Only Sections (CDK Infrastructure, then GitHub CI for code deploy)
                    if model.mode.isRemote {
                        cdkInfrastructureSection

                        Divider()

                        githubCISection
                    }

                    // MARK: - Local-Only Sections (Docker Services, Build, Lambda)
                    // Uses protocol conformance - sections only render if provider exists
                    if model.dockerServicesProvider != nil {
                        dockerServicesSection

                        Divider()
                    }

                    if model.buildProvider != nil {
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
        if let dockerProvider = model.dockerServicesProvider {
            VStack(alignment: .leading, spacing: 12) {
                Text("Docker Services")
                    .font(.headline)

                // S3 (MinIO) Row
                DockerServiceRow(
                    name: "S3 (MinIO)",
                    state: model.status.s3State,
                    dataDirectory: dockerProvider.s3DataDirectory,
                    onStart: {
                        try await dockerProvider.startS3()
                        model.refreshStatus()
                    },
                    onStop: {
                        try await dockerProvider.stopS3()
                        model.refreshStatus()
                    }
                )

                // PostgreSQL Row
                DockerServiceRow(
                    name: "PostgreSQL",
                    state: model.status.postgresState,
                    dataDirectory: dockerProvider.postgresDataDirectory,
                    onStart: {
                        try await dockerProvider.startDatabase()
                        model.refreshStatus()
                    },
                    onStop: {
                        try await dockerProvider.stopDatabase()
                        model.refreshStatus()
                    }
                )
            }
        }
    }

    // MARK: - Build Section

    @ViewBuilder
    private var buildSection: some View {
        if let buildProvider = model.buildProvider {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Build")
                        .font(.headline)

                    Spacer()

                    // Build status badge
                    buildStatusBadge(for: buildProvider)

                    Button(action: {
                        Task {
                            try? await buildProvider.build(clean: false)
                        }
                    }) {
                        if buildProvider.buildState.status.isBuilding {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: "hammer")
                        }
                    }
                    .buttonStyle(.borderless)
                    .disabled(buildProvider.buildState.status.isBuilding)
                    .help("Build Lambda")

                    Button(action: {
                        Task {
                            try? await buildProvider.build(clean: true)
                        }
                    }) {
                        Image(systemName: "sparkles")
                    }
                    .buttonStyle(.borderless)
                    .disabled(buildProvider.buildState.status.isBuilding)
                    .help("Clean and Build Lambda")

                    if buildProvider.buildState.status.hasArtifact {
                        Button(action: {
                            Task {
                                try? await buildProvider.deleteBuild()
                            }
                        }) {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .disabled(buildProvider.buildState.status.isBuilding)
                        .help("Delete Build")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func buildStatusBadge(for buildProvider: LocalBuildProvider) -> some View {
        let status = buildProvider.buildState.status
        HStack(spacing: 4) {
            if status.showProgress {
                ProgressView()
                    .scaleEffect(0.6)
            } else {
                Image(systemName: status.iconName)
                    .foregroundColor(buildStatusColor(for: buildProvider))
            }
            Text(status.displayText)
                .font(.caption2)
                .foregroundColor(buildStatusColor(for: buildProvider))
        }
    }

    private func buildStatusColor(for buildProvider: LocalBuildProvider) -> Color {
        switch buildProvider.buildState.status.colorName {
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

    // MARK: - CDK Infrastructure Section

    @ViewBuilder
    private var cdkInfrastructureSection: some View {
        if let cdkService = model.cdkInfrastructureService {
            CDKInfrastructureSectionView(service: cdkService)
                .onAppear {
                    Task { await cdkService.refreshStatus() }
                }
        } else {
            // Show loading/placeholder while CDKInfrastructureService initializes
            CDKInfrastructureLoadingView()
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
    let dataDirectory: String
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
            Button(action: {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: dataDirectory)
            }) {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            .help("Open data directory: \(dataDirectory)")

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
