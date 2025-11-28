import Client
import SwiftUI
import SwiftDeploy

struct SettingsView: View {
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
        VStack(spacing: 20) {
            Text("Settings")
                .font(.title)
                .padding(.top)

            Divider()

            VStack(alignment: .leading, spacing: 15) {
                Text("API Configuration")
                    .font(.headline)

                // Mode Picker
                VStack(alignment: .leading, spacing: 5) {
                    Text("Lambda Mode")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Picker("Lambda Mode", selection: modeBinding) {
                        Text("Remote").tag(RemoteService.persistenceKey)
                        Text("Local Xcode").tag(XcodeLocalService.persistenceKey)
                        Text("Local Linux").tag(LinuxLocalService.persistenceKey)
                    }
                    .pickerStyle(.segmented)

                    Text(model.mode.detailText)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                // Endpoint section
                VStack(alignment: .leading, spacing: 5) {
                    Text(model.endpointLabel)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    TextField("Endpoint", text: .constant(model.endpoint))
                        .textFieldStyle(.roundedBorder)
                        .disabled(true)

                    Text(model.endpointHelpText)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                // Service Status Section
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Service Status")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Spacer()

                        Button(action: {
                            Task {
                                await model.startServices()
                            }
                        }) {
                            if model.status.lambdaState.isTransitioning {
                                ProgressView()
                                    .scaleEffect(0.7)
                            } else {
                                Image(systemName: "play.circle")
                            }
                        }
                        .buttonStyle(.borderless)
                        .disabled(model.status.lambdaState.isTransitioning)
                        .help("Start services")

                        Button(action: { model.refreshStatus() }) {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.borderless)
                        .disabled(model.status.lambdaState.isTransitioning)
                        .help("Refresh status")
                    }

                    HStack(spacing: 20) {
                        StatusIndicator(label: "Lambda", state: model.status.lambdaState)
                        StatusIndicator(label: "S3", state: model.status.s3State)
                        StatusIndicator(label: "PostgreSQL", state: model.status.postgresState)
                    }
                    .padding(.vertical, 4)
                }

                // Build Section
                buildSection

                Divider()
                    .padding(.top)

                // Current Configuration
                VStack(alignment: .leading, spacing: 10) {
                    Text("Current Configuration")
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text("Mode:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(model.mode.displayName)
                                .font(.caption)
                                .textSelection(.enabled)
                        }
                        HStack {
                            Text("Configured:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(model.isConfigured ? "Yes" : "No")
                                .font(.caption)
                                .foregroundColor(model.isConfigured ? .green : .red)
                        }
                        HStack {
                            Text("Endpoint:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(model.endpoint)
                                .font(.caption)
                                .textSelection(.enabled)
                        }
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                }
                .onAppear {
                    model.refreshStatus()
                }

                Divider()
                    .padding(.top)

                VStack(alignment: .leading, spacing: 10) {
                    Text("About")
                        .font(.headline)

                    Text("Swift Lambda Sample - MacApp")
                        .font(.body)

                    Text("This application connects to either a remote AWS Lambda API Gateway or a local Lambda instance for managing users and testing S3 file operations.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 20)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    var buildSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Build")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

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

            BuildOutputView(buildState: model.mode.buildState)
        }
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
    return SettingsView()
        .environment(model)
}
