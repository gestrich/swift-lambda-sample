import AppKit
import Client
import CLIKit
import SwiftDeploy
import SwiftUI

/// View for Local Lambda service management (Xcode or Linux)
/// Shows Docker services, build controls, and Lambda management
/// The service mode (Xcode vs Linux) is controlled by the parent ServicesView
struct LocalServiceView: View {
    @Environment(MacAppModel.self) var model

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // MARK: - Docker Services Section
                    if let dockerProvider = model.dockerServicesProvider {
                        DockerServicesView(
                            dockerProvider: dockerProvider,
                            s3State: model.status.s3State,
                            postgresState: model.status.postgresState,
                            onRefreshStatus: { model.refreshStatus() }
                        )

                        Divider()
                    }

                    // MARK: - Build Section
                    if model.buildProvider != nil {
                        buildSection

                        Divider()
                    }

                    // MARK: - Lambda Section
                    if model.lambdaProvider != nil {
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
        if let lambdaProvider = model.lambdaProvider {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Lambda")
                        .font(.headline)

                    Spacer()

                    // Lambda status badge
                    lambdaStatusBadge(for: lambdaProvider)

                    Button(action: {
                        Task {
                            await model.startServices()
                        }
                    }) {
                        if lambdaProvider.lambdaState.status.isTransitioning {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: "play.circle")
                        }
                    }
                    .buttonStyle(.borderless)
                    .disabled(lambdaProvider.lambdaState.status.isTransitioning)
                    .help("Start Lambda")

                    Button(action: {
                        Task {
                            try? await lambdaProvider.stopWithServices()
                        }
                    }) {
                        Image(systemName: "stop.circle")
                    }
                    .buttonStyle(.borderless)
                    .disabled(lambdaProvider.lambdaState.status.isTransitioning || lambdaProvider.lambdaState.status == .stopped)
                    .help("Stop Lambda")

                    Button(action: { model.refreshStatus() }) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .disabled(lambdaProvider.lambdaState.status.isTransitioning)
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
    }

    @ViewBuilder
    private func lambdaStatusBadge(for lambdaProvider: LocalLambdaProvider) -> some View {
        let status = lambdaProvider.lambdaState.status
        HStack(spacing: 4) {
            if status.showProgress {
                ProgressView()
                    .scaleEffect(0.6)
            } else {
                Image(systemName: status.iconName)
                    .foregroundColor(lambdaStatusColor(for: lambdaProvider))
            }
            Text(status.displayText)
                .font(.caption2)
                .foregroundColor(lambdaStatusColor(for: lambdaProvider))
        }
    }

    private func lambdaStatusColor(for lambdaProvider: LocalLambdaProvider) -> Color {
        switch lambdaProvider.lambdaState.status.colorName {
        case "blue": return .blue
        case "green": return .green
        case "orange": return .orange
        case "red": return .red
        case "secondary": return .secondary
        default: return .primary
        }
    }

    // MARK: - Unified Output Section

    @ViewBuilder
    private var unifiedOutputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Output")
                .font(.headline)

            // Use mode-specific CLI output stream - each mode has isolated output
            StreamingTextView(streamProvider: { await model.cliService.outputStream() })
                .id(model.mode.persistenceKey) // Reset view when mode changes
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
            _ = try? await model.cliService.execute(
                command: command,
                arguments: arguments
            )
        }
    }
}

#Preview {
    let model = MacAppModel()
    return LocalServiceView()
        .environment(model)
}
