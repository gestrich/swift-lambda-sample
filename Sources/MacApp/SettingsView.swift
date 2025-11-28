import Client
import SwiftUI
import SwiftDeploy

struct SettingsView: View {
    @Environment(APIConfiguration.self) var config

    private var modeBinding: Binding<String> {
        Binding(
            get: { config.mode.persistenceKey },
            set: { key in
                switch key {
                case RemoteService.persistenceKey:
                    config.setRemote()
                case XcodeLocalService.persistenceKey:
                    config.setLocalXcode()
                case LinuxLocalService.persistenceKey:
                    config.setLocalLinux()
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

                    Text(config.mode.detailText)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                // Endpoint section
                VStack(alignment: .leading, spacing: 5) {
                    Text(config.endpointLabel)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    TextField("Endpoint", text: .constant(config.endpoint))
                        .textFieldStyle(.roundedBorder)
                        .disabled(true)

                    Text(config.endpointHelpText)
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
                                await config.startServices()
                            }
                        }) {
                            if config.status.lambdaState.isTransitioning {
                                ProgressView()
                                    .scaleEffect(0.7)
                            } else {
                                Image(systemName: "play.circle")
                            }
                        }
                        .buttonStyle(.borderless)
                        .disabled(config.status.lambdaState.isTransitioning)
                        .help("Start services")

                        Button(action: { config.refreshStatus() }) {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.borderless)
                        .disabled(config.status.lambdaState.isTransitioning)
                        .help("Refresh status")
                    }

                    HStack(spacing: 20) {
                        StatusIndicator(label: "Lambda", state: config.status.lambdaState)
                        StatusIndicator(label: "S3", state: config.status.s3State)
                        StatusIndicator(label: "PostgreSQL", state: config.status.postgresState)
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
                            Text(config.mode.displayName)
                                .font(.caption)
                                .textSelection(.enabled)
                        }
                        HStack {
                            Text("Configured:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(config.isConfigured ? "Yes" : "No")
                                .font(.caption)
                                .foregroundColor(config.isConfigured ? .green : .red)
                        }
                        HStack {
                            Text("Endpoint:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(config.endpoint)
                                .font(.caption)
                                .textSelection(.enabled)
                        }
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                }
                .onAppear {
                    config.refreshStatus()
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
                        try? await config.buildLambda(clean: false)
                    }
                }) {
                    if config.mode.buildState.status.isBuilding {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Image(systemName: "hammer")
                    }
                }
                .buttonStyle(.borderless)
                .disabled(config.mode.buildState.status.isBuilding)
                .help("Build Lambda")

                Button(action: {
                    Task {
                        try? await config.buildLambda(clean: true)
                    }
                }) {
                    Image(systemName: "sparkles")
                }
                .buttonStyle(.borderless)
                .disabled(config.mode.buildState.status.isBuilding)
                .help("Clean and Build Lambda")
            }

            BuildOutputView(buildState: config.mode.buildState)
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
    let config = APIConfiguration()
    return SettingsView()
        .environment(config)
}
