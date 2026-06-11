import AppKit
import WebKit
import QuickMarkCore

/// A floating window that renders a Markdown file using QuickMarkCore + WKWebView.
final class MarkdownPreviewWindowController: NSObject, WKNavigationDelegate {
    static let shared = MarkdownPreviewWindowController()

    private var window: NSWindow?
    private var webView: WKWebView?

    func show(url: URL) {
        if window == nil { createWindow() }
        load(url: url)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func createWindow() {
        let config = WKWebViewConfiguration()
        let wv = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), configuration: config)
        wv.navigationDelegate = self
        webView = wv

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        win.title = "QuickMark Preview"
        win.contentView = wv
        win.center()
        win.isReleasedWhenClosed = false
        window = win
    }

    private func load(url: URL) {
        guard let webView else { return }
        let markdown = (try? String(contentsOf: url, encoding: .utf8)) ?? "_Could not read file._"
        let title = url.deletingPathExtension().lastPathComponent
        let html = MarkdownRenderer.render(markdown: markdown, title: title)
        window?.title = title
        webView.loadHTMLString(html, baseURL: url.deletingLastPathComponent())
    }

    // WKNavigationDelegate: block remote navigation, open links externally
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
