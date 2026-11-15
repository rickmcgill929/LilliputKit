import SwiftUI
import AppKit

@main
struct MonitorControlApp: App {
    init() {
        // Lets `swift run MonitorControl` come to the front like a normal app.
        NSApplication.shared.setActivationPolicy(.regular)
        DispatchQueue.main.async { NSApplication.shared.activate(ignoringOtherApps: true) }
    }

    var body: some Scene {
        WindowGroup("Monitor Control") {
            ContentView()
        }
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
