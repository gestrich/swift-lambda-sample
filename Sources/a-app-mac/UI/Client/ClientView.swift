import d_sdk_client
import SwiftUI

struct ClientView: View {
    var apiClient: APIClient

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Show which service we're connected to
                Text("Connected to: \(apiClient.baseURL)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                // S3 Section
                GroupBox {
                    S3View(apiClient: apiClient)
                } label: {
                    Label("Files (S3)", systemImage: "externaldrive.fill")
                        .font(.headline)
                }

                // DynamoDB Reminders Section
                GroupBox {
                    RemindersView(apiClient: apiClient)
                } label: {
                    Label("Reminders (DynamoDB)", systemImage: "bell.fill")
                        .font(.headline)
                }

                // PostgreSQL Section
                GroupBox {
                    PostgresView(apiClient: apiClient)
                } label: {
                    Label("Users (PostgreSQL)", systemImage: "cylinder.fill")
                        .font(.headline)
                }
            }
            .padding()
        }.id(apiClient.baseURL) // To rebuild view when client changes
    }
}

#Preview {
    ClientView(apiClient: .preview)
}
