import SwiftUI
import AppKit
import QuickMarkCore

struct MenuBarView: View {
    let updater: UpdaterController

    var body: some View {
        Button("New Document") {
            MarkdownPreviewWindowController.shared.showNewDocument()
        }
        .keyboardShortcut("n")

        Divider()

        Button("Open Markdown…") {
            openFilePicker()
        }
        .keyboardShortcut("o")

        Divider()

        Button("Settings…") {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            NSApp.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut(",")

        Button("About QuickMark") {
            NSApp.orderFrontStandardAboutPanel(nil)
            NSApp.activate(ignoringOtherApps: true)
        }

        Button("Check for Updates…") {
            updater.checkForUpdates()
        }
        .disabled(!updater.canCheckForUpdates)

        Divider()

        Button("Quit QuickMark") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.title = "Open Markdown File"
        panel.allowedContentTypes = [
            .init(filenameExtension: "md")!,
            .init(filenameExtension: "markdown")!
        ]
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            MarkdownPreviewWindowController.shared.show(url: url)
        }
    }
}
