import AppKit
import SwiftUI

@main
struct MacAppMain: App {
    @State private var model = AllServicesModel()

    init() {
        // Set activation policy to make app appear in Dock and Cmd+Tab
        NSApplication.shared.setActivationPolicy(.regular)
        // Activate the app to bring it to foreground
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .environment(model.apiClient)
                .onAppear {
                    model.refreshStatus()
                }
        }
        .defaultSize(width: 700, height: 600)
    }
}
