import Cocoa
import Quartz
import WebKit
import QuickMarkCore

class PreviewViewController: NSViewController, QLPreviewingController {

    private var webView: WKWebView!
    private var currentDirectory: URL?
    private static let resources = Bundle(for: PreviewViewController.self)

    override func loadView() {
        let config = WKWebViewConfiguration()
        // Disable all URL scheme handlers to prevent any remote loading
        let prefs = WKPreferences()
        prefs.javaScriptCanOpenWindowsAutomatically = false
        config.preferences = prefs
        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.setAccessibilityLabel(String(localized: "Rendered Markdown", bundle: Self.resources))
        view = webView
    }

    func preparePreviewOfFile(at url: URL) async throws {
        let title = url.deletingPathExtension().lastPathComponent
        let html: String
        do {
            let markdown = try String(contentsOf: url, encoding: .utf8)
            html = MarkdownRenderer.render(markdown: markdown, title: title)
        } catch {
            let filename = url.lastPathComponent
            let message = String(localized: "Could not read file: \(filename)", bundle: Self.resources)
            let language = Self.resources.preferredLocalizations.first ?? "en"
            html = HTMLTemplate.build(
                bodyHTML: "<p lang=\"\(Self.escapeHTML(language))\"><em>\(Self.escapeHTML(message))</em></p>",
                title: title
            )
        }
        let directory = url.deletingLastPathComponent()

        // baseURL is the file's directory so relative image paths resolve
        await MainActor.run {
            currentDirectory = directory
            webView.loadHTMLString(html, baseURL: directory)
        }
    }
    private static func escapeHTML(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
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
            } else if openLocalWikilink(navigationAction.request.url) {
                decisionHandler(.cancel)
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

    private func openLocalWikilink(_ url: URL?) -> Bool {
        guard let target = MarkdownWikilinkResolver.target(from: url) else { return false }
        guard let directory = currentDirectory,
              let linkedURL = MarkdownWikilinkResolver.resolve(target, in: directory),
              let markdown = try? String(contentsOf: linkedURL, encoding: .utf8) else {
            NSSound.beep()
            return true
        }
        let html = MarkdownRenderer.render(markdown: markdown, title: linkedURL.deletingPathExtension().lastPathComponent)
        currentDirectory = linkedURL.deletingLastPathComponent()
        webView.loadHTMLString(html, baseURL: currentDirectory)
        return true
    }
}
