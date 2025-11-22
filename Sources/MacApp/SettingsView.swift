import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var apiClient: APIClient
    @State private var editedURL: String = ""
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

                VStack(alignment: .leading, spacing: 5) {
                    Text("API Gateway URL")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    TextField("https://api.example.com/prod", text: $editedURL)
                        .textFieldStyle(.roundedBorder)
                        .onAppear {
                            editedURL = apiClient.baseURL
                        }
                }

                HStack {
                    Button("Reset to Default") {
                        editedURL = "https://5kawxqr7e4.execute-api.us-east-1.amazonaws.com/prod"
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button("Save") {
                        saveSettings()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(editedURL == apiClient.baseURL)
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
                            Text("Base URL:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(apiClient.baseURL)
                                .font(.caption)
                                .textSelection(.enabled)
                        }
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                }

                Divider()
                    .padding(.top)

                VStack(alignment: .leading, spacing: 10) {
                    Text("About")
                        .font(.headline)

                    Text("Swift Lambda Sample - MacApp")
                        .font(.body)

                    Text("This application connects to the AWS Lambda API Gateway for managing users and testing S3 file operations.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 20)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func saveSettings() {
        apiClient.baseURL = editedURL
        showingSuccess = true

        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            showingSuccess = false
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(APIClient.shared)
}
