import SwiftUI

struct ContentView: View {
    @StateObject private var apiClient = APIClient.shared

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
        .environmentObject(apiClient)
    }
}

#Preview {
    ContentView()
}
