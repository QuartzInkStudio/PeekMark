import AppKit
import WebKit
import QuickMarkCore
import UniformTypeIdentifiers

/// A floating split-view window:
///   Left  → editable NSTextView with raw Markdown source
///   Right → WKWebView live preview (updates on every keystroke)
@MainActor
final class MarkdownPreviewWindowController: NSObject {
    static let shared = MarkdownPreviewWindowController()

    private var windows: [NSWindow] = []
    private weak var scratchpadWindow: NSWindow?

    func show(url: URL) {
        _ = show(url: url, reportFailure: true)
    }

    func showLinkedDocument(url: URL, from hostWindow: NSWindow?) {
        guard !show(url: url, reportFailure: false) else { return }

        let panel = NSOpenPanel()
        panel.title = String(localized: "Allow Access to Linked Markdown File")
        panel.message = String(localized: "Choose \(url.lastPathComponent) to open this link.")
        panel.allowedContentTypes = QuickMarkMarkdownFiles.extensions.compactMap { .init(filenameExtension: $0) }
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.canCreateDirectories = false
        panel.directoryURL = url.deletingLastPathComponent()
        panel.nameFieldStringValue = url.lastPathComponent

        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let selectedURL = panel.url else { return }
            self?.show(url: selectedURL)
        }
        if let hostWindow {
            panel.beginSheetModal(for: hostWindow, completionHandler: completion)
        } else {
            panel.begin(completionHandler: completion)
        }
    }

    @discardableResult
    private func show(url: URL, reportFailure: Bool) -> Bool {
        let resolvedURL = RecentMarkdownStore.shared.resolvedURL(for: url)
        let didStartAccessing = resolvedURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                resolvedURL.stopAccessingSecurityScopedResource()
            }
        }

        let markdown: String
        do {
            markdown = try String(contentsOf: resolvedURL, encoding: .utf8)
        } catch {
            if reportFailure {
                RecentMarkdownStore.shared.remove(url)
                showOpenError(error, for: resolvedURL)
            }
            return false
        }

        let (window, splitVC) = createWindow()
        load(markdown: markdown, url: resolvedURL, in: window, splitVC: splitVC)
        window.makeKeyAndOrderFront(nil)
        positionWindowForFirstOpen(window)
        NSApp.activate(ignoringOtherApps: true)
        return true
    }

    func showNewDocument() {
        let (window, splitVC) = createWindow()
        flashNewDocumentTitle(window)
        splitVC.loadNew()
        (window.contentViewController as? ReaderWindowViewController)?.changeMode(.split)
        window.makeKeyAndOrderFront(nil)
        splitVC.focusEditor()
        positionWindowForFirstOpen(window)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showScratchpad() {
        if let scratchpadWindow, scratchpadWindow.isVisible {
            scratchpadWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let (window, splitVC) = createWindow()
        let url = scratchpadURL()
        let markdown = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        window.title = String(localized: "Scratchpad")
        splitVC.load(markdown: markdown, url: url)
        scratchpadWindow = window
        (window.contentViewController as? ReaderWindowViewController)?.changeMode(.split)
        window.makeKeyAndOrderFront(nil)
        splitVC.focusEditor()
        positionWindowForFirstOpen(window)
        NSApp.activate(ignoringOtherApps: true)
    }

    func openMarkdownDocument(closing welcomeWindow: NSWindow? = nil) {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Open Markdown File")
        panel.allowedContentTypes = QuickMarkMarkdownFiles.extensions.compactMap { .init(filenameExtension: $0) }
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.show(url: url)
            welcomeWindow?.close()
        }
    }

    private func createWindow() -> (NSWindow, SplitPreviewViewController) {
        let reader = ReaderWindowViewController()
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        win.title = "PeekMark"
        win.titleVisibility = .hidden
        win.titlebarAppearsTransparent = true
        win.isMovableByWindowBackground = true
        win.contentViewController = reader
        win.minSize = NSSize(width: 720, height: 480)
        win.center()
        win.isReleasedWhenClosed = false
        win.delegate = self

        windows.append(win)
        return (win, reader.split)
    }

    private func positionWindowForFirstOpen(_ window: NSWindow) {
        let visibleFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
        guard let visibleFrame else {
            window.center()
            return
        }

        #if DEBUG
        let compact = ProcessInfo.processInfo.environment["PEEKMARK_QA_SCREEN"] == "split"
        #else
        let compact = false
        #endif
        let width = min(compact ? 960 : 1280, visibleFrame.width - 24)
        let height = min(compact ? 700 : 800, visibleFrame.height - 24)
        let x = visibleFrame.midX - width / 2
        let y = visibleFrame.midY - height / 2

        window.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
    }

    private func flashNewDocumentTitle(_ window: NSWindow) {
        window.title = String(localized: "New Document")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            guard self?.windows.contains(where: { $0 === window }) == true else { return }
            window.title = String(localized: "Untitled")
        }
    }

    private func load(markdown: String, url: URL, in window: NSWindow, splitVC: SplitPreviewViewController) {
        window.title = url.deletingPathExtension().lastPathComponent
        window.representedURL = url
        splitVC.load(markdown: markdown, url: url)
        RecentMarkdownStore.shared.add(url)
    }

    private func showOpenError(_ error: Error, for url: URL) {
        let alert = NSAlert(error: error)
        alert.messageText = String(localized: "Unable to Open Markdown File")
        alert.informativeText = url.path
        alert.runModal()
    }

    private func scratchpadURL() -> URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PeekMark", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("Scratchpad.md")
    }
}

extension MarkdownPreviewWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow else { return }
        windows.removeAll { $0 === closingWindow }
    }
}

// MARK: - Split View Controller

final class SplitPreviewViewController: NSSplitViewController {
    private let editorVC = EditorViewController()
    private let previewVC = PreviewWebViewController()
    private lazy var editorItem = NSSplitViewItem(viewController: editorVC)
    private lazy var previewItem = NSSplitViewItem(viewController: previewVC)
    private var mode = ReaderMode.read
    private var sourceFraction = 0.40

    var onHeadingsChange: (([ReaderHeading]) -> Void)?
    var onDocumentURLChange: ((URL?) -> Void)?
    var markdown: String { editorVC.markdownText }
    var documentURL: URL? { editorVC.documentURL }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.wantsLayer = true
        splitView.wantsLayer = true
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        editorItem.minimumThickness = 235
        previewItem.minimumThickness = 290
        addSplitViewItem(editorItem)
        addSplitViewItem(previewItem)
        editorItem.isCollapsed = true

        editorVC.onTextChange = { [weak self] markdown in
            self?.previewVC.render(markdown: markdown)
        }
        editorVC.onURLChange = { [weak self] url in
            guard let self else { return }
            previewVC.sourceURL = url
            previewVC.baseURL = url?.deletingLastPathComponent()
            previewVC.render(markdown: editorVC.markdownText)
            onDocumentURLChange?(url)
        }
        previewVC.onHeadingsChange = { [weak self] in self?.onHeadingsChange?($0) }
    }

    func load(markdown: String, url: URL) {
        _ = view
        editorVC.setText(markdown)
        editorVC.setCurrentURL(url)
    }

    func loadNew() {
        _ = view
        editorVC.setText("")
        editorVC.setCurrentURL(nil)
    }

    func setMode(_ next: ReaderMode, moveFocus: Bool) {
        _ = view
        if mode == .split && splitView.bounds.width > 1 && !editorItem.isCollapsed {
            sourceFraction = editorVC.view.bounds.width / splitView.bounds.width
        }
        mode = next
        editorVC.setSplitPresentation(next == .split)
        previewVC.setSplitPresentation(next == .split)
        editorItem.isCollapsed = next == .read
        previewItem.isCollapsed = next == .source
        if next == .split {
            splitView.layoutSubtreeIfNeeded()
            let width = splitView.bounds.width
            if width > 525 {
                splitView.setPosition(min(width - 290, max(235, width * sourceFraction)), ofDividerAt: 0)
            }
        }
        if moveFocus {
            if next == .read { previewVC.focus() } else { editorVC.focus() }
        }
    }

    func focusEditor() { editorVC.focus() }
    func jumpToHeading(_ id: String) { previewVC.jumpToHeading(id) }
    func setPreviewZoom(_ value: Int) { previewVC.setZoom(value) }

    private var window: NSWindow? { view.window }

    @objc func saveCurrentFile(_ sender: Any?) {
        editorVC.saveFile()
    }

    @objc func copyHTML(_ sender: Any?) {
        let html = MarkdownRenderer.render(markdown: editorVC.markdownText, title: window?.title ?? "PeekMark")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(html, forType: .html)
        NSPasteboard.general.setString(html, forType: .string)
        flashTitle(String(localized: "✓ HTML Copied"))
    }

    func exportDocument(using exporter: any DocumentExporting) {
        let panel = NSSavePanel()
        panel.title = exporter.format.displayName
        panel.nameFieldStringValue = "\(window?.title ?? "Untitled").\(exporter.format.filenameExtension)"
        if let contentType = UTType(filenameExtension: exporter.format.filenameExtension) {
            panel.allowedContentTypes = [contentType]
        }

        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let destinationURL = panel.url, let self else { return }
            let sourceURL = editorVC.documentURL
            let purpose: RenderPurpose
            switch exporter.format.filenameExtension.lowercased() {
            case "pdf": purpose = .pdfExport
            case "docx": purpose = .docxExport
            default: purpose = .htmlExport
            }
            let context = RenderContext(
                sourceURL: sourceURL,
                title: window?.title ?? "PeekMark",
                purpose: purpose
            )
            let provider = QuickMarkExtensionRegistry.customizationProviders.first
            let markdown = editorVC.markdownText

            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    let customization = try await provider?.customization(for: context) ?? .none
                    let html = MarkdownRenderer.render(
                        markdown: markdown,
                        title: context.title,
                        customization: customization
                    )
                    try await exporter.export(ExportRequest(
                        html: html,
                        context: context,
                        destinationURL: destinationURL
                    ))
                    flashTitle(String(localized: "✓ Exported"))
                    NSWorkspace.shared.activateFileViewerSelecting([destinationURL])
                } catch {
                    let alert = NSAlert(error: error)
                    alert.messageText = String(localized: "Unable to Export Document")
                    if let hostWindow = window ?? NSApp.keyWindow {
                        alert.beginSheetModal(for: hostWindow) { _ in }
                    } else {
                        alert.runModal()
                    }
                }
            }
        }
        if let hostWindow = window ?? NSApp.keyWindow {
            panel.beginSheetModal(for: hostWindow, completionHandler: completion)
        } else {
            panel.begin(completionHandler: completion)
        }
    }

    @objc func findInSource(_ sender: Any?) {
        if mode == .read { previewVC.showFindPanel() } else { editorVC.showFindPanel() }
    }

    private func flashTitle(_ title: String) {
        guard let window else { return }
        let original = window.title
        window.title = title
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak window] in
            window?.title = original
        }
    }
}

// MARK: - Editor (left pane)

/// Draw outside AppKit's editable text rect. The clip view drives gutter scroll.
private final class SourceLineGutter: NSView {
    weak var scrollView: NSScrollView?
    weak var textView: NSTextView?
    private var scrollObservation: NSObjectProtocol?

    init(scrollView: NSScrollView, textView: NSTextView) {
        self.scrollView = scrollView
        self.textView = textView
        super.init(frame: .zero)
        setAccessibilityElement(false)
        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollObservation = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification, object: scrollView.contentView, queue: .main
        ) { [weak self] _ in self?.needsDisplay = true }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        if let scrollObservation { NotificationCenter.default.removeObserver(scrollObservation) }
    }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let textView, let scrollView,
              let layoutManager = textView.layoutManager, let textContainer = textView.textContainer else { return }
        let source = textView.string as NSString
        let viewport = scrollView.documentVisibleRect
        let origin = textView.textContainerOrigin
        let visible = viewport.offsetBy(dx: -origin.x, dy: -origin.y)
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visible, in: textContainer)
        let firstCharacter = glyphRange.location < layoutManager.numberOfGlyphs
            ? min(source.length, layoutManager.characterIndexForGlyph(at: glyphRange.location))
            : source.length
        var lineStart = 0
        var lineNumber = 1
        while lineStart < firstCharacter {
            let range = source.lineRange(for: NSRange(location: lineStart, length: 0))
            guard NSMaxRange(range) <= firstCharacter, NSMaxRange(range) > lineStart else { break }
            lineStart = NSMaxRange(range)
            lineNumber += 1
        }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: PeekMarkAppearance.monoFont(size: 11),
            .foregroundColor: PeekMarkAppearance.color(.muted)
        ]
        while lineStart <= source.length {
            let rect: NSRect
            if lineStart == source.length {
                guard source.length == 0 || source.character(at: source.length - 1) == 10 || source.character(at: source.length - 1) == 13 else { break }
                rect = layoutManager.extraLineFragmentRect
            } else {
                let glyph = layoutManager.glyphIndexForCharacter(at: lineStart)
                rect = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            }
            let y = rect.minY + origin.y - viewport.minY
            if y > bounds.maxY { break }
            if y + rect.height >= bounds.minY {
                let label = "\(lineNumber)" as NSString
                let width = label.size(withAttributes: attributes).width
                label.draw(at: NSPoint(x: 35 - width, y: y + 1), withAttributes: attributes)
            }
            guard lineStart < source.length else { break }
            let next = NSMaxRange(source.lineRange(for: NSRange(location: lineStart, length: 0)))
            guard next > lineStart else { break }
            lineStart = next
            lineNumber += 1
        }
    }
}

private final class SplitPaneHeader: NSView {
    private let title: String
    private let background: PeekMarkAppearance.Role
    private let leading: CGFloat

    init(title: String, background: PeekMarkAppearance.Role, leading: CGFloat) {
        self.title = title
        self.background = background
        self.leading = leading
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        PeekMarkAppearance.color(background).setFill()
        bounds.fill()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: PeekMarkAppearance.monoFont(size: 11),
            .foregroundColor: PeekMarkAppearance.color(.muted),
            .kern: 1.0
        ]
        (title as NSString).draw(at: NSPoint(x: leading, y: 22), withAttributes: attributes)
        PeekMarkAppearance.color(.line).setFill()
        NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()
    }
}

final class EditorViewController: NSViewController {
    var onTextChange: ((String) -> Void)?
    var onURLChange: ((URL?) -> Void)?
    var markdownText: String { textView.string }
    var documentURL: URL? { currentURL }

    private var currentURL: URL?
    private var securityScopedURL: URL?
    private var scrollView: NSScrollView!
    private var textView: NSTextView!
    private var gutter: SourceLineGutter!
    private var headerHeight: NSLayoutConstraint!

    deinit {
        securityScopedURL?.stopAccessingSecurityScopedResource()
    }

    override func loadView() {
        scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        textView = NSTextView(usingTextLayoutManager: false)
        textView.isEditable = true
        textView.isRichText = false
        textView.font = PeekMarkAppearance.monoFont(size: 13)
        textView.textColor = PeekMarkAppearance.color(.ink)
        textView.backgroundColor = PeekMarkAppearance.color(.rail)
        textView.insertionPointColor = PeekMarkAppearance.color(.blue)
        textView.setAccessibilityLabel(String(localized: "Markdown source"))
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.textContainerInset = NSSize(width: 22, height: 23)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 5
        textView.defaultParagraphStyle = paragraph
        textView.typingAttributes[.paragraphStyle] = paragraph
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.delegate = self
        textView.allowsUndo = true

        // Set colors for both light and dark mode
        textView.drawsBackground = true

        scrollView.documentView = textView
        let container = NSView()
        let header = SplitPaneHeader(title: String(localized: "SOURCE"), background: .rail, leading: 22)
        header.translatesAutoresizingMaskIntoConstraints = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(header)
        container.addSubview(scrollView)
        gutter = SourceLineGutter(scrollView: scrollView, textView: textView)
        gutter.isHidden = true
        gutter.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(gutter)
        NSLayoutConstraint.activate([
            gutter.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            gutter.topAnchor.constraint(equalTo: scrollView.topAnchor),
            gutter.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            gutter.widthAnchor.constraint(equalToConstant: 43)
        ])
        headerHeight = header.heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: container.topAnchor),
            header.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            headerHeight,
            scrollView.topAnchor.constraint(equalTo: header.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        view = container
    }

    func setText(_ markdown: String) {
        textView.string = markdown
        gutter.needsDisplay = true
        if let paragraph = textView.defaultParagraphStyle {
            textView.textStorage?.addAttribute(.paragraphStyle, value: paragraph,
                                              range: NSRange(location: 0, length: textView.textStorage?.length ?? 0))
        }
    }

    func setSplitPresentation(_ enabled: Bool) {
        _ = view
        headerHeight.constant = enabled ? 57 : 0
        gutter.isHidden = !enabled
        gutter.needsDisplay = true
        textView.textContainerInset = NSSize(width: enabled ? 51 : 22, height: 23)
    }

    func setCurrentURL(_ url: URL?) {
        securityScopedURL?.stopAccessingSecurityScopedResource()
        securityScopedURL = nil
        currentURL = url
        if let url, url.startAccessingSecurityScopedResource() { securityScopedURL = url }
        onURLChange?(url)
    }

    func focus() { view.window?.makeFirstResponder(textView) }

    func showFindPanel() {
        let alert = NSAlert()
        alert.messageText = String(localized: "Find in Source")
        alert.informativeText = String(localized: "Enter text to find in the Markdown source.")
        alert.addButton(withTitle: String(localized: "Find"))
        alert.addButton(withTitle: String(localized: "Cancel"))

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        alert.accessoryView = field

        guard alert.runModal() == .alertFirstButtonReturn, !field.stringValue.isEmpty else { return }
        find(field.stringValue)
    }

    private func find(_ query: String) {
        let nsString = textView.string as NSString
        let selectedEnd = textView.selectedRange().upperBound
        var range = nsString.range(of: query, options: [.caseInsensitive], range: NSRange(location: selectedEnd, length: nsString.length - selectedEnd))
        if range.location == NSNotFound {
            range = nsString.range(of: query, options: [.caseInsensitive])
        }
        guard range.location != NSNotFound else { NSSound.beep(); return }
        textView.setSelectedRange(range)
        textView.scrollRangeToVisible(range)
        view.window?.makeFirstResponder(textView)
    }

    @objc func saveFile() {
        guard let url = currentURL else {
            saveAs()
            return
        }
        do {
            try textView.string.write(to: url, atomically: true, encoding: .utf8)
            if let win = view.window {
                let original = win.title
                win.title = String(localized: "✓ Saved")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    win.title = original
                }
            }
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
        }
    }

    private func saveAs() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: "md")!]
        panel.nameFieldStringValue = "Untitled.md"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            do {
                try self.textView.string.write(to: url, atomically: true, encoding: .utf8)
                self.setCurrentURL(url)
                RecentMarkdownStore.shared.add(url)
            } catch {
                let alert = NSAlert(error: error)
                alert.runModal()
            }
        }
    }
}

extension EditorViewController: NSTextViewDelegate {
    func textDidChange(_ notification: Notification) {
        gutter.needsDisplay = true
        onTextChange?(textView.string)
    }
}

// MARK: - Preview (right pane)

final class PreviewWebViewController: NSViewController, WKNavigationDelegate {
    var baseURL: URL?
    var sourceURL: URL?
    var onHeadingsChange: (([ReaderHeading]) -> Void)?
    private var webView: WKWebView!
    private var renderTask: Task<Void, Never>?
    private var currentNavigation: WKNavigation?
    private var headerHeight: NSLayoutConstraint!

    deinit { renderTask?.cancel() }

    override func loadView() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: .zero, configuration: config)
        webView.underPageBackgroundColor = PeekMarkAppearance.color(.paper)
        webView.setAccessibilityLabel(String(localized: "Rendered Markdown"))
        webView.navigationDelegate = self
        let container = NSView()
        let header = SplitPaneHeader(title: String(localized: "PREVIEW"), background: .paper, leading: 36)
        header.translatesAutoresizingMaskIntoConstraints = false
        webView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(header)
        container.addSubview(webView)
        headerHeight = header.heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: container.topAnchor),
            header.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            headerHeight,
            webView.topAnchor.constraint(equalTo: header.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        view = container
    }

    func setSplitPresentation(_ enabled: Bool) {
        _ = view
        headerHeight.constant = enabled ? 57 : 0
    }

    func render(markdown: String, baseURL: URL? = nil) {
        let resolvedBase = baseURL ?? self.baseURL
        let context = RenderContext(sourceURL: sourceURL, title: "Preview", purpose: .appPreview)
        let provider = QuickMarkExtensionRegistry.customizationProviders.first

        renderTask?.cancel()
        renderTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(150))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }

            let customization: RenderCustomization
            if let provider {
                do {
                    customization = try await provider.customization(for: context)
                } catch {
                    customization = .none
                }
            } else {
                customization = .none
            }
            guard !Task.isCancelled, let self else { return }

            let html = MarkdownRenderer.render(
                markdown: markdown,
                title: context.title,
                customization: PeekMarkTypography.readerCustomization(combining: customization),
                sourceURL: context.sourceURL
            )
            currentNavigation = webView.loadHTMLString(html, baseURL: resolvedBase)
        }
    }

    func focus() { view.window?.makeFirstResponder(webView) }

    func setZoom(_ percent: Int) { webView.pageZoom = Double(percent) / 100 }

    func jumpToHeading(_ id: String) {
        webView.callAsyncJavaScript("document.getElementById(anchor)?.scrollIntoView({block: 'start'});",
                                    arguments: ["anchor": id], in: nil, in: .page, completionHandler: nil)
    }

    func showFindPanel() {
        guard let window = view.window else { return }
        let alert = NSAlert()
        alert.messageText = String(localized: "Find in Markdown")
        alert.addButton(withTitle: String(localized: "Find"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 26))
        field.placeholderString = String(localized: "Find text")
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { [weak self] result in
            guard result == .alertFirstButtonReturn, !field.stringValue.isEmpty else { return }
            let configuration = WKFindConfiguration()
            configuration.wraps = true
            self?.webView.find(field.stringValue, configuration: configuration) { result in
                if !result.matchFound { NSSound.beep() }
            }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard navigation === currentNavigation else { return }
        webView.evaluateJavaScript("""
            JSON.stringify(Array.from(document.querySelectorAll('article :is(h1,h2,h3,h4,h5,h6)[id]'))
              .filter((node,index) => node.tagName !== 'H1' || index !== 0)
              .map(node => ({id:node.id,title:(() => {const copy=node.cloneNode(true);copy.querySelectorAll('.peekmark-heading-anchor').forEach(link=>link.remove());return copy.textContent.trim();})(),level:Number(node.tagName[1])})))
            """) { [weak self] value, _ in
            guard let self, navigation === currentNavigation, let json = value as? String,
                  let headings = try? JSONDecoder().decode([ReaderHeading].self, from: Data(json.utf8)) else { return }
            onHeadingsChange?(headings.filter { !$0.title.isEmpty })
        }
    }

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if navigationAction.navigationType == .linkActivated {
            if Self.isLocalAnchor(navigationAction.request.url) {
                decisionHandler(.allow)
                return
            }
            if openLocalWikilink(navigationAction.request.url) {
                decisionHandler(.cancel)
                return
            }
            if openLocalMarkdownLink(navigationAction.request.url) {
                decisionHandler(.cancel)
                return
            }
            if UserDefaults.standard.bool(forKey: QuickMarkSettings.openPreviewLinksExternally),
               let url = navigationAction.request.url,
               Self.canOpenExternally(url) {
                NSWorkspace.shared.open(url)
            }
            decisionHandler(.cancel)
        } else if Self.isAllowedPreviewURL(navigationAction.request.url) {
            decisionHandler(.allow)
        } else {
            decisionHandler(.cancel)
        }
    }

    private func openLocalWikilink(_ url: URL?) -> Bool {
        guard let target = MarkdownWikilinkResolver.target(from: url) else { return false }
        guard let directory = baseURL,
              let linkedURL = MarkdownWikilinkResolver.resolve(target, in: directory) else {
            NSSound.beep()
            return true
        }
        MarkdownPreviewWindowController.shared.showLinkedDocument(url: linkedURL, from: view.window)
        return true
    }

    private func openLocalMarkdownLink(_ url: URL?) -> Bool {
        guard let url, url.isFileURL else { return false }

        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.fragment = nil
        guard let linkedURL = components?.url?.standardizedFileURL,
              QuickMarkMarkdownFiles.isMarkdown(linkedURL) else {
            return false
        }

        MarkdownPreviewWindowController.shared.showLinkedDocument(url: linkedURL, from: view.window)
        return true
    }

    private static func isAllowedPreviewURL(_ url: URL?) -> Bool {
        guard let url else { return true }
        guard let scheme = url.scheme?.lowercased() else { return true }
        return scheme == "file" || scheme == "about"
    }

    private static func isLocalAnchor(_ url: URL?) -> Bool {
        guard let url, url.fragment?.isEmpty == false else { return false }
        guard let scheme = url.scheme?.lowercased() else { return true }
        return scheme == "file" || scheme == "about"
    }

    private static func canOpenExternally(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https" || scheme == "mailto"
    }
}
