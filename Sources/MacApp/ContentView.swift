import SwiftUI

struct ContentView: View {
    @Environment(MacAppModel.self) var model

    var body: some View {
        TabView {
            // Only show Client tab if configured
            if model.isConfigured {
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
    let model = MacAppModel()
    return ContentView()
        .environment(model)
}
