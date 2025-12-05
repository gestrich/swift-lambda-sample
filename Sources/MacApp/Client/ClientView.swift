import Client
import SwiftUI

struct ClientView: View {
    @Environment(APIClient.self) var apiClient

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Show which service we're connected to
                Text("Connected to: \(apiClient.baseURL)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                // S3 Section
                GroupBox {
                    S3View()
                } label: {
                    Label("S3", systemImage: "externaldrive.fill")
                        .font(.headline)
                }

                // PostgreSQL Section
                GroupBox {
                    PostgresView()
                } label: {
                    Label("PostgreSQL", systemImage: "cylinder.fill")
                        .font(.headline)
                }
            }
            .padding()
        }
    }
}

#Preview {
    ClientView()
}
