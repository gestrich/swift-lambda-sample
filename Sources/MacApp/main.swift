import AppKit
import SwiftUI

@main
struct MacAppMain: App {
    @State private var config = APIConfiguration()

    init() {
        // Set activation policy to make app appear in Dock and Cmd+Tab
        NSApplication.shared.setActivationPolicy(.regular)
        // Activate the app to bring it to foreground
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(config: config)
                .task {
                    // Fetch remote URL from CDK on app start
                    await config.fetchRemoteURLFromCDK()
                }
        }
        .defaultSize(width: 700, height: 600)
    }
}
