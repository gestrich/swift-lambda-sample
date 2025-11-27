import Client
import SwiftUI
import SwiftDeploy

struct SettingsView: View {
    @Environment(APIConfiguration.self) var config
    @State private var editedMode: ConnectionMode = .remote
    @State private var showingSuccess = false
    @State private var serviceStatus: LocalServiceStatus?
    @State private var isLoadingStatus = false

    var body: some View {
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

                    Picker("Mode", selection: $editedMode) {
                        Text("Remote").tag(ConnectionMode.remote)
                        Text("Local Xcode").tag(ConnectionMode.localXcode)
                        Text("Local Linux").tag(ConnectionMode.localLinux)
                    }
                    .pickerStyle(.segmented)

                    Text(modeDescription)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                // Remote API Gateway URL (shown when in remote mode)
                if editedMode == .remote {
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

                // Local Lambda info (shown when in local mode)
                if let localService = createLocalService(for: editedMode) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Local Lambda Endpoint")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        TextField("Local endpoint", text: .constant(localService.localEndpoint))
                            .textFieldStyle(.roundedBorder)
                            .disabled(true)

                        Text("Make sure local Lambda is running on port \(localService.port)")
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

                            Button(action: { refreshStatus() }) {
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

                        if let status = serviceStatus {
                            HStack(spacing: 20) {
                                StatusIndicator(label: "Lambda", state: status.lambdaState)
                                StatusIndicator(label: "MinIO", state: status.minioState)
                                StatusIndicator(label: "PostgreSQL", state: status.postgresState)
                            }
                            .padding(.vertical, 4)
                        } else {
                            Text("Click refresh to check status")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                HStack {
                    Button("Reset All to Defaults") {
                        resetAllSettings()
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button("Save") {
                        saveSettings()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!hasChanges())
                }

                if showingSuccess {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Settings saved successfully")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                    .transition(.opacity)
                }

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
                        if let localService = createLocalService(for: config.mode) {
                            HStack {
                                Text("Local Endpoint:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(localService.localEndpoint)
                                    .font(.caption)
                                    .textSelection(.enabled)
                            }
                        } else if let remoteURL = config.remoteURL {
                            HStack {
                                Text("Remote URL:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(remoteURL)
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
                    loadCurrentSettings()
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

    private var modeDescription: String {
        switch editedMode {
        case .remote:
            return "Connect to deployed AWS API Gateway"
        case .localXcode:
            return "Native macOS build - fast iteration, best for development"
        case .localLinux:
            return "Docker container build - matches AWS Lambda environment"
        }
    }

    private func loadCurrentSettings() {
        editedMode = config.mode
    }

    private func hasChanges() -> Bool {
        return editedMode != config.mode
    }

    private func saveSettings() {
        config.mode = editedMode
        config.save()

        showingSuccess = true

        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            showingSuccess = false
        }
    }

    private func resetAllSettings() {
        config.clear()
        loadCurrentSettings()
        showingSuccess = true

        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            showingSuccess = false
        }
    }

    /// Create a local service for a specific mode (nil if remote mode)
    private func createLocalService(for mode: ConnectionMode) -> (any LocalDeploymentService)? {
        let workingDir = FileManager.default.currentDirectoryPath

        switch mode {
        case .localXcode:
            return XcodeLocalService(workingDirectory: workingDir)
        case .localLinux:
            return LinuxLocalService(workingDirectory: workingDir)
        case .remote:
            return nil
        }
    }

    /// Refresh the status of local services
    private func refreshStatus() {
        guard let service = createLocalService(for: editedMode) else {
            serviceStatus = nil
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
                    self.serviceStatus = nil
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
