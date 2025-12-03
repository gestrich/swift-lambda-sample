import SwiftUI

struct ContentView: View {
    @Environment(AllServicesModel.self) var model

    var body: some View {
        TabView {
            // Services tab (Remote/Local selection)
            ServicesView()
                .tabItem {
                    Label("Services", systemImage: "shippingbox")
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
    let model = AllServicesModel()
    return ContentView()
        .environment(model)
}
