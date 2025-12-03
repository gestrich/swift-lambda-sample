import SwiftUI

struct ClientView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
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
