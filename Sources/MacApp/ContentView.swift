import SwiftUI

struct ContentView: View {
    @Environment(MacAppModel.self) var model

    var body: some View {
        TabView {
            // Deploy is always available
            DeployView()
                .tabItem {
                    Label("Deploy", systemImage: "shippingbox")
                }

            // Only show Client tab if configured
            if model.isConfigured {
                ClientView()
                    .tabItem {
                        Label("Client", systemImage: "network")
                    }
            }
        }
    }
}

#Preview {
    let model = MacAppModel()
    return ContentView()
        .environment(model)
}
