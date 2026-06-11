import AppKit
import WebKit
import QuickMarkCore

/// A floating split-view window:
///   Left  → editable NSTextView with raw Markdown source
///   Right → WKWebView live preview (updates on every keystroke)
final class MarkdownPreviewWindowController: NSObject {
    static let shared = MarkdownPreviewWindowController()

    private var window: NSWindow?
    private var splitVC: SplitPreviewViewController?
    private var currentURL: URL?

    func show(url: URL) {
        if window == nil { createWindow() }
        load(url: url)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func createWindow() {
        let vc = SplitPreviewViewController()
        splitVC = vc

        // Adapt to screen size: 80% of visible area, minimum 1000×700
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let width  = max(1000, screen.width  * 0.82)
        let height = max(700,  screen.height * 0.85)

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        win.title = "QuickMark"
        win.contentViewController = vc
        win.center()
        win.isReleasedWhenClosed = false
        window = win

        let toolbar = NSToolbar(identifier: "QuickMarkToolbar")
        toolbar.delegate = vc
        toolbar.displayMode = .iconAndLabel
        win.toolbar = toolbar
    }

    private func load(url: URL) {
        currentURL = url
        let markdown = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        window?.title = url.deletingPathExtension().lastPathComponent
        splitVC?.load(markdown: markdown, url: url)
    }
}

// MARK: - Split View Controller

final class SplitPreviewViewController: NSSplitViewController, NSToolbarDelegate {
    private let editorItem = NSSplitViewItem(viewController: EditorViewController())
    private let previewItem = NSSplitViewItem(viewController: PreviewWebViewController())

    private var editorVC: EditorViewController { editorItem.viewController as! EditorViewController }
    private var previewVC: PreviewWebViewController { previewItem.viewController as! PreviewWebViewController }

    private enum ViewMode {
        case both, editorOnly, previewOnly
        mutating func toggle() {
            switch self {
            case .both:        self = .editorOnly
            case .editorOnly:  self = .previewOnly
            case .previewOnly: self = .both
            }
        }
        var label: String {
            switch self {
            case .both:        return "Split"
            case .editorOnly:  return "Source"
            case .previewOnly: return "Preview"
            }
        }
        var icon: String {
            switch self {
            case .both:        return "rectangle.split.2x1"
            case .editorOnly:  return "doc.text"
            case .previewOnly: return "eye"
            }
        }
    }

    private var viewMode: ViewMode = .both

    override func viewDidLoad() {
        super.viewDidLoad()
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        addSplitViewItem(editorItem)
        addSplitViewItem(previewItem)

        editorVC.onTextChange = { [weak self] markdown in
            self?.previewVC.render(markdown: markdown)
        }

        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "s" {
                self?.saveCurrentFile(nil)
                return nil
            }
            return event
        }
    }

    func load(markdown: String, url: URL) {
        editorVC.setText(markdown)
        previewVC.baseURL = url.deletingLastPathComponent()
        previewVC.render(markdown: markdown, baseURL: url.deletingLastPathComponent())
        editorVC.currentURL = url
    }

    @objc func saveCurrentFile(_ sender: Any?) {
        editorVC.saveFile()
    }

    @objc func toggleViewMode(_ sender: Any?) {
        viewMode.toggle()
        switch viewMode {
        case .both:
            editorItem.isCollapsed = false
            previewItem.isCollapsed = false
        case .editorOnly:
            editorItem.isCollapsed = false
            previewItem.isCollapsed = true
        case .previewOnly:
            editorItem.isCollapsed = true
            previewItem.isCollapsed = false
        }
        if let toolbar = view.window?.toolbar,
           let item = toolbar.items.first(where: { $0.itemIdentifier.rawValue == "toggle" }) {
            item.image = NSImage(systemSymbolName: viewMode.icon, accessibilityDescription: viewMode.label)
            item.label = viewMode.label
        }
    }

    // MARK: NSToolbarDelegate

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [NSToolbarItem.Identifier("save"), .flexibleSpace, NSToolbarItem.Identifier("toggle")]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [NSToolbarItem.Identifier("save"), NSToolbarItem.Identifier("toggle"), .flexibleSpace, .space]
    }

    func toolbar(_ toolbar: NSToolbar,
                 itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch itemIdentifier.rawValue {
        case "save":
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Save"
            item.toolTip = "Save file (⌘S)"
            item.image = NSImage(systemSymbolName: "square.and.arrow.down",
                                 accessibilityDescription: "Save")
            item.target = self
            item.action = #selector(saveCurrentFile(_:))
            return item
        case "toggle":
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = viewMode.label
            item.toolTip = "Toggle view mode"
            item.image = NSImage(systemSymbolName: viewMode.icon,
                                 accessibilityDescription: viewMode.label)
            item.target = self
            item.action = #selector(toggleViewMode(_:))
            return item
        default:
            return nil
        }
    }
}

// MARK: - Editor (left pane)

final class EditorViewController: NSViewController {
    var onTextChange: ((String) -> Void)?
    var currentURL: URL?

    private var scrollView: NSScrollView!
    private var textView: NSTextView!

    override func loadView() {
        scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        textView = NSTextView()
        textView.isEditable = true
        textView.isRichText = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.delegate = self
        textView.allowsUndo = true

        // Set colors for both light and dark mode
        textView.drawsBackground = true

        scrollView.documentView = textView
        view = scrollView
        view.frame = NSRect(x: 0, y: 0, width: 480, height: 700)
    }

    func setText(_ markdown: String) {
        textView.string = markdown
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
                win.title = "✓ Saved"
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
            self.currentURL = url
            try? self.textView.string.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

extension EditorViewController: NSTextViewDelegate {
    func textDidChange(_ notification: Notification) {
        onTextChange?(textView.string)
    }
}

// MARK: - Preview (right pane)

final class PreviewWebViewController: NSViewController, WKNavigationDelegate {
    var baseURL: URL?
    private var webView: WKWebView!

    override func loadView() {
        let config = WKWebViewConfiguration()
        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        view = webView
        view.frame = NSRect(x: 0, y: 0, width: 520, height: 700)
    }

    func render(markdown: String, baseURL: URL? = nil) {
        let resolvedBase = baseURL ?? self.baseURL
        let html = MarkdownRenderer.render(markdown: markdown, title: "Preview")
        webView.loadHTMLString(html, baseURL: resolvedBase)
    }

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if navigationAction.navigationType == .linkActivated {
            if let url = navigationAction.request.url {
                NSWorkspace.shared.open(url)
            }
            decisionHandler(.cancel)
        } else {
            decisionHandler(.allow)
        }
    }
}
