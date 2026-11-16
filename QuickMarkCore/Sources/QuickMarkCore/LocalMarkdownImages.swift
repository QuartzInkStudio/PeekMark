import Foundation
import UniformTypeIdentifiers

enum LocalMarkdownImages {
    private static let maxImageSize = 8 * 1024 * 1024
    private static let maxTotalSize = 24 * 1024 * 1024
    private static let sources = try! NSRegularExpression(
        pattern: #"<img\b[^>]*?\ssrc\s*=\s*(["'])([^"']+)\1"#,
        options: [.caseInsensitive]
    )

    /// WKWebView cannot always load relative images for HTML strings. Embed only
    /// readable images located beneath the opened Markdown file's directory.
    static func inline(in html: String, sourceURL: URL?) -> String {
        guard let sourceURL, sourceURL.isFileURL else { return html }
        let root = sourceURL.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL
        let scanner = html as NSString
        let output = NSMutableString(string: html)
        var total = 0
        for match in sources.matches(in: html, range: NSRange(location: 0, length: scanner.length)).reversed() {
            let position = match.range(at: 2)
            let attribute = scanner.substring(with: position)
                .replacingOccurrences(of: "&amp;", with: "&")
                .replacingOccurrences(of: "&#39;", with: "'")
            guard let parts = URLComponents(string: attribute),
                  parts.scheme == nil, parts.host == nil, !parts.path.hasPrefix("/"),
                  parts.query == nil, !parts.path.isEmpty else { continue }
            let file = root.appendingPathComponent(parts.path).resolvingSymlinksInPath().standardizedFileURL
            guard file.path.hasPrefix(root.path.hasSuffix("/") ? root.path : root.path + "/"),
                  let mime = UTType(filenameExtension: file.pathExtension)?.preferredMIMEType,
                  mime.hasPrefix("image/"),
                  let attributes = try? file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                  attributes.isRegularFile == true, let size = attributes.fileSize,
                  size > 0, size <= maxImageSize, total + size <= maxTotalSize,
                  let data = try? Data(contentsOf: file, options: [.mappedIfSafe]),
                  data.count == size else { continue }
            total += size
            output.replaceCharacters(in: position, with: "data:\(mime);base64,\(data.base64EncodedString())")
        }
        return output as String
    }
}
