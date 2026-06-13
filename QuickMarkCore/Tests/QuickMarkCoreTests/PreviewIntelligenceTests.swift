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
}
