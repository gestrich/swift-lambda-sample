import SwiftUI

struct ContentView: View {
    @Environment(APIConfiguration.self) var config

    var body: some View {
        TabView {
            // Only show Client tab if configured
            if config.isConfigured {
                ClientView()
                    .tabItem {
                        Label("Client", systemImage: "network")
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
