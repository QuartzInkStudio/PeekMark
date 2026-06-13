import Foundation

struct PreviewIntelligence {
    let markdownBody: String

    private let frontmatter: Frontmatter

    init(markdown: String) {
        let parsed = Frontmatter.parse(markdown)
        self.markdownBody = Self.renderWikilinks(in: parsed.body)
        self.frontmatter = parsed.frontmatter
    }

    func enhance(bodyHTML: String) -> String {
        let headings = Headings.addAnchors(to: bodyHTML)
        return frontmatter.html + headings.tocHTML + headings.html
    }

    private static func renderWikilinks(in markdown: String) -> String {
        var renderedLines: [String] = []
        renderedLines.reserveCapacity(markdown.split(separator: "\n", omittingEmptySubsequences: false).count)
        var isInFence = false

        for rawLine in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                isInFence.toggle()
                renderedLines.append(line)
            } else if isInFence {
                renderedLines.append(line)
            } else {
                renderedLines.append(replaceWikilinks(in: line))
            }
        }
        return renderedLines.joined(separator: "\n")
    }

    private static func replaceWikilinks(in line: String) -> String {
        var output = ""
        var index = line.startIndex

        while let open = line[index...].range(of: "[[") {
            output += line[index..<open.lowerBound]
            guard let close = line[open.upperBound...].range(of: "]]" ) else {
                output += line[open.lowerBound...]
                return output
            }

            let rawTarget = String(line[open.upperBound..<close.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let parts = rawTarget.split(separator: "|", maxSplits: 1).map(String.init)
            let target = (parts.first ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let label = (parts.count > 1 ? parts[1] : target).trimmingCharacters(in: .whitespacesAndNewlines)

            if target.isEmpty || label.isEmpty {
                output += line[open.lowerBound..<close.upperBound]
            } else {
                output += "[\(escapeMarkdownLinkText(label))](peekmark-wikilink://\(percentEncode(target)))"
            }
            index = close.upperBound
        }

        output += line[index...]
        return output
    }

    private static func escapeMarkdownLinkText(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "]", with: "\\]")
    }

    private static func percentEncode(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) ?? text
    }
}

private struct Frontmatter {
    let fields: [Field]

    var html: String {
        let chips = fields.flatMap(\.chips)
        guard !chips.isEmpty else { return "" }
        return """
        <section class="peekmark-intelligence peekmark-frontmatter" aria-label="Markdown properties">
        <div class="peekmark-eyebrow">Markdown properties</div>
        <div class="peekmark-chip-grid">
        \(chips.joined(separator: "\n"))
        </div>
        </section>

        """
    }

    static func parse(_ markdown: String) -> (frontmatter: Frontmatter, body: String) {
        let normalized = markdown.replacingOccurrences(of: "\r\n", with: "\n")
        guard normalized.hasPrefix("---\n") || normalized == "---" else {
            return (Frontmatter(fields: []), markdown)
        }

        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard lines.first == "---" else { return (Frontmatter(fields: []), markdown) }

        var closingIndex: Int?
        for i in 1..<lines.count where lines[i].trimmingCharacters(in: .whitespaces) == "---" {
            closingIndex = i
            break
        }
        guard let closingIndex else { return (Frontmatter(fields: []), markdown) }

        let frontmatterLines = Array(lines[1..<closingIndex])
        let bodyLines = Array(lines.dropFirst(closingIndex + 1))
        return (Frontmatter(fields: parseFields(frontmatterLines)), bodyLines.joined(separator: "\n"))
    }

    private static func parseFields(_ lines: [String]) -> [Field] {
        let supportedKeys: Set<String> = [
            "type", "status", "tags", "tag", "date", "start_date", "end_date",
            "belongs_to", "related_to", "has", "url", "icon"
        ]
        var fields: [Field] = []
        var currentKey: String?
        var currentValues: [String] = []

        func flush() {
            guard let key = currentKey, supportedKeys.contains(key), !currentValues.isEmpty else {
                currentKey = nil
                currentValues = []
                return
            }
            fields.append(Field(key: key, values: currentValues))
            currentKey = nil
            currentValues = []
        }

        for line in lines {
            if line.hasPrefix("  - ") {
                currentValues.append(clean(String(line.dropFirst(4))))
                continue
            }
            if line.hasPrefix("- ") {
                currentValues.append(clean(String(line.dropFirst(2))))
                continue
            }

            guard let colon = line.firstIndex(of: ":") else { continue }
            flush()
            let key = String(line[..<colon]).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            currentKey = key

            if value.hasPrefix("[") && value.hasSuffix("]") {
                currentValues = value.dropFirst().dropLast().split(separator: ",").map { clean(String($0)) }.filter { !$0.isEmpty }
            } else if !value.isEmpty {
                currentValues = [clean(value)]
            }
        }
        flush()

        return fields
    }

    private static func clean(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
    }

    struct Field {
        let key: String
        let values: [String]

        var chips: [String] {
            values.filter { !$0.isEmpty }.map { value in
                let cssKey = htmlEscape(key.replacingOccurrences(of: "_", with: "-"))
                return "<span class=\"peekmark-chip peekmark-chip-\(cssKey)\"><span class=\"peekmark-chip-key\">\(htmlEscape(label))</span><span class=\"peekmark-chip-value\">\(htmlEscape(value))</span></span>"
            }
        }

        private var label: String {
            switch key {
            case "start_date": return "Start"
            case "end_date": return "End"
            case "belongs_to": return "Belongs to"
            case "related_to": return "Related to"
            default:
                return key.replacingOccurrences(of: "_", with: " ").capitalized
            }
        }
    }
}

private enum Headings {
    struct Result {
        let html: String
        let tocHTML: String
    }

    static func addAnchors(to html: String) -> Result {
        let pattern = #"<h([1-6])>(.*?)</h\1>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return Result(html: html, tocHTML: "")
        }

        let nsHTML = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: nsHTML.length))
        guard !matches.isEmpty else { return Result(html: html, tocHTML: "") }

        var headings: [(level: Int, id: String, text: String, range: NSRange, innerHTML: String)] = []
        var usedIDs: [String: Int] = [:]
        var enhanced = html

        for match in matches {
            let level = Int(nsHTML.substring(with: match.range(at: 1))) ?? 1
            let innerHTML = nsHTML.substring(with: match.range(at: 2))
            let text = plainText(fromHTML: innerHTML)
            let id = uniqueID(for: text, usedIDs: &usedIDs)
            headings.append((level, id, text, match.range, innerHTML))
        }

        for heading in headings.reversed() {
            let replacement = "<h\(heading.level) id=\"\(htmlEscape(heading.id))\"><a class=\"peekmark-heading-anchor\" href=\"#\(htmlEscape(heading.id))\" aria-label=\"Link to this heading\">#</a>\(heading.innerHTML)</h\(heading.level)>"
            if let range = Range(heading.range, in: enhanced) {
                enhanced.replaceSubrange(range, with: replacement)
            }
        }

        return Result(html: enhanced, tocHTML: tocHTML(for: headings.map { ($0.level, $0.id, $0.text) }))
    }

    private static func tocHTML(for headings: [(level: Int, id: String, text: String)]) -> String {
        guard headings.count >= 2 else { return "" }
        let items = headings.map { heading in
            "<a class=\"peekmark-toc-link peekmark-toc-level-\(heading.level)\" href=\"#\(htmlEscape(heading.id))\">\(htmlEscape(heading.text))</a>"
        }.joined(separator: "\n")
        return """
        <nav class="peekmark-intelligence peekmark-toc" aria-label="Table of contents">
        <div class="peekmark-eyebrow">On this page</div>
        <div class="peekmark-toc-list">
        \(items)
        </div>
        </nav>

        """
    }

    private static func uniqueID(for text: String, usedIDs: inout [String: Int]) -> String {
        let base = slug(for: text)
        let count = usedIDs[base, default: 0]
        usedIDs[base] = count + 1
        return count == 0 ? base : "\(base)-\(count + 1)"
    }

    private static func slug(for text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).lowercased()
        let scalars = folded.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : "-"
        }
        let collapsed = String(scalars).split(separator: "-").joined(separator: "-")
        return collapsed.isEmpty ? "section" : collapsed
    }

    private static func plainText(fromHTML html: String) -> String {
        html.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private func htmlEscape(_ s: String) -> String {
    s.replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
        .replacingOccurrences(of: "\"", with: "&quot;")
        .replacingOccurrences(of: "'", with: "&#39;")
}
