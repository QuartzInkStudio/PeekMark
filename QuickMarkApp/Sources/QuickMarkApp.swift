import SwiftUI

@main
struct QuickMarkApp: App {
    @StateObject private var updater = UpdaterController()

    var body: some Scene {
        // Main window (shown on first launch or from menu bar "Open QuickMark")
        WindowGroup {
            ContentView()
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 480, height: 300)

        // Menu bar extra
        MenuBarExtra("QuickMark", systemImage: "doc.text.magnifyingglass") {
            MenuBarView(updater: updater)
        }
        .menuBarExtraStyle(.menu)

        // Settings window (Cmd+,)
        Settings {
            SettingsView()
        }
    }
}
