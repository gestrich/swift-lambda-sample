import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) var model

    var body: some View {
        ServicesView()
    }
}

#Preview {
    let model = AppModel()
    return ContentView()
        .environment(model)
}
