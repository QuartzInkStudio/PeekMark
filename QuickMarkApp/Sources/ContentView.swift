import AppKit
import SwiftUI

/// A real file for the Finder exercise. Existing user edits are preserved.
enum PeekMarkSample {
    static func sampleURL() throws -> URL {
        let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("PeekMark/Samples", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("Release notes.md")
        if !FileManager.default.fileExists(atPath: url.path) {
            try markdown.write(to: url, atomically: true, encoding: .utf8)
        }
        return url
    }

    private static let markdown = """
    # Release notes

    A clearer path from draft to delivery.

    ## What changed

    A small set of improvements for the way we work.

    ### The release flow

    ```mermaid
    flowchart LR
        Draft --> Review --> Ship
    ```

    ### At a glance

    | Area | Update |
    | --- | --- |
    | Reading | A quieter workspace |
    | Sharing | More polished handoffs |

    ## Next steps

    Share your notes and keep the conversation moving.
    """
}

private func pmColor(_ role: PeekMarkAppearance.Role) -> Color {
    Color(nsColor: PeekMarkAppearance.color(role))
}
private func display(_ size: CGFloat) -> Font {
    Font(PeekMarkAppearance.displayFont(size: size))
}
private func mono(_ size: CGFloat) -> Font {
    Font(PeekMarkAppearance.monoFont(size: size))
}

struct ContentView: View {
    @ObservedObject private var navigation = PeekMarkWelcomeNavigation.shared
    @State private var showingHelp: Bool = {
        #if DEBUG
        return ProcessInfo.processInfo.environment["PEEKMARK_QA_SCREEN"] == "help"
        #else
        return false
        #endif
    }()
    @State private var sampleError: String?

    var body: some View {
        VStack(spacing: 0) {
            Text(showingHelp ? "Quick Look help" : "PeekMark")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(pmColor(.ink))
                .frame(maxWidth: .infinity)
                .frame(height: 53)
                .accessibilityAddTraits(.isHeader)
            Rectangle().fill(pmColor(.line)).frame(height: 1)
            GeometryReader { geometry in
                ScrollView([.vertical, .horizontal]) {
                    let wide = geometry.size.width >= 960
                    Group {
                        if wide {
                            HStack(alignment: .top, spacing: 54) {
                                introduction
                                    .frame(width: 390, alignment: .leading)
                                panel
                                    .frame(maxWidth: .infinity, alignment: .topLeading)
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 36) {
                                introduction
                                panel
                            }
                        }
                    }
                    .padding(.horizontal, wide ? 68 : 32)
                    .padding(.top, 37)
                    .padding(.bottom, 48)
                    .frame(minWidth: geometry.size.width, minHeight: geometry.size.height, alignment: .topLeading)
                }
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .background(pmColor(.shell))
        .navigationTitle(showingHelp ? "Quick Look help" : "PeekMark")
        .onChange(of: navigation.helpRequested, initial: true) { _, requested in
            guard requested else { return }
            showingHelp = true
            navigation.helpRequested = false
        }
        .alert("Couldn’t show the sample", isPresented: Binding(get: { sampleError != nil }, set: { if !$0 { sampleError = nil } })) {
            Button("OK", role: .cancel) { sampleError = nil }
        } message: {
            Text(sampleError ?? "")
        }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(showingHelp ? "PEEKMARK   /   HELP" : "PEEKMARK   /   1.1")
                .font(mono(12)).foregroundStyle(pmColor(.blue))
                .padding(.top, 7)
            Text(showingHelp ? "Let’s get the\npreview working." : "Markdown,\nright in Finder.")
                .font(display(showingHelp ? 60 : 62))
                .lineSpacing(-4)
                .foregroundStyle(pmColor(.ink))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 29)
            if showingHelp {
                Text("If the sample didn’t preview as expected,\ntry these steps, or open a file directly.")
                    .font(.system(size: 16)).lineSpacing(5)
                    .foregroundStyle(pmColor(.ink)).fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 18)
                actions.padding(.top, 62)
                rule.padding(.top, 70)
                Text("STILL NEED A HAND?").font(mono(11)).foregroundStyle(pmColor(.blue)).padding(.top, 24)
                Link(destination: URL(string: "mailto:hello@quartz.ink?subject=PeekMark%20support")!) {
                    Text("Contact support →").font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(pmColor(.blue)).padding(.top, 16)
                Button("← Back to welcome") { showingHelp = false }
                    .buttonStyle(.plain).foregroundStyle(pmColor(.blue))
                    .font(.system(size: 13, weight: .semibold)).padding(.top, 24)
            } else {
                Text("See diagrams, math and tables in place.")
                    .font(.system(size: 18)).foregroundStyle(pmColor(.ink)).padding(.top, 17)
                Text("Select a file in Finder, then press Space.")
                    .font(.system(size: 15)).foregroundStyle(pmColor(.muted)).padding(.top, 8)
                rule.padding(.top, 27)
                Text("TRY IT IN FINDER").font(mono(11)).foregroundStyle(pmColor(.blue)).padding(.top, 24)
                Text("We’ll select a sample in Finder.\nPress Space to preview it.")
                    .font(.system(size: 15)).lineSpacing(5).foregroundStyle(pmColor(.ink)).padding(.top, 16)
                actions.padding(.top, 30)
                Button("Quick Look not working? Get help →") { showingHelp = true }
                    .buttonStyle(.plain).foregroundStyle(pmColor(.blue))
                    .font(.system(size: 13, weight: .semibold)).padding(.top, 40)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var rule: some View { Rectangle().fill(pmColor(.line)).frame(height: 1) }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 13) {
            Button(action: revealSample) {
                Label("Show sample in Finder", systemImage: "arrow.up.right")
                    .frame(width: 230, height: 46)
                    .background(pmColor(.blue), in: RoundedRectangle(cornerRadius: 6))
                    .foregroundStyle(pmColor(.accentText))
            }
            .accessibilityHint("Selects the sample file in Finder, where you can press Space to preview it.")
            Button {
                MarkdownPreviewWindowController.shared.openMarkdownDocument(closing: NSApp.keyWindow)
            } label: {
                Label("Open Markdown…", systemImage: "folder")
                    .frame(width: 230, height: 42)
                    .background(pmColor(.paper), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(pmColor(.line), lineWidth: 1))
                    .foregroundStyle(pmColor(.ink))
            }
            .keyboardShortcut("o", modifiers: .command)
        }
        .font(.system(size: 13, weight: .semibold))
        .buttonStyle(.plain)
    }

    private func revealSample() {
        do { NSWorkspace.shared.activateFileViewerSelecting([try PeekMarkSample.sampleURL()]) }
        catch { sampleError = error.localizedDescription }
    }

    @ViewBuilder private var panel: some View {
        if showingHelp { HelpPanel() } else { DemoPanel() }
    }
}

private struct HelpPanel: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("QUICK LOOK CHECK").font(mono(11)).foregroundStyle(pmColor(.blue))
            Text("A few things to try").font(display(34)).foregroundStyle(pmColor(.ink)).padding(.top, 19)
            Rectangle().fill(pmColor(.line)).frame(height: 1).padding(.top, 20)
            step("01", "Select the sample in Finder", "Choose Release notes.md and press Space.", key: true)
            divider
            step("02", "Check Quick Look extensions", "In System Settings, search for Extensions.\nMake sure PeekMark is enabled for Quick Look.")
            divider
            step("03", "Try the sample again", "Return to Finder and press Space on the file.")
            HStack(spacing: 13) {
                Image(systemName: "info.circle").foregroundStyle(pmColor(.blue))
                Text("You can use Open Markdown while you sort this out.")
                    .font(.system(size: 13)).foregroundStyle(pmColor(.ink))
            }
            .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
            .padding(.horizontal, 18).background(pmColor(.soft), in: RoundedRectangle(cornerRadius: 6))
            .padding(.top, 24)
        }
        .padding(40)
        .frame(maxWidth: .infinity, minHeight: 582, alignment: .topLeading)
        .background(pmColor(.paper), in: RoundedRectangle(cornerRadius: 10))
    }
    private var divider: some View { Rectangle().fill(pmColor(.line)).frame(height: 1).padding(.leading, 57) }
    private func step(_ number: String, _ title: String, _ detail: String, key: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 28) {
            Text(number).font(mono(13)).foregroundStyle(pmColor(.blue)).frame(width: 29, alignment: .leading)
            VStack(alignment: .leading, spacing: 9) {
                Text(title).font(.system(size: 17, weight: .semibold)).foregroundStyle(pmColor(.ink))
                Text(detail).font(.system(size: 14)).lineSpacing(5).foregroundStyle(pmColor(.muted))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if key { Text("SPACE").font(mono(11)).foregroundStyle(pmColor(.ink)).frame(width: 99, height: 34).background(pmColor(.soft), in: RoundedRectangle(cornerRadius: 6)).accessibilityHidden(true) }
        }
        .padding(.vertical, 25)
    }
}

private struct DemoPanel: View {
    var body: some View {
        GeometryReader { geometry in
            let scale = min(geometry.size.width / 700, 1)
            demo
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: 700 * scale, height: 628 * scale, alignment: .topLeading)
        }
        .frame(height: 628)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Illustration of Release notes selected in Finder and its Quick Look preview")
    }
    private var demo: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 12).fill(pmColor(.rail))
            VStack(alignment: .leading, spacing: 14) {
                Text("FINDER QUICK LOOK").font(mono(11)).foregroundStyle(pmColor(.blue))
                Text("Release notes.md").font(display(24)).foregroundStyle(pmColor(.ink))
            }.offset(x: 36, y: 30)
            finder.offset(x: 36, y: 117)
            paper.offset(x: 311, y: 167)
            Text("SPACE").font(mono(11)).foregroundStyle(pmColor(.ink))
                .frame(width: 101, height: 35).background(pmColor(.paper), in: RoundedRectangle(cornerRadius: 6)).offset(x: 173, y: 530)
        }
        .frame(width: 700, height: 628)
    }
    private var finder: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                pmColor(.rail)
                Text("Samples").font(.system(size: 13, weight: .semibold)).foregroundStyle(pmColor(.ink))
                HStack(spacing: 6) {
                    ForEach([Color(red: 1, green: 0.37, blue: 0.34), Color(red: 1, green: 0.74, blue: 0.18), Color(red: 0.16, green: 0.78, blue: 0.25)], id: \.self) { color in Circle().fill(color).frame(width: 9, height: 9) }
                    Spacer()
                }.padding(.leading, 16)
            }.frame(height: 48)
            Text("NAME").font(mono(10)).foregroundStyle(pmColor(.muted)).padding(.leading, 22).padding(.top, 18)
            Rectangle().fill(pmColor(.line)).frame(height: 1).padding(.horizontal, 14).padding(.top, 9)
            fileRow("Release notes.md", selected: true).padding(.top, 10)
            fileRow("Project brief.md")
            fileRow("Reading list.md")
            Spacer()
            Text("1 item selected").font(.system(size: 11)).foregroundStyle(pmColor(.muted)).padding(.leading, 22).padding(.bottom, 18)
        }
        .frame(width: 333, height: 377)
        .background(pmColor(.paper), in: RoundedRectangle(cornerRadius: 9))
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(pmColor(.line), lineWidth: 1))
    }
    private func fileRow(_ title: String, selected: Bool = false) -> some View {
        HStack(spacing: 9) {
            Image(systemName: "doc.text")
            Text(title).fontWeight(selected ? .semibold : .regular)
            Spacer()
        }
        .font(.system(size: 13)).foregroundStyle(selected ? pmColor(.accentText) : pmColor(.ink))
        .padding(.horizontal, 12).frame(height: 38)
        .background(selected ? pmColor(.blue) : .clear, in: RoundedRectangle(cornerRadius: 5))
        .padding(.horizontal, 12).padding(.bottom, 9)
    }
    private var paper: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("PEEKMARK  /  PRODUCT NOTES").font(mono(10)).foregroundStyle(pmColor(.blue))
            Text("Release notes").font(display(37)).foregroundStyle(pmColor(.ink)).padding(.top, 21)
            Rectangle().fill(pmColor(.line)).frame(height: 1).padding(.top, 45)
            Text("What changed").font(.system(size: 14, weight: .semibold)).foregroundStyle(pmColor(.ink)).padding(.top, 22)
            Text("A clearer path from draft to delivery.").font(.system(size: 13)).foregroundStyle(pmColor(.ink)).padding(.top, 15)
            Text("Draft → Review → Ship").font(.system(size: 13)).foregroundStyle(pmColor(.muted)).padding(.top, 7)
            Spacer()
            Rectangle().fill(pmColor(.line)).frame(height: 1)
            Text("PEEKMARK  /  SAMPLE").font(mono(10)).foregroundStyle(pmColor(.blue)).padding(.top, 18)
        }
        .padding(.horizontal, 28).padding(.vertical, 26)
        .frame(width: 334, height: 392, alignment: .topLeading)
        .background(pmColor(.paper), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(pmColor(.line), lineWidth: 1))
    }
}
