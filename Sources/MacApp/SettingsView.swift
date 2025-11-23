import Client
import SwiftUI
import SwiftDeploy

struct SettingsView: View {
    @Environment(APIConfiguration.self) var config
    @State private var editedMode: ConnectionMode = .remote
    @State private var showingSuccess = false

    var body: some View {
        VStack(spacing: 20) {
            Text("Settings")
                .font(.title)
                .padding(.top)

            Divider()

            VStack(alignment: .leading, spacing: 15) {
                Text("API Configuration")
                    .font(.headline)

                // Mode Toggle
                VStack(alignment: .leading, spacing: 5) {
                    Text("Lambda Mode")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Picker("Mode", selection: $editedMode) {
                        Text("Remote (API Gateway)").tag(ConnectionMode.remote)
                        Text("Local Lambda").tag(ConnectionMode.local)
                    }
                    .pickerStyle(.segmented)
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

                // Local Lambda Endpoint (shown when in local mode)
                if editedMode == .local {
                    let localService = LocalDevelopmentService(workingDirectory: FileManager.default.currentDirectoryPath)

                    VStack(alignment: .leading, spacing: 5) {
                        Text("Local Lambda Endpoint")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        TextField("Local endpoint", text: .constant(localService.localEndpoint))
                            .textFieldStyle(.roundedBorder)
                            .disabled(true)

                        Text("Local endpoint is configured in LocalDevelopmentService - make sure local Lambda is running on port \(localService.port)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
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
                            Text(config.mode == .local ? "Local Lambda" : "Remote (API Gateway)")
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
                        if config.mode == .remote {
                            if let remoteURL = config.remoteURL {
                                HStack {
                                    Text("Remote URL:")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(remoteURL)
                                        .font(.caption)
                                        .textSelection(.enabled)
                                }
                            }
                        } else {
                            let localService = LocalDevelopmentService(workingDirectory: FileManager.default.currentDirectoryPath)

                            HStack {
                                Text("Local Endpoint:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(localService.localEndpoint)
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
}

#Preview {
    let config = APIConfiguration()
    return SettingsView()
        .environment(config)
}
