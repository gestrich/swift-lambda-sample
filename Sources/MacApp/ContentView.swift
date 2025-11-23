import Client
import SwiftUI

struct ContentView: View {
    @State private var config: APIConfiguration
    @State private var apiClient: APIClient?

    init(config: APIConfiguration) {
        _config = State(initialValue: config)
        _apiClient = State(initialValue: config.createAPIClient())
    }

    var body: some View {
        TabView {
            // Only show Files and Users tabs if configured
            if let apiClient = apiClient {
                FileView()
                    .tabItem {
                        Label("Files", systemImage: "doc.fill")
                    }
                    .environment(apiClient)

                UserListView()
                    .tabItem {
                        Label("Users", systemImage: "person.3.fill")
                    }
                    .environment(apiClient)
            }

            // Settings is always available
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .environment(config)
        }
        .onAppear(perform: {
            self.apiClient = config.createAPIClient()
        })
        .onChange(of: config.mode) { _, _ in
            apiClient = config.createAPIClient()
        }
        .onChange(of: config.remoteURL) { _, _ in
            if config.mode == .remote {
                apiClient = config.createAPIClient()
            }
        }
        .onChange(of: config.localEndpoint) { _, _ in
            if config.mode == .local {
                apiClient = config.createAPIClient()
            }
        }
    }
}

#Preview {
    let config = APIConfiguration()
    return ContentView(config: config)
}
