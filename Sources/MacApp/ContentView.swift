import SwiftUI

struct ContentView: View {
    @Environment(APIConfiguration.self) var config

    var body: some View {
        TabView {
            // Only show Files and Users tabs if configured
            if config.isConfigured {
                FileView()
                    .tabItem {
                        Label("Files", systemImage: "doc.fill")
                    }

                UserListView()
                    .tabItem {
                        Label("Users", systemImage: "person.3.fill")
                    }
            }

            // Settings is always available
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
    }
}

#Preview {
    let config = APIConfiguration()
    return ContentView()
        .environment(config)
}
