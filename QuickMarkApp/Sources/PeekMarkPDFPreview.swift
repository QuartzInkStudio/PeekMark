#if OFFICIAL_EXTENSIONS
import AppKit
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

/// Embedded PDF preview. The original rendered bytes are retained for saving.
struct PeekMarkPDFPreview: View {
    let title: String
    let render: @MainActor () async throws -> Data
    let onBack: () -> Void

    @ObservedObject private var access = PeekMarkPDFAccess.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var data: Data?
    @State private var document: PDFDocument?
    @State private var loading = true
    @State private var error: String?
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

    init(title: String, render: @escaping @MainActor () async throws -> Data, onBack: @escaping () -> Void) {
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
    private var count: Int { document?.pageCount ?? 0 }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                toolbar
                Rectangle().fill(line).frame(height: 1)
                if loading {
                    VStack(spacing: 12) { ProgressView(); Text("Preparing PDF preview…").foregroundStyle(muted) }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error {
                    VStack(spacing: 14) {
                        Image(systemName: "exclamationmark.triangle").font(.title)
                        Text("Couldn’t prepare PDF").font(.headline)
                        Text(error).foregroundStyle(muted).multilineTextAlignment(.center)
                        Button("Try again") { Task { await load() } }
                    }.padding().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let document {
                    GeometryReader { geometry in
                        // Keep the details column outside the fitted A4 page on smaller windows.
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
        .task { if document == nil && data == nil { await load() } }
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
                Label(access.snapshot.hasPro ? "Save PDF" : "Unlock to save PDF", systemImage: access.snapshot.hasPro ? "square.and.arrow.down" : "lock")
            }.buttonStyle(PDFPrimaryButton(height: 34)).fixedSize().disabled(document == nil)
                .focused($focusedControl, equals: .save)
        }.font(.system(size: 13, weight: .medium)).padding(.horizontal, 26).frame(height: 62)
    }

    private func thumbnails(_ document: PDFDocument) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("PAGES").font(.system(size: 10, weight: .semibold)); Spacer(); Text("\(count) \(count == 1 ? "page" : "pages")").font(.system(size: 11)) }.foregroundStyle(muted)
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
            Text(access.snapshot.hasPro ? "Your PDF is ready to save." : "Preview all pages for free.\nPeekMark Pro unlocks saving.")
                .font(.system(size: 13)).foregroundStyle(muted).padding(.top, 16)
            Rectangle().fill(line).frame(height: 1).padding(.vertical, 24)
            HStack { Text("Paper").foregroundStyle(muted); Spacer(); Text("A4").fontWeight(.semibold) }
            HStack { Text("Length").foregroundStyle(muted); Spacer(); Text("\(count) \(count == 1 ? "page" : "pages")").fontWeight(.semibold) }.padding(.top, 20)
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
                    Text(access.snapshot.isPending ? "Waiting for confirmation…" : "Please wait…")
                }
                .font(.system(size: 12)).foregroundStyle(muted).padding(.top, 12)
            }
            if let status = access.snapshot.status {
                Text(status).font(.system(size: 12)).foregroundStyle(muted).padding(.top, 10)
            }
            Button(action: goBackFromUpgrade) {
                Label(activationVisible ? "Back to upgrade" : "Return to preview", systemImage: "arrow.left")
                    .frame(minHeight: 26)
            }
            .buttonStyle(.plain).foregroundStyle(blue).font(.system(size: 13, weight: .semibold))
            .padding(.top, 18).focused($focusedControl, equals: .returnToPreview)
        }.padding(36)
    }

    private var upgradeTitle: String {
#if !APP_STORE
        if showActivation { return "Activate PeekMark Pro" }
#endif
        return "Save this PDF"
    }

    private var upgradeDescription: String {
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

    @MainActor private func load() async {
        loading = true; error = nil
        do {
            let bytes = try await render()
            guard let pdf = PDFDocument(data: bytes), pdf.pageCount > 0 else { throw PDFPreviewError.invalidDocument }
            data = bytes; document = pdf; page = 0
        } catch { self.error = error.localizedDescription }
        loading = false
    }

    @MainActor private func save() {
        access.refresh()
        guard access.snapshot.hasPro, let data else { showUpgrade = true; return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = filename
        let saveResult: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                access.refresh()
                guard access.snapshot.hasPro else { showUpgrade = true; return }
                do { try data.write(to: url, options: .atomic); savedURL = url }
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

private enum PDFPreviewError: LocalizedError {
    case invalidDocument
    var errorDescription: String? { "The generated PDF could not be opened." }
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
