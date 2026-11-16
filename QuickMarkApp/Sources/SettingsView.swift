import SwiftUI
import AppKit

func settingsColor(_ role: PeekMarkAppearance.Role) -> Color {
    Color(nsColor: PeekMarkAppearance.color(role))
}

private enum SettingsPane: String, CaseIterable, Identifiable {
    case general = "General"
    case scratchpad = "Scratchpad"
    case preview = "Preview"
#if OFFICIAL_EXTENSIONS
    case pro = "Pro"
#endif
    case about = "About"

    var id: String { rawValue }
    var title: LocalizedStringKey {
        switch self {
        case .general: "General"
        case .scratchpad: "Scratchpad"
        case .preview: "Preview"
#if OFFICIAL_EXTENSIONS
        case .pro: "Pro"
#endif
        case .about: "About"
        }
    }
    var number: String {
        switch self {
        case .general: return "01"
        case .scratchpad: return "02"
        case .preview: return "03"
#if OFFICIAL_EXTENSIONS
        case .pro: return "04"
        case .about: return "05"
#else
        case .about: return "04"
#endif
        }
    }
}

private var settingsEdition: LocalizedStringKey {
#if APP_STORE
    return "MAC APP STORE"
#elseif OFFICIAL_EXTENSIONS
    return "DIRECT EDITION"
#else
    return "COMMUNITY"
#endif
}

struct SettingsView: View {
    @State private var selection: SettingsPane = .general

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(settingsColor(.line)).frame(width: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    switch selection {
                    case .general: GeneralSettingsView(number: selection.number)
                    case .scratchpad: ScratchpadSettingsView(number: selection.number)
                    case .preview: PreviewSettingsView(number: selection.number)
#if OFFICIAL_EXTENSIONS
                    case .pro: ProSettingsView(number: selection.number)
#endif
                    case .about: AboutView(number: selection.number)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 38)
                .padding(.top, 52)
                .padding(.bottom, 32)
            }
            .background(settingsColor(.shell))
        }
        .frame(width: 800, height: 588)
        .foregroundStyle(settingsColor(.ink))
        .navigationTitle("Settings")
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("PEEKMARK")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(settingsColor(.muted))
                .padding(.horizontal, 22)
                .padding(.top, 44)
                .padding(.bottom, 14)
            ForEach(SettingsPane.allCases) { pane in
                Button {
                    selection = pane
                } label: {
                    Text(pane.title)
                        .font(.system(size: 14))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .frame(height: 34)
                        .background(selection == pane ? settingsColor(.soft) : .clear, in: RoundedRectangle(cornerRadius: 7))
                        .foregroundStyle(selection == pane ? settingsColor(.blue) : settingsColor(.ink))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == pane ? .isSelected : [])
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
            Spacer()
        }
        .frame(width: 187)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(settingsColor(.rail))
    }
}

private struct SettingsHeading: View {
    let number: String
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(number) / PREFERENCES")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(settingsColor(.blue))
            Text(title)
                .font(Font(PeekMarkAppearance.displayFont(size: 34)))
                .padding(.top, 14)
            Text(subtitle)
                .font(.system(size: 14))
                .foregroundStyle(settingsColor(.muted))
                .padding(.top, 4)
            SettingsRule().padding(.top, 18)
        }
    }
}

struct SettingsRule: View {
    var body: some View { Rectangle().fill(settingsColor(.line)).frame(height: 1) }
}

private struct SettingsSectionLabel: View {
    let title: LocalizedStringKey
    var body: some View {
        Text(title)
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(settingsColor(.muted))
    }
}

struct SettingsButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14))
            .foregroundStyle(prominent ? Color.white : settingsColor(.ink))
            .padding(.horizontal, 13)
            .frame(height: 34)
            .background((prominent ? settingsColor(.blue) : Color(nsColor: .controlBackgroundColor)).opacity(configuration.isPressed ? 0.7 : 1), in: RoundedRectangle(cornerRadius: 7))
    }
}

private struct SettingsNote<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(settingsColor(.paper), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct GeneralSettingsView: View {
    let number: String
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsHeading(number: number, title: "General", subtitle: "A quieter home for your Markdown.")
            SettingsSectionLabel(title: "APPEARANCE").padding(.top, 27)
            HStack {
                Text("Appearance").font(.system(size: 15))
                Spacer()
                Text("System")
                    .font(.system(size: 13))
                    .foregroundStyle(settingsColor(.muted))
                    .frame(width: 192, height: 32, alignment: .leading)
                    .padding(.leading, 12)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
            }.padding(.top, 15)
            Text("Follows your Mac’s light or dark appearance.")
                .font(.system(size: 13)).foregroundStyle(settingsColor(.muted)).padding(.top, 6)
            SettingsRule().padding(.top, 28)
            SettingsSectionLabel(title: "QUICK LOOK").padding(.top, 27)
            Text("Preview in Finder").font(.system(size: 15)).padding(.top, 18)
            Text("Select a Markdown file in Finder and press Space.")
                .font(.system(size: 13)).foregroundStyle(settingsColor(.muted)).padding(.top, 6)
            Button("Troubleshoot Quick Look…") {
                PeekMarkWelcomeNavigation.showHelp()
                openWindow(id: "welcome")
            }
            .buttonStyle(SettingsButtonStyle())
            .padding(.top, 24)
#if !OFFICIAL_EXTENSIONS
            CommunityNote().padding(.top, 38)
#endif
        }
    }
}

private struct ScratchpadSettingsView: View {
    let number: String
    @AppStorage(QuickMarkSettings.scratchpadHotKeyEnabled) private var hotKeyEnabled = true
    @AppStorage(QuickMarkSettings.scratchpadHotKey) private var selectedHotKey = ScratchpadHotKeyOption.commandShiftM.rawValue
    @AppStorage("ScratchpadHotKeyRegistrationStatus") private var registrationStatus = "registered"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsHeading(number: number, title: "Scratchpad", subtitle: "Keep a blank page close at hand.")
            SettingsSectionLabel(title: "GLOBAL SHORTCUT").padding(.top, 27)
            Toggle("Enable Scratchpad shortcut", isOn: $hotKeyEnabled)
                .toggleStyle(.switch).font(.system(size: 15)).padding(.top, 18)
            Text("Open the existing Scratchpad or create one if needed.")
                .font(.system(size: 13)).foregroundStyle(settingsColor(.muted)).padding(.top, 8)
            SettingsRule().padding(.top, 24)
            Picker("Shortcut", selection: $selectedHotKey) {
                ForEach(ScratchpadHotKeyOption.allCases) { option in
                    Text(option.label).tag(option.rawValue)
                }
            }
            .disabled(!hotKeyEnabled)
            .font(.system(size: 15))
            .padding(.top, 20)
            HStack(spacing: 8) {
                Circle().fill(statusColor).frame(width: 9, height: 9).accessibilityHidden(true)
                Text(statusText).font(.system(size: 13)).foregroundStyle(statusColor)
            }.padding(.top, 24)
            Text("If unavailable, choose another shortcut.")
                .font(.system(size: 13)).foregroundStyle(settingsColor(.muted)).padding(.top, 10)
            Text("AVAILABLE:  ⌘ ⇧ M    ⌘ ⌥ M    ⌃ ⌥ M")
                .font(.system(size: 10, design: .monospaced)).foregroundStyle(settingsColor(.muted)).padding(.top, 34)
        }
    }

    private var statusText: LocalizedStringKey {
        if !hotKeyEnabled { return "Off" }
        if registrationStatus == "unavailable" { return "Unavailable" }
        return "Registered"
    }
    private var statusColor: Color {
        if !hotKeyEnabled { return settingsColor(.muted) }
        return registrationStatus == "unavailable" ? .red : settingsColor(.status)
    }
}

private struct PreviewSettingsView: View {
    let number: String
    @AppStorage(QuickMarkSettings.openPreviewLinksExternally) private var openLinksExternally = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsHeading(number: number, title: "Preview", subtitle: "Make links behave the way you expect.")
            SettingsSectionLabel(title: "LINKS").padding(.top, 27)
            Toggle("Open links in the default browser", isOn: $openLinksExternally)
                .toggleStyle(.switch).font(.system(size: 15)).padding(.top, 18)
            Text("Applies to document windows in PeekMark.")
                .font(.system(size: 13)).foregroundStyle(settingsColor(.muted)).padding(.top, 10)
            SettingsRule().padding(.top, 24)
            SettingsNote {
                VStack(alignment: .leading, spacing: 10) {
                    Text("A note about Quick Look").font(.system(size: 14))
                    Text("Links remain blocked in Finder’s Quick Look preview.")
                        .font(.system(size: 13)).foregroundStyle(settingsColor(.muted))
                }
            }.padding(.top, 28)
        }
    }
}

#if OFFICIAL_EXTENSIONS
private struct ProSettingsView: View {
    let number: String
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsHeading(number: number, title: "PeekMark Pro", subtitle: "More ways to make Markdown your own.")
            SettingsSectionLabel(title: settingsEdition).padding(.top, 27)
            OfficialOptionalFeaturesSettingsView()
                .padding(.top, 18)
        }
    }
}
#endif

private struct AboutView: View {
    let number: String
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsHeading(number: number, title: "About PeekMark", subtitle: "A little more room to read.")
            SettingsSectionLabel(title: "EDITION").padding(.top, 27)
            Text("PeekMark").font(Font(PeekMarkAppearance.displayFont(size: 24))).padding(.top, 16)
            Text(versionDescription).font(.system(size: 13)).foregroundStyle(settingsColor(.muted)).padding(.top, 4)
            SettingsRule().padding(.top, 24)
#if !APP_STORE
            Text("AGPL-3.0 Open Source").font(.system(size: 14)).padding(.top, 26)
            Link("github.com/QuartzInkStudio/PeekMark ↗", destination: URL(string: "https://github.com/QuartzInkStudio/PeekMark")!)
                .font(.system(size: 13)).foregroundStyle(settingsColor(.blue)).padding(.top, 10)
#endif
            Link("Send Feedback…", destination: feedbackURL).buttonStyle(SettingsButtonStyle()).padding(.top, 32)
#if !OFFICIAL_EXTENSIONS
            CommunityNote().padding(.top, 38)
#endif
        }
    }

    private var versionDescription: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
#if APP_STORE
        return String(localized: "Version \(version) · Mac App Store")
#elseif OFFICIAL_EXTENSIONS
        return String(localized: "Version \(version) · Direct")
#else
        return String(localized: "Version \(version) · Community")
#endif
    }
    private var feedbackURL: URL {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = "hello@quartz.ink"
        components.queryItems = [URLQueryItem(name: "subject", value: String(localized: "PeekMark Feedback — \(versionDescription)"))]
        return components.url ?? URL(string: "mailto:hello@quartz.ink")!
    }
}

#if !OFFICIAL_EXTENSIONS
private struct CommunityNote: View {
    var body: some View {
        SettingsNote {
            HStack {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Community edition").font(.system(size: 14))
                    Text("Optional features are available in official editions.")
                        .font(.system(size: 13)).foregroundStyle(settingsColor(.muted))
                }
                Spacer()
                Link("Learn more ↗", destination: URL(string: "https://peekmark.app")!)
                    .font(.system(size: 13)).foregroundStyle(settingsColor(.blue))
            }
        }
    }
}
#endif
