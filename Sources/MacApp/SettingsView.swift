import Client
import SwiftUI
import SwiftDeploy

struct SettingsView: View {
    @Environment(APIConfiguration.self) var config
    @State private var serviceStatus = DeploymentStatus(lambdaState: .stopped, s3State: .stopped, postgresState: .stopped)
    @State private var isLoadingStatus = false

    var body: some View {
        @Bindable var config = config

        VStack(spacing: 20) {
            Text("Settings")
                .font(.title)
                .padding(.top)

            Divider()

            VStack(alignment: .leading, spacing: 15) {
                Text("API Configuration")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 5) {
                    Text("Lambda Mode")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Picker("Mode", selection: $config.mode) {
                        Text("Remote").tag(ConnectionMode.remote)
                        Text("Local Xcode").tag(ConnectionMode.localXcode)
                        Text("Local Linux").tag(ConnectionMode.localLinux)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: config.mode) { _, newMode in
                        onModeChanged(newMode)
                    }

                    Text(config.mode.detailText)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                // Remote API Gateway URL (shown when in remote mode)
                if config.mode == .remote {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("API Gateway URL")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack {
                            TextField("Fetched from CDK", text: .constant(config.remoteURL ?? "Not fetched yet"))
                                .textFieldStyle(.roundedBorder)
                                .disabled(true)

                            Button(config.isLoadingRemoteURL ? "Fetching..." : "Fetch from CDK") {
                                Task {
                                    await config.fetchRemoteURLFromCDK()
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(config.isLoadingRemoteURL)
                        }

                        Text("URL is automatically fetched from deployed CDK stack")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                // Lambda endpoint info (shown for local modes)
                if config.mode != .remote, let service = createService(for: config.mode) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Local Lambda Endpoint")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        TextField("Local endpoint", text: .constant(service.endpoint))
                            .textFieldStyle(.roundedBorder)
                            .disabled(true)

                        Text("Make sure local Lambda is running on port \(service.port)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                // Service Status Section (shown for all modes)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Service Status")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Spacer()

                        Button(action: { refreshStatus(for: config.mode) }) {
                            if isLoadingStatus {
                                ProgressView()
                                    .scaleEffect(0.7)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                        }
                        .buttonStyle(.borderless)
                        .disabled(isLoadingStatus)
                    }

                    HStack(spacing: 20) {
                        StatusIndicator(label: "Lambda", state: serviceStatus.lambdaState)
                        StatusIndicator(label: "S3", state: serviceStatus.s3State)
                        StatusIndicator(label: "PostgreSQL", state: serviceStatus.postgresState)
                    }
                    .padding(.vertical, 4)
                }

                Button("Reset All to Defaults") {
                    resetAllSettings()
                }
                .buttonStyle(.bordered)

                Divider()
                    .padding(.top)

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
                        if let service = createService(for: config.mode) {
                            HStack {
                                Text("Endpoint:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(service.endpoint)
                                    .font(.caption)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                }
                .onAppear {
                    refreshStatus(for: config.mode)
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

    private func onModeChanged(_ newMode: ConnectionMode) {
        // Auto-save when mode changes
        config.save()
        // Auto-refresh status for the new mode
        refreshStatus(for: newMode)
    }

    private func resetAllSettings() {
        config.clear()
        refreshStatus(for: config.mode)
    }

    /// Create a service for a specific mode
    private func createService(for mode: ConnectionMode) -> (any LambdaService)? {
        let workingDir = FileManager.default.currentDirectoryPath

        switch mode {
        case .localXcode:
            return XcodeLocalService(workingDirectory: workingDir)
        case .localLinux:
            return LinuxLocalService(workingDirectory: workingDir)
        case .remote:
            // Load AWS config for remote service
            guard let awsConfig = AWSAuthConfiguration.loadConfig() else {
                print("Warning: No AWS config found for remote service")
                return nil
            }
            return RemoteService(projectRoot: workingDir, awsConfig: awsConfig)
        }
    }

    /// Refresh the status of services
    private func refreshStatus(for mode: ConnectionMode) {
        guard let service = createService(for: mode) else {
            return
        }

        isLoadingStatus = true
        Task {
            do {
                let status = try await service.status()
                await MainActor.run {
                    self.serviceStatus = status
                    self.isLoadingStatus = false
                }
            } catch {
                await MainActor.run {
                    // On error, show all stopped
                    self.serviceStatus = DeploymentStatus(lambdaState: .stopped, s3State: .stopped, postgresState: .stopped)
                    self.isLoadingStatus = false
                }
            }
        }
    }
}

// MARK: - Status Indicator View

private struct StatusIndicator: View {
    let label: String
    let state: ServiceState

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(state == .running ? Color.green : Color.gray)
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
