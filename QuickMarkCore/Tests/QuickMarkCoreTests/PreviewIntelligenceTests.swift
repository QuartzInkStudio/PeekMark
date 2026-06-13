import XCTest
@testable import QuickMarkCore

final class PreviewIntelligenceTests: XCTestCase {
    func testRendersFrontmatterChipsTOCAndWikilinks() {
        let html = MarkdownRenderer.render(markdown: """
        ---
        type: Project
        status: Active
        tags: [markdown, preview]
        related_to:
          - "[[Rendering Notes]]"
        ---
        # Alpha

        See [[Rendering Notes|the renderer]].

        ## Details

        More text.
        """, title: "Alpha")

        XCTAssertTrue(html.contains("peekmark-frontmatter"))
        XCTAssertTrue(html.contains("peekmark-chip-type"))
        XCTAssertTrue(html.contains("Project"))
        XCTAssertTrue(html.contains("peekmark-toc"))
        XCTAssertTrue(html.contains("href=\"#alpha\""))
        XCTAssertTrue(html.contains("href=\"#details\""))
        XCTAssertTrue(html.contains("peekmark-wikilink://Rendering%20Notes"))
        XCTAssertFalse(html.contains("<h1>Alpha</h1>"))
    }

    func testDoesNotRenderWikilinksInsideFencedCode() {
        let html = MarkdownRenderer.render(markdown: """
        ```markdown
        [[Do Not Link]]
        ```
        """)

        XCTAssertFalse(html.contains("peekmark-wikilink://Do%20Not%20Link"))
        XCTAssertTrue(html.contains("[[Do Not Link]]"))
    }

    func testResolvesSameDirectoryWikilinkCandidates() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let target = directory.appendingPathComponent("rendering-notes.md")
        try "# Rendering Notes".write(to: target, atomically: true, encoding: .utf8)

        XCTAssertEqual(
            MarkdownWikilinkResolver.resolve("Rendering Notes", in: directory)?.lastPathComponent,
            "rendering-notes.md"
        )
        XCTAssertNil(MarkdownWikilinkResolver.resolve("Missing Note", in: directory))
    }

    func testExtractsWikilinkTargetFromURL() {
        let url = URL(string: "peekmark-wikilink://Rendering%20Notes")
        XCTAssertEqual(MarkdownWikilinkResolver.target(from: url), "Rendering Notes")
    }

    func testIncludesBundledMermaidRenderingForMermaidFences() {
        let html = MarkdownRenderer.render(markdown: """
        ```mermaid
        flowchart TD
          A[Markdown] --> B[Preview]
        ```
        """)

        XCTAssertTrue(html.contains("language-mermaid"))
        XCTAssertTrue(html.contains("flowchart TD"))
        XCTAssertTrue(html.contains("peekmark-mermaid"))
        XCTAssertTrue(html.contains("mermaid.initialize"))
        XCTAssertFalse(html.contains("{{MERMAID_JS}}"))
        XCTAssertFalse(html.contains("https://cdn"))
    }
}
