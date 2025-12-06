import SwiftUI

struct ContentView: View {
    @Environment(AllServicesModel.self) var model

    var body: some View {
        ServicesView()
    }
}

#Preview {
    let model = AllServicesModel()
    return ContentView()
        .environment(model)
}
