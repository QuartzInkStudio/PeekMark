import Foundation

public enum MarkdownWikilinkResolver {
    public static let scheme = "peekmark-wikilink"

    public static func target(from url: URL?) -> String? {
        guard let url, url.scheme?.lowercased() == scheme else { return nil }

        let rawTarget: String
        if let host = url.host(percentEncoded: false), !host.isEmpty {
            rawTarget = host
        } else {
            rawTarget = url.path(percentEncoded: false).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }

        let target = rawTarget.trimmingCharacters(in: .whitespacesAndNewlines)
        return target.isEmpty ? nil : target
    }

    public static func resolve(_ target: String, in directory: URL) -> URL? {
        let safeTarget = target
            .replacingOccurrences(of: "#", with: " ")
            .split(whereSeparator: { $0 == "/" || $0 == "\\" })
            .last
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !safeTarget.isEmpty else { return nil }

        let candidates = candidateFilenames(for: safeTarget)
        return candidates
            .map { directory.appendingPathComponent($0, isDirectory: false) }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    public static func candidateFilenames(for target: String) -> [String] {
        let trimmed = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let lower = trimmed.lowercased()
        var candidates: [String] = []
        if lower.hasSuffix(".md") || lower.hasSuffix(".markdown") {
            candidates.append(trimmed)
        } else {
            candidates.append(trimmed + ".md")
            candidates.append(trimmed + ".markdown")
        }

        let slug = slugFilenameStem(for: trimmed)
        if !slug.isEmpty, slug != trimmed {
            candidates.append(slug + ".md")
            candidates.append(slug + ".markdown")
        }

        var seen = Set<String>()
        return candidates.filter { seen.insert($0).inserted }
    }

    private static func slugFilenameStem(for target: String) -> String {
        let stem = (target as NSString).deletingPathExtension
        let folded = stem.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).lowercased()
        let scalars = folded.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : "-"
        }
        return String(scalars).split(separator: "-").joined(separator: "-")
    }
}
