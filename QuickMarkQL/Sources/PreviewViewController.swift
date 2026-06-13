import Cocoa
import Quartz
import WebKit
import QuickMarkCore

class PreviewViewController: NSViewController, QLPreviewingController {

    private var webView: WKWebView!

    override func loadView() {
        let config = WKWebViewConfiguration()
        // Disable all URL scheme handlers to prevent any remote loading
        let prefs = WKPreferences()
        prefs.javaScriptCanOpenWindowsAutomatically = false
        config.preferences = prefs
        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        view = webView
    }

    func preparePreviewOfFile(at url: URL) async throws {
        let markdown: String
        do {
            markdown = try String(contentsOf: url, encoding: .utf8)
        } catch {
            markdown = "_Could not read file: \(url.lastPathComponent)_"
        }

        let title = url.deletingPathExtension().lastPathComponent
        let html = MarkdownRenderer.render(markdown: markdown, title: title)

        // baseURL is the file's directory so relative image paths resolve
        await MainActor.run {
            webView.loadHTMLString(html, baseURL: url.deletingLastPathComponent())
        }
    }
}

extension PreviewViewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // Only allow local file:// URLs — block all remote navigation
        if navigationAction.navigationType == .linkActivated {
            if Self.isLocalAnchor(navigationAction.request.url) {
                decisionHandler(.allow)
            } else {
                decisionHandler(.cancel)
            }
        } else if let url = navigationAction.request.url, url.isFileURL || url.scheme == nil {
            decisionHandler(.allow)
        } else {
            decisionHandler(.cancel)
        }
    }

    private static func isLocalAnchor(_ url: URL?) -> Bool {
        guard let url, url.fragment?.isEmpty == false else { return false }
        guard let scheme = url.scheme?.lowercased() else { return true }
        return scheme == "file" || scheme == "about"
    }
}
