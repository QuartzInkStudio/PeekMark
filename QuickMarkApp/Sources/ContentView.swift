import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text("QuickMark")
                .font(.title.bold())
            Text("Markdown Quick Look extension is active.\nSelect a .md file in Finder and press Space to preview.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Divider()
            HStack(spacing: 16) {
                Button("Open Markdown…") {
                    openMarkdownFile()
                }
                Button("Settings…") {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                }
            }
        }
        .padding(40)
        .frame(minWidth: 400, minHeight: 280)
    }

    private func openMarkdownFile() {
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
