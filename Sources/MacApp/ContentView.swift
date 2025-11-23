import Client
import SwiftUI

struct ContentView: View {
    @State private var apiClient = APIClient.shared

    var body: some View {
        TabView {
            FileView()
                .tabItem {
                    Label("Files", systemImage: "doc.fill")
                }

            UserListView()
                .tabItem {
                    Label("Users", systemImage: "person.3.fill")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
        .environment(apiClient)
    }
}

#Preview {
    ContentView()
}
