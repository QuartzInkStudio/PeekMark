import AppKit
import Combine
import QuickMarkCore
import SwiftUI

struct ReaderHeading: Decodable, Identifiable {
    let id: String
    let title: String
    let level: Int
}

enum ReaderMode: String, CaseIterable {
    case read = "Read"
    case split = "Split"
    case source = "Source"

    var title: LocalizedStringKey {
        switch self {
        case .read: "Read"
        case .split: "Split"
        case .source: "Source"
        }
    }
}

@MainActor
private final class ReaderControls: ObservableObject {
    @Published var filename = String(localized: "Untitled")
    @Published var mode = ReaderMode.read
    @Published var headings: [ReaderHeading] = []
    @Published var selectedHeading: String?
    @Published var outlineVisible = true
    @Published var outlineEnabled = true
    @Published var fileIsLocal = false
    @Published var showingPDF = false
    @Published var zoom = 100
}

@MainActor
final class ReaderWindowViewController: NSViewController {
    let split = SplitPreviewViewController()
    private let controls = ReaderControls()
    private let bodyView = NSView()
    private var outlineWidth: NSLayoutConstraint!
    private var outline: NSHostingView<ReaderOutline>!
    private var toolbar: NSHostingView<ReaderToolbar>!
    private var status: NSHostingView<ReaderStatus>!
    private var wantsOutline = true
#if OFFICIAL_EXTENSIONS
    private var pdfHost: NSHostingView<PeekMarkPDFPreview>?
#endif

    override func loadView() {
        let root = ReaderWindowBackdrop()
        root.translatesAutoresizingMaskIntoConstraints = false
        view = root
        let toolbar = NSHostingView(rootView: ReaderToolbar(
            controls: controls,
            changeMode: { [weak self] in self?.changeMode($0) },
            toggleOutline: { [weak self] in self?.toggleOutline() },
            exportPDF: { [weak self] in self?.showPDFPreview() }
        ))
        toolbar.safeAreaRegions = []
        self.toolbar = toolbar
        outline = NSHostingView(rootView: ReaderOutline(
            controls: controls,
            pick: { [weak self] in self?.selectHeading($0) },
            close: { [weak self] in self?.toggleOutline() }
        ))
        status = NSHostingView(rootView: ReaderStatus(
            controls: controls,
            find: { [weak self] in self?.split.findInSource(nil) },
            changeZoom: { [weak self] in self?.changeZoom($0) }
        ))
        addChild(split)
        let reader = split.view
        for element in [toolbar as NSView, bodyView, status as NSView] {
            element.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(element)
        }
        for element in [outline as NSView, reader] {
            element.translatesAutoresizingMaskIntoConstraints = false
            bodyView.addSubview(element)
        }
        outlineWidth = outline.widthAnchor.constraint(equalToConstant: 255)
        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: root.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 58),
            bodyView.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            bodyView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            bodyView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            bodyView.bottomAnchor.constraint(equalTo: status.topAnchor),
            status.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            status.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            status.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            status.heightAnchor.constraint(equalToConstant: 37),
            outline.leadingAnchor.constraint(equalTo: bodyView.leadingAnchor),
            outline.topAnchor.constraint(equalTo: bodyView.topAnchor),
            outline.bottomAnchor.constraint(equalTo: bodyView.bottomAnchor),
            outlineWidth,
            reader.leadingAnchor.constraint(equalTo: outline.trailingAnchor),
            reader.trailingAnchor.constraint(equalTo: bodyView.trailingAnchor),
            reader.topAnchor.constraint(equalTo: bodyView.topAnchor),
            reader.bottomAnchor.constraint(equalTo: bodyView.bottomAnchor),
        ])
        split.onHeadingsChange = { [weak self] items in
            guard let self else { return }
            controls.headings = items
            if !items.contains(where: { $0.id == self.controls.selectedHeading }) {
                controls.selectedHeading = items.first?.id
            }
        }
        split.onDocumentURLChange = { [weak self] url in
            guard let self else { return }
            controls.filename = url?.lastPathComponent ?? String(localized: "Untitled")
            controls.fileIsLocal = url != nil
            self.view.window?.representedURL = url
        }
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        updateOutline()
    }

    func changeMode(_ mode: ReaderMode) {
        let previous = controls.mode
        controls.mode = mode
        split.setMode(mode, moveFocus: previous != mode)
        updateOutline()
    }

    private func toggleOutline() {
        wantsOutline.toggle()
        updateOutline()
    }

    private func updateOutline() {
        let available = controls.mode == .read && view.bounds.width >= 900
        if controls.outlineEnabled != available { controls.outlineEnabled = available }
        let visible = available && wantsOutline
        guard outlineWidth.constant != (visible ? 255 : 0) || outline.isHidden == visible else { return }
        outlineWidth.constant = visible ? 255 : 0
        outline.isHidden = !visible
        controls.outlineVisible = visible
    }

    private func selectHeading(_ heading: ReaderHeading) {
        controls.selectedHeading = heading.id
        split.jumpToHeading(heading.id)
    }

    private func changeZoom(_ zoom: Int) {
        controls.zoom = zoom
        split.setPreviewZoom(zoom)
    }

    func showPDFPreview() {
#if OFFICIAL_EXTENSIONS
        guard pdfHost == nil, let renderer = QuickMarkExtensionRegistry.pdfPreviewRenderer else { return }
        let title = controls.filename
        let sourceURL = split.documentURL
        let markdown = split.markdown
        let preview = PeekMarkPDFPreview(title: title, render: { preset in
            let context = RenderContext(sourceURL: sourceURL, title: title, purpose: .pdfExport)
            let css = try await QuickMarkExtensionRegistry.customizationProviders.first?.customization(for: context) ?? .none
            let html = MarkdownRenderer.render(
                markdown: markdown, title: title,
                customization: PeekMarkTypography.pdfCustomization(combining: css),
                sourceURL: sourceURL
            )
            return try await renderer.renderPDF(html: html, sourceURL: sourceURL, preset: preset)
        }, onBack: { [weak self] in self?.closePDFPreview() })
        let host = NSHostingView(rootView: preview)
        host.safeAreaRegions = []
        pdfHost = host
        host.translatesAutoresizingMaskIntoConstraints = false
        bodyView.isHidden = true
        status.isHidden = true
        controls.showingPDF = true
        view.addSubview(host)
        NSLayoutConstraint.activate([
            host.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            host.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        view.window?.makeFirstResponder(host)
#endif
    }

#if OFFICIAL_EXTENSIONS
    private func closePDFPreview() {
        pdfHost?.removeFromSuperview()
        pdfHost = nil
        bodyView.isHidden = false
        status.isHidden = false
        controls.showingPDF = false
        view.window?.makeFirstResponder(toolbar)
    }
#endif
}

private final class ReaderWindowBackdrop: NSView {
    override func draw(_ dirtyRect: NSRect) {
        PeekMarkAppearance.color(.shell).setFill()
        dirtyRect.fill()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

private func readerColor(_ role: PeekMarkAppearance.Role) -> Color {
    Color(nsColor: PeekMarkAppearance.color(role))
}

private struct ReaderToolbar: View {
    @ObservedObject var controls: ReaderControls
    let changeMode: (ReaderMode) -> Void
    let toggleOutline: () -> Void
    let exportPDF: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text").foregroundStyle(readerColor(.blue)).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(controls.filename).font(.system(size: 14, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                if controls.showingPDF {
                    Text("PDF preview").font(.system(size: 10)).foregroundStyle(readerColor(.muted))
                }
            }.layoutPriority(-1)
            Spacer(minLength: 12)
            if !controls.showingPDF {
                if controls.outlineEnabled && !controls.outlineVisible {
                    Button(action: toggleOutline) { Image(systemName: "sidebar.left").frame(width: 28, height: 28) }
                        .buttonStyle(.plain).help("Show contents").accessibilityLabel("Show contents")
                }
                HStack(spacing: 2) {
                    ForEach(ReaderMode.allCases, id: \.self) { mode in
                        Button(mode.title) { changeMode(mode) }
                            .buttonStyle(ReaderModeButton(selected: mode == controls.mode))
                            .accessibilityAddTraits(mode == controls.mode ? [.isSelected] : [])
                    }
                }
                .padding(3)
                .background(readerColor(.rail), in: .rect(cornerRadius: 7))
#if OFFICIAL_EXTENSIONS
                Button(action: exportPDF) { Label("Export PDF…", systemImage: "doc.badge.arrow.up") }
                    .buttonStyle(ReaderExportButton())
#else
                Button("Copy HTML", systemImage: "doc.on.doc") {
                    (NSApp.keyWindow?.contentViewController as? ReaderWindowViewController)?.split.copyHTML(nil)
                }
                .buttonStyle(ReaderModeButton(selected: false))
#endif
            }
        }
        .foregroundStyle(readerColor(.ink))
        .padding(.leading, 100).padding(.trailing, 26)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(readerColor(.shell))
        .overlay(alignment: .bottom) { Rectangle().fill(readerColor(.line)).frame(height: 1) }
    }
}

private struct ReaderModeButton: ButtonStyle {
    let selected: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: selected ? .semibold : .medium))
            .foregroundStyle(readerColor(selected ? .ink : .muted))
            .frame(minWidth: 56, minHeight: 27)
            .padding(.horizontal, 7)
            .background(readerColor(.paper).opacity(selected || configuration.isPressed ? 1 : 0), in: .rect(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(readerColor(.blue).opacity(selected ? 1 : 0)))
            .contentShape(.rect)
    }
}

private struct ReaderExportButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 13, weight: .semibold))
            .foregroundStyle(readerColor(.accentText))
            .padding(.horizontal, 16).frame(height: 36)
            .background(readerColor(.blue).opacity(configuration.isPressed ? 0.83 : 1), in: .rect(cornerRadius: 6))
    }
}

private struct ReaderOutline: View {
    private var fileStatus: LocalizedStringKey {
        controls.fileIsLocal ? "Local file" : "Unsaved document"
    }


    @ObservedObject var controls: ReaderControls
    let pick: (ReaderHeading) -> Void
    let close: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("CONTENTS").font(Font(PeekMarkAppearance.monoFont(size: 11))).tracking(0.7)
                Spacer()
                Button(action: close) { Image(systemName: "sidebar.left").frame(width: 26, height: 26) }
                    .buttonStyle(.plain).help("Hide contents").accessibilityLabel("Hide contents")
            }.foregroundStyle(readerColor(.muted)).padding(.horizontal, 10)
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    if controls.headings.isEmpty {
                        Text("Headings in this document appear here.")
                            .font(.system(size: 13)).foregroundStyle(readerColor(.muted)).padding(.horizontal, 10)
                    }
                    ForEach(controls.headings) { item in
                        let selected = controls.selectedHeading == item.id
                        Button { pick(item) } label: {
                            Text(item.title).lineLimit(2)
                                .font(.system(size: item.level > 2 ? 13 : 14, weight: selected ? .semibold : .regular))
                                .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
                                .padding(.leading, item.level > 2 ? 30 : 15).padding(.trailing, 7)
                                .background(readerColor(.soft).opacity(selected ? 1 : 0), in: .rect(cornerRadius: 5))
                                .overlay(alignment: .leading) {
                                    if selected { Rectangle().fill(readerColor(.blue)).frame(width: 3) }
                                }
                                .contentShape(.rect)
                        }.buttonStyle(.plain)
                        .accessibilityAddTraits(selected ? [.isSelected] : [])
                    }
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                Divider().overlay(readerColor(.line))
                Label(fileStatus, systemImage: "internaldrive").font(.system(size: 13))
                Text("Markdown document").font(.system(size: 12)).foregroundStyle(readerColor(.muted)).padding(.leading, 26)
            }.padding(.horizontal, 10)
        }
        .foregroundStyle(readerColor(.ink))
        .padding(.horizontal, 17).padding(.top, 23).padding(.bottom, 30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(readerColor(.rail))
        .overlay(alignment: .trailing) { Rectangle().fill(readerColor(.line)).frame(width: 1) }
    }
}

private struct ReaderStatus: View {
    @ObservedObject var controls: ReaderControls
    let find: () -> Void
    let changeZoom: (Int) -> Void

    var body: some View {
        HStack {
            Text("Markdown").font(.system(size: 12))
            Spacer()
            if controls.mode != .source {
                Menu("\(controls.zoom)%") {
                    ForEach([75, 90, 100, 110, 125, 150, 200], id: \.self) { value in
                        Button("\(value)%") { changeZoom(value) }
                    }
                }
                .fixedSize().menuStyle(.borderlessButton).accessibilityLabel("Reading zoom")
                .help("Reading zoom")
            }
            Button(action: find) { Label("Find", systemImage: "magnifyingglass").frame(minWidth: 72, minHeight: 24) }
                .buttonStyle(.plain).foregroundStyle(readerColor(.blue)).help("Find (⌘F)")
        }.foregroundStyle(readerColor(.muted))
            .padding(.horizontal, 27).frame(maxHeight: .infinity)
            .background(readerColor(.shell))
            .overlay(alignment: .top) { Rectangle().fill(readerColor(.line)).frame(height: 1) }
    }
}
