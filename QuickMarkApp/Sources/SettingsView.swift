import SwiftUI
import AppKit

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gear") }
            AboutView()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 420, height: 280)
        .padding()
    }
}

private struct GeneralSettingsView: View {
    var body: some View {
        Form {
            Section("Quick Look Extension") {
                Text("The QuickMark Quick Look extension is active.\nSelect a .md file in Finder and press Space to preview.")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }
            Section("Pro Features") {
                Text("Custom themes, Mermaid diagrams, and PDF export are available in QuickMark Pro.")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
                Button("Learn More…") {
                    NSWorkspace.shared.open(URL(string: "https://quickmark.app")!)
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct AboutView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("QuickMark")
                .font(.title2.bold())
            Text("Version 0.1.0 (Community)")
                .foregroundStyle(.secondary)
            Text("AGPL-3.0 Open Source")
                .foregroundStyle(.secondary)
                .font(.caption)
            Link("github.com/yourname/quickmark",
                 destination: URL(string: "https://github.com/yourname/quickmark")!)
                .font(.caption)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
