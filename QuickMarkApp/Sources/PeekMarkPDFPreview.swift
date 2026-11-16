#if OFFICIAL_EXTENSIONS
import AppKit
import PDFKit
import QuickMarkCore
import SwiftUI
import UniformTypeIdentifiers

/// Embedded PDF preview. The original rendered bytes are retained for saving.
struct PeekMarkPDFPreview: View {
    let title: String
    let render: @MainActor (PDFExportPreset) async throws -> Data
    let onBack: () -> Void

    @ObservedObject private var access = PeekMarkPDFAccess.shared
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("PDFExportDefaultPreset") private var storedPreset = Data()
    @State private var preset = PDFExportPreset()
    @State private var initializedPreset = false
    @State private var revision = 0
    @State private var rendered: RenderedPDF?
    @State private var failed: FailedRender?

    private struct RenderRequest: Equatable {
        let preset: PDFExportPreset
        let revision: Int
    }
    private struct RenderedPDF {
        let request: RenderRequest
        let data: Data
        let document: PDFDocument
    }
    private struct FailedRender {
        let request: RenderRequest
        let message: String
    }

    private var request: RenderRequest { RenderRequest(preset: preset, revision: revision) }
    private var document: PDFDocument? { rendered?.request == request ? rendered?.document : nil }
    private var error: String? { failed?.request == request ? failed?.message : nil }
    private var rememberedPreset: PDFExportPreset {
        (try? JSONDecoder().decode(PDFExportPreset.self, from: storedPreset)) ?? PDFExportPreset()
    }
    @State private var page = 0
    @State private var zoom: CGFloat = 1
    @State private var fitRevision = 0
    @State private var showUpgrade = false
#if !APP_STORE
    @State private var showActivation = false
    @State private var key = ""
#endif
    @FocusState private var focusedControl: FocusTarget?
    private enum FocusTarget: Hashable { case save, returnToPreview, license }
    @State private var savedURL: URL?
    @State private var saveError: String?

    init(title: String, render: @escaping @MainActor (PDFExportPreset) async throws -> Data, onBack: @escaping () -> Void) {
        self.title = title
        self.render = render
        self.onBack = onBack
    }

    private var filename: String {
        let base = (title as NSString).deletingPathExtension
        return (base.isEmpty ? "Document" : base) + ".pdf"
    }
    private var ink: Color { Color(nsColor: PeekMarkAppearance.color(.ink)) }
    private var muted: Color { Color(nsColor: PeekMarkAppearance.color(.muted)) }
    private var line: Color { Color(nsColor: PeekMarkAppearance.color(.line)) }
    private var blue: Color { Color(nsColor: PeekMarkAppearance.color(.blue)) }
    private var paper: Color { Color(nsColor: PeekMarkAppearance.color(.paper)) }
    private var saveLabel: LocalizedStringKey { access.snapshot.hasPro ? "Save PDF" : "Unlock to save PDF" }
    private var exportDescription: LocalizedStringKey {
        access.snapshot.hasPro ? "Your PDF is ready to save." : "Preview all pages for free.\nPeekMark Pro unlocks saving."
    }
    private var upgradeBackLabel: LocalizedStringKey { activationVisible ? "Back to upgrade" : "Return to preview" }
    private var accessStatus: LocalizedStringKey { access.snapshot.isPending ? "Waiting for confirmation…" : "Please wait…" }
    private var count: Int { document?.pageCount ?? 0 }

    var body: some View {
        let activeRequest = request
        ZStack {
            VStack(spacing: 0) {
                toolbar
                Rectangle().fill(line).frame(height: 1)
                presetBar
                Rectangle().fill(line).frame(height: 1)
                if document == nil && error == nil {
                    VStack(spacing: 12) { ProgressView(); Text("Preparing PDF preview…").foregroundStyle(muted) }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error {
                    VStack(spacing: 14) {
                        Image(systemName: "exclamationmark.triangle").font(.title)
                        Text("Couldn’t prepare PDF").font(.headline)
                        Text(error).foregroundStyle(muted).multilineTextAlignment(.center)
                        Button("Try again") { revision += 1 }
                    }.padding().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let document {
                    GeometryReader { geometry in
                        // Keep the details column outside the fitted page on smaller windows.
                        let spacious = geometry.size.width >= 1180
                        HStack(spacing: 0) {
                            thumbnails(document)
                            Rectangle().fill(line).frame(width: 1)
                            ZStack(alignment: .topTrailing) {
                                PDFDocumentView(document: document, page: $page, zoom: $zoom, fitRevision: fitRevision)
                                    .padding(.trailing, spacious ? 108 : 0)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                if spacious {
                                    details
                                } else if let savedURL {
                                    Button("PDF saved · Show in Finder") {
                                        NSWorkspace.shared.activateFileViewerSelecting([savedURL])
                                    }
                                    .buttonStyle(PDFOutlineButton())
                                    .fixedSize().padding(16)
                                }
                            }
                            .background(Color(nsColor: PeekMarkAppearance.color(.pdfCanvas)))
                        }
                    }
                }
            }
            .background(Color(nsColor: PeekMarkAppearance.color(.shell)))
            .allowsHitTesting(!showUpgrade)
            .accessibilityHidden(showUpgrade)
            if showUpgrade {
                let scrim = colorScheme == .dark ? Color.black.opacity(0.42)
                    : Color(red: 32.0 / 255, green: 40.0 / 255, blue: 61.0 / 255).opacity(68.0 / 255)
                scrim.ignoresSafeArea()
                GeometryReader { geometry in
                    ScrollView {
                        upgradeCard
                            .frame(width: 500)
                            .frame(minHeight: 470, alignment: .topLeading)
                            .background(paper)
                            .overlay(alignment: .top) { Rectangle().fill(blue).frame(height: 4) }
                            .clipShape(.rect(cornerRadius: 12))
                            .frame(maxWidth: .infinity)
                            .padding(.top, max(18, (geometry.size.height - 502) / 2))
                            .padding(.bottom, 18)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }
            }
        }
        .foregroundStyle(ink)
        .task(id: activeRequest) {
            if !initializedPreset {
                initializedPreset = true
                access.refresh()
                if access.snapshot.hasPro, preset != rememberedPreset {
                    preset = rememberedPreset
                    return
                }
            }
            await load(activeRequest)
        }
        .onChange(of: preset) { _, _ in
            savedURL = nil
        }
        .alert("Couldn’t save PDF", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(saveError ?? "") }
        .onChange(of: access.snapshot.hasPro) { _, hasPro in
            if hasPro && showUpgrade { dismissUpgrade() }
        }
        .onExitCommand {
            if showUpgrade { goBackFromUpgrade() } else { onBack() }
        }
    }

    private var toolbar: some View {
        HStack {
            Button(action: onBack) { Label("Back", systemImage: "arrow.left") }
                .buttonStyle(PDFOutlineButton()).fixedSize()
            Spacer()
            HStack(spacing: 0) {
                Button { page = max(0, page - 1) } label: { Image(systemName: "chevron.left").frame(width: 28, height: 28).contentShape(.rect) }
                    .disabled(page <= 0)
                    .accessibilityLabel("Previous page")
                Text("\(count == 0 ? 0 : page + 1) / \(count)").frame(minWidth: 75)
                    .monospacedDigit()
                Button { page = min(count - 1, page + 1) } label: { Image(systemName: "chevron.right").frame(width: 28, height: 28).contentShape(.rect) }
                    .disabled(count == 0 || page >= count - 1)
                    .accessibilityLabel("Next page")
            }.buttonStyle(.plain).padding(.horizontal, 8).frame(height: 32)
                .background(paper, in: RoundedRectangle(cornerRadius: 6)).overlay(RoundedRectangle(cornerRadius: 6).stroke(line))
            HStack(spacing: 9) {
                Button { zoom = max(0.25, zoom / 1.2) } label: { Image(systemName: "minus").frame(width: 26, height: 28).contentShape(.rect) }.accessibilityLabel("Zoom out")
                Button { fitRevision += 1 } label: { Text("Fit").frame(minWidth: 26, minHeight: 28).contentShape(.rect) }.help("Fit page")
                Button { zoom = min(4, zoom * 1.2) } label: { Image(systemName: "plus").frame(width: 26, height: 28).contentShape(.rect) }.accessibilityLabel("Zoom in")
            }.buttonStyle(.plain).padding(.horizontal, 8).frame(height: 32)
                .background(paper, in: RoundedRectangle(cornerRadius: 6)).overlay(RoundedRectangle(cornerRadius: 6).stroke(line))
            Spacer()
            Button {
                access.refresh()
                if access.snapshot.hasPro {
                    save()
                } else {
                    showUpgrade = true
                    focusedControl = .returnToPreview
                }
            } label: {
                Label(saveLabel, systemImage: access.snapshot.hasPro ? "square.and.arrow.down" : "lock")
            }.buttonStyle(PDFPrimaryButton(height: 34)).fixedSize().disabled(document == nil)
                .focused($focusedControl, equals: .save)
        }.font(.system(size: 13, weight: .medium)).padding(.horizontal, 26).frame(height: 62)
    }

    private var presetBar: some View {
        HStack(spacing: 16) {
            Picker("Paper", selection: $preset.paper) {
                ForEach(PDFExportPreset.Paper.allCases, id: \.self) { paper in
                    Text(paper.title).tag(paper)
                }
            }
            .fixedSize()
            Picker("Margins", selection: $preset.margins) {
                ForEach(PDFExportPreset.Margins.allCases, id: \.self) { margins in
                    Text(margins.title).tag(margins)
                }
            }
            .fixedSize()
            Spacer(minLength: 8)
            if access.snapshot.hasPro {
                Button {
                    access.refresh()
                    guard access.snapshot.hasPro,
                          let encoded = try? JSONEncoder().encode(preset) else { return }
                    storedPreset = encoded
                } label: {
                    if preset == rememberedPreset {
                        Text("Default preset")
                    } else {
                        Text("Use as default")
                    }
                }
                .buttonStyle(.link)
                .disabled(preset == rememberedPreset)
            }
        }
        .font(.system(size: 13))
        .padding(.horizontal, 26)
        .padding(.vertical, 8)
    }

    private func thumbnails(_ document: PDFDocument) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("PAGES").font(.system(size: 10, weight: .semibold)); Spacer(); Text("\(count) pages").font(.system(size: 11)) }.foregroundStyle(muted)
            ScrollView {
                VStack(spacing: 18) {
                    ForEach(0..<count, id: \.self) { index in
                        if let pdfPage = document.page(at: index) {
                            Button { page = index } label: {
                                VStack(spacing: 8) {
                                    Image(nsImage: pdfPage.thumbnail(of: NSSize(width: 104, height: 148), for: .mediaBox))
                                        .resizable().aspectRatio(contentMode: .fit).frame(width: 104, height: 148)
                                        .background(Color.white)
                                        .overlay(RoundedRectangle(cornerRadius: 2).stroke(index == page ? blue : line, lineWidth: index == page ? 2 : 1))
                                    Text("\(index + 1)").font(.system(size: 12, weight: index == page ? .semibold : .regular)).foregroundStyle(index == page ? ink : muted)
                                }
                            }.buttonStyle(.plain).accessibilityLabel("Page \(index + 1)")
                        }
                    }
                }.frame(maxWidth: .infinity)
            }
        }.padding(.horizontal, 24).padding(.top, 26).frame(width: 195).frame(maxHeight: .infinity, alignment: .top)
            .background(Color(nsColor: PeekMarkAppearance.color(.shell)))
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("EXPORT DETAILS").font(.system(size: 10, weight: .semibold)).foregroundStyle(muted)
            Text(filename).font(Font(PeekMarkAppearance.displayFont(size: 24))).padding(.top, 16).lineLimit(2)
            Text(exportDescription)
                .font(.system(size: 13)).foregroundStyle(muted).padding(.top, 16)
            Rectangle().fill(line).frame(height: 1).padding(.vertical, 24)
            HStack { Text("Paper").foregroundStyle(muted); Spacer(); Text(preset.paper.title).fontWeight(.semibold) }
            HStack { Text("Length").foregroundStyle(muted); Spacer(); Text("\(count) pages").fontWeight(.semibold) }.padding(.top, 20)
            if let savedURL {
                Label("PDF saved", systemImage: "checkmark.circle.fill").foregroundStyle(Color(nsColor: PeekMarkAppearance.color(.status))).padding(.top, 28)
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([savedURL]) }.buttonStyle(.link).padding(.top, 8)
            }
            Spacer()
        }.font(.system(size: 13)).padding(.top, 48).padding(.leading, 28).padding(.trailing, 79).frame(width: 352).frame(maxHeight: .infinity, alignment: .top)
    }

    private var upgradeCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label("PEEKMARK PRO", systemImage: "doc.badge.checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(blue)
            Text(upgradeTitle)
                .font(Font(PeekMarkAppearance.displayFont(size: 34))).padding(.top, 24)
            Text(upgradeDescription)
                .font(.system(size: 14)).foregroundStyle(muted).padding(.top, 4)
            Rectangle().fill(line).frame(height: 1).padding(.vertical, 20)
#if APP_STORE
            purchaseContent
#else
            if showActivation {
                Text("License key").font(.system(size: 13, weight: .semibold)).padding(.bottom, 8)
                SecureField("Paste your license key", text: $key)
                    .textFieldStyle(.roundedBorder).focused($focusedControl, equals: .license)
                    .accessibilityLabel("License key")
                Button("Activate Pro") {
                    let value = key
                    Task { await access.perform(.activate, key: value) }
                }
                .buttonStyle(PDFPrimaryButton())
                .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || access.snapshot.isBusy)
                .padding(.top, 18)
            } else {
                purchaseContent
            }
#endif
            if access.snapshot.isBusy || access.snapshot.isPending {
                HStack {
                    ProgressView().controlSize(.small)
                    Text(accessStatus)
                }
                .font(.system(size: 12)).foregroundStyle(muted).padding(.top, 12)
            }
            if let status = access.snapshot.status {
                Text(status).font(.system(size: 12)).foregroundStyle(muted).padding(.top, 10)
            }
            Button(action: goBackFromUpgrade) {
                Label(upgradeBackLabel, systemImage: "arrow.left")
                    .frame(minHeight: 26)
            }
            .buttonStyle(.plain).foregroundStyle(blue).font(.system(size: 13, weight: .semibold))
            .padding(.top, 18).focused($focusedControl, equals: .returnToPreview)
        }.padding(36)
    }

    private var upgradeTitle: LocalizedStringKey {
#if !APP_STORE
        if showActivation { return "Activate PeekMark Pro" }
#endif
        return "Save this PDF"
    }

    private var upgradeDescription: LocalizedStringKey {
#if !APP_STORE
        if showActivation { return "Paste the license key from your order confirmation." }
#endif
        return "Save this file and future PDFs with Pro."
    }

    private var activationVisible: Bool {
#if APP_STORE
        false
#else
        showActivation
#endif
    }

    @ViewBuilder private var purchaseContent: some View {
                HStack(alignment: .firstTextBaseline, spacing: 20) {
                    Text(access.snapshot.price ?? "Pro").font(.system(size: 27, weight: .semibold))
                    Text("One-time purchase").font(.system(size: 13)).foregroundStyle(muted)
                }
                Text("Includes workspaces, search and all export formats.").font(.system(size: 13)).foregroundStyle(muted).padding(.top, 10)
                Button {
                    Task { await access.perform(.purchase) }
                } label: {
                    #if APP_STORE
                    Text("Buy with App Store")
                    #else
                    Label("Continue to secure checkout", systemImage: "arrow.up.right")
                    #endif
                }.buttonStyle(PDFPrimaryButton()).disabled(!access.snapshot.canPurchase || access.snapshot.isBusy || access.snapshot.isPending).padding(.top, 22)
                #if APP_STORE
                Button("Restore purchases") { Task { await access.perform(.restore) } }
                    .buttonStyle(PDFOutlineButton()).disabled(access.snapshot.isBusy).padding(.top, 12)
                Text("Use the same Apple Account to restore Pro.").font(.system(size: 12)).foregroundStyle(muted).padding(.top, 16)
                #else
                Button {
                    showActivation = true
                    focusedControl = .license
                } label: { Label("Enter license key", systemImage: "key") }
                    .buttonStyle(PDFOutlineButton()).disabled(access.snapshot.isBusy).padding(.top, 12)
                Text("Checkout opens in your browser.").font(.system(size: 12)).foregroundStyle(muted).padding(.top, 16)
                #endif
    }

    private func dismissUpgrade() {
#if !APP_STORE
        key = ""
        showActivation = false
#endif
        showUpgrade = false
        focusedControl = .save
    }

    private func goBackFromUpgrade() {
#if !APP_STORE
        if showActivation {
            key = ""
            showActivation = false
            focusedControl = .returnToPreview
            return
        }
#endif
        dismissUpgrade()
    }

    @MainActor private func load(_ pending: RenderRequest) async {
        guard request == pending, !Task.isCancelled else { return }
        rendered = nil
        failed = nil
        do {
            let bytes = try await render(pending.preset)
            guard request == pending, !Task.isCancelled else { return }
            guard let pdf = PDFDocument(data: bytes), pdf.pageCount > 0 else { throw PDFPreviewError.invalidDocument }
            page = 0
            zoom = 1
            fitRevision += 1
            rendered = RenderedPDF(request: pending, data: bytes, document: pdf)
        } catch {
            guard request == pending, !Task.isCancelled else { return }
            failed = FailedRender(request: pending, message: error.localizedDescription)
        }
    }

    @MainActor private func save() {
        access.refresh()
        guard access.snapshot.hasPro else { showUpgrade = true; return }
        guard let rendered, rendered.request == request else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = filename
        let saveResult: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                access.refresh()
                guard access.snapshot.hasPro else { showUpgrade = true; return }
                // The panel saves the exact bytes of the preview from which it was opened.
                do {
                    try rendered.data.write(to: url, options: .atomic)
                    if rendered.request == request { savedURL = url }
                }
                catch { self.saveError = error.localizedDescription }
            }
        }
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: saveResult)
        } else {
            panel.begin(completionHandler: saveResult)
        }
    }
}

private extension PDFExportPreset.Paper {
    var title: LocalizedStringKey {
        switch self {
        case .a4: "A4"
        case .usLetter: "US Letter"
        }
    }
}

private extension PDFExportPreset.Margins {
    var title: LocalizedStringKey {
        switch self {
        case .standard: "Standard"
        case .compact: "Compact"
        }
    }
}

private enum PDFPreviewError: LocalizedError {
    case invalidDocument
    var errorDescription: String? { String(localized: "The generated PDF could not be opened.") }
}

private struct PDFPrimaryButton: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    var height: CGFloat = 42
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 13, weight: .semibold)).frame(maxWidth: .infinity).padding(.horizontal, 18).frame(height: height)
            .foregroundStyle(Color(nsColor: PeekMarkAppearance.color(.accentText))).background(Color(nsColor: PeekMarkAppearance.color(.blue)).opacity(enabled ? (configuration.isPressed ? 0.8 : 1) : 0.45), in: RoundedRectangle(cornerRadius: 6))
    }
}

private struct PDFOutlineButton: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 13, weight: .semibold)).frame(maxWidth: .infinity).padding(.horizontal, 14).frame(height: 38)
            .foregroundStyle(Color(nsColor: PeekMarkAppearance.color(.ink)).opacity(enabled ? 1 : 0.45))
            .background(Color(nsColor: PeekMarkAppearance.color(.paper)).opacity(configuration.isPressed ? 0.6 : 1), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: PeekMarkAppearance.color(.line))))
    }
}

private struct PDFDocumentView: NSViewRepresentable {
    let document: PDFDocument
    @Binding var page: Int
    @Binding var zoom: CGFloat
    let fitRevision: Int

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> ProtectedPDFView {
        let view = ProtectedPDFView()
        view.displayMode = .singlePage
        view.displayDirection = .vertical
        view.displaysPageBreaks = false
        view.autoScales = false
        view.backgroundColor = PeekMarkAppearance.color(.pdfCanvas)
        view.document = document
        context.coordinator.observe(view)
        return view
    }
    func updateNSView(_ view: ProtectedPDFView, context: Context) {
        context.coordinator.parent = self
        if view.document !== document {
            view.document = document
            view.fitsPage = true
        }
        if let target = document.page(at: page), view.currentPage !== target { view.go(to: target) }
        if context.coordinator.fitRevision != fitRevision {
            context.coordinator.fitRevision = fitRevision
            view.fitsPage = true
            view.applyPageFit()
        } else if abs(view.scaleFactor - zoom) > 0.01 && context.coordinator.lastZoom != zoom {
            view.fitsPage = false
            view.scaleFactor = zoom
        }
        context.coordinator.lastZoom = zoom
    }
    final class Coordinator: NSObject {
        var parent: PDFDocumentView
        var fitRevision = 0
        var lastZoom: CGFloat = 1
        private var observer: NSObjectProtocol?
        private var scaleObserver: NSObjectProtocol?
        init(_ parent: PDFDocumentView) { self.parent = parent }
        func observe(_ view: PDFView) {
            observer = NotificationCenter.default.addObserver(forName: .PDFViewPageChanged, object: view, queue: .main) { [weak self, weak view] _ in
                guard let self, let view, let current = view.currentPage, let document = view.document else { return }
                let index = document.index(for: current)
                if index != NSNotFound && self.parent.page != index {
                    DispatchQueue.main.async { [weak self] in self?.parent.page = index }
                }
            }
            scaleObserver = NotificationCenter.default.addObserver(forName: .PDFViewScaleChanged, object: view, queue: .main) { [weak self, weak view] _ in
                guard let self, let view, abs(self.parent.zoom - view.scaleFactor) > 0.01 else { return }
                let scale = view.scaleFactor
                self.lastZoom = scale
                DispatchQueue.main.async { [weak self] in self?.parent.zoom = scale }
            }
        }
        deinit {
            if let observer { NotificationCenter.default.removeObserver(observer) }
            if let scaleObserver { NotificationCenter.default.removeObserver(scaleObserver) }
        }
    }
}

/// Disables PDFKit's copy, print, selection, contextual menu, and drag paths while
/// retaining scroll, page navigation, zoom, and the native accessibility tree.
private final class ProtectedPDFView: PDFView {
    var fitsPage = true

    override func layout() {
        super.layout()
        if fitsPage { applyPageFit() }
    }

    func applyPageFit() {
        guard let page = currentPage ?? document?.page(at: 0),
              bounds.width > 100, bounds.height > 125 else { return }
        let pageBounds = page.bounds(for: .mediaBox)
        let fit = min((bounds.width - 48) / pageBounds.width, (bounds.height - 100) / pageBounds.height)
        if fit > 0, abs(scaleFactor - fit) > 0.005 { scaleFactor = fit }
    }

    override func menu(for event: NSEvent) -> NSMenu? { nil }
    override func mouseDragged(with event: NSEvent) { clearSelection() }
    override func mouseUp(with event: NSEvent) { super.mouseUp(with: event); clearSelection() }
    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command), let key = event.charactersIgnoringModifiers?.lowercased(), ["a", "c", "p", "s"].contains(key) { return }
        super.keyDown(with: event)
    }
    override func copy(_ sender: Any?) {}
    override func selectAll(_ sender: Any?) {}
}
#endif
