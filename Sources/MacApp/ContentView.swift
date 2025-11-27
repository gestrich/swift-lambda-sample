import Client
import SwiftDeploy
import SwiftUI

struct ContentView: View {
    @State private var config: APIConfiguration
    @State private var apiClient: APIClient?

    init(config: APIConfiguration) {
        _config = State(initialValue: config)
        _apiClient = State(initialValue: Self.createAPIClient(for: config))
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
            self.apiClient = Self.createAPIClient(for: config)
        })
        .onChange(of: config.mode) { _, _ in
            apiClient = Self.createAPIClient(for: config)
        }
        .onChange(of: config.remoteURL) { _, _ in
            if config.mode == .remote {
                apiClient = Self.createAPIClient(for: config)
            }
        }
    }

    /// Create an API client based on the current configuration
    private static func createAPIClient(for config: APIConfiguration) -> APIClient? {
        let workingDir = FileManager.default.currentDirectoryPath

        switch config.mode {
        case .localXcode:
            let service = XcodeLocalService(workingDirectory: workingDir)
            return APIClient(localPort: service.port)
        case .localLinux:
            let service = LinuxLocalService(workingDirectory: workingDir)
            return APIClient(localPort: service.port)
        case .remote:
            guard let url = config.remoteURL else { return nil }
            return APIClient(baseURL: url)
        }
    }
}

#Preview {
    let config = APIConfiguration()
    return ContentView(config: config)
}
