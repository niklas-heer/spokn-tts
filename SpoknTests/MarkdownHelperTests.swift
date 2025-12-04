import XCTest

@testable import Spokn

final class MarkdownHelperTests: XCTestCase {

    // MARK: - Markdown Detection Tests (Strong Patterns - single match sufficient)

    func testDetectsBoldMarkdown() {
        let text = "This is **bold** text"
        XCTAssertTrue(
            MarkdownHelper.containsMarkdown(text), "Should detect bold markdown (strong pattern)")
    }

    func testDetectsUnderscoreBold() {
        let text = "This is __bold__ text"
        XCTAssertTrue(
            MarkdownHelper.containsMarkdown(text), "Should detect underscore bold (strong pattern)")
    }

    func testDetectsStrikethrough() {
        let text = "This is ~~strikethrough~~ text"
        XCTAssertTrue(
            MarkdownHelper.containsMarkdown(text), "Should detect strikethrough (strong pattern)")
    }

    func testDetectsHeaders() {
        let text = "# Header\nSome content"
        XCTAssertTrue(
            MarkdownHelper.containsMarkdown(text), "Should detect headers (strong pattern)")
    }

    func testDetectsLinks() {
        let text = "Check out [this link](https://example.com)"
        XCTAssertTrue(MarkdownHelper.containsMarkdown(text), "Should detect links (strong pattern)")
    }

    func testDetectsCodeBlocks() {
        let text = "```\ncode here\n```"
        XCTAssertTrue(
            MarkdownHelper.containsMarkdown(text), "Should detect code blocks (strong pattern)")
    }

    // MARK: - Markdown Detection Tests (Weak Patterns - need 2+ matches)

    func testDetectsMultipleWeakPatterns() {
        // Italic + inline code = 2 weak patterns
        let text = "This is *italic* and `code` text"
        XCTAssertTrue(
            MarkdownHelper.containsMarkdown(text), "Should detect when 2+ weak patterns present")
    }

    func testDetectsListWithCode() {
        // List + inline code = 2 weak patterns
        let text = "- Item with `code`"
        XCTAssertTrue(
            MarkdownHelper.containsMarkdown(text), "Should detect list + code as markdown")
    }

    func testSingleItalicNotDetected() {
        // Single weak pattern should NOT be detected
        let text = "This is *italic* text"
        XCTAssertFalse(
            MarkdownHelper.containsMarkdown(text),
            "Single italic should not trigger markdown detection")
    }

    func testSingleInlineCodeNotDetected() {
        // Single weak pattern should NOT be detected
        let text = "This is `code` text"
        XCTAssertFalse(
            MarkdownHelper.containsMarkdown(text),
            "Single inline code should not trigger markdown detection")
    }

    func testSingleListItemNotDetected() {
        // Single weak pattern should NOT be detected
        let text = "- Just one item"
        XCTAssertFalse(
            MarkdownHelper.containsMarkdown(text),
            "Single list item should not trigger markdown detection")
    }

    func testPlainTextNotDetectedAsMarkdown() {
        let text = "This is just plain text with no special formatting."
        XCTAssertFalse(
            MarkdownHelper.containsMarkdown(text), "Should not detect plain text as markdown")
    }

    func testConsoleLogNotDetectedAsMarkdown() {
        // Console log output should NOT be detected as markdown
        let text =
            "[Spokn] Language detected: English, starting speech\nAddInstanceForFactory: No factory registered"
        XCTAssertFalse(
            MarkdownHelper.containsMarkdown(text), "Console log should not be detected as markdown")
    }

    // MARK: - Markdown Stripping Tests

    func testStripsBold() {
        let text = "This is **bold** text"
        let stripped = MarkdownHelper.stripMarkdown(text)
        XCTAssertEqual(stripped, "This is bold text", "Should strip bold markers")
    }

    func testStripsItalic() {
        let text = "This is *italic* text"
        let stripped = MarkdownHelper.stripMarkdown(text)
        XCTAssertEqual(stripped, "This is italic text", "Should strip italic markers")
    }

    func testStripsUnderscoreBold() {
        let text = "This is __bold__ text"
        let stripped = MarkdownHelper.stripMarkdown(text)
        XCTAssertEqual(stripped, "This is bold text", "Should strip underscore bold markers")
    }

    func testStripsStrikethrough() {
        let text = "This is ~~deleted~~ text"
        let stripped = MarkdownHelper.stripMarkdown(text)
        XCTAssertEqual(stripped, "This is deleted text", "Should strip strikethrough markers")
    }

    func testStripsInlineCode() {
        let text = "Run `npm install` command"
        let stripped = MarkdownHelper.stripMarkdown(text)
        XCTAssertEqual(stripped, "Run npm install command", "Should strip inline code markers")
    }

    func testStripsHeaders() {
        let text = "# Header\nContent here"
        let stripped = MarkdownHelper.stripMarkdown(text)
        XCTAssertTrue(stripped.contains("Header"), "Should preserve header text")
        XCTAssertFalse(stripped.contains("#"), "Should remove # symbol")
    }

    func testStripsLinks() {
        let text = "Check [this link](https://example.com) out"
        let stripped = MarkdownHelper.stripMarkdown(text)
        XCTAssertEqual(stripped, "Check this link out", "Should strip link markdown, keep text")
    }

    func testStripsListMarkers() {
        let text = "- Item one\n- Item two"
        let stripped = MarkdownHelper.stripMarkdown(text)
        XCTAssertTrue(stripped.contains("Item one"), "Should preserve list item text")
        XCTAssertTrue(stripped.contains("Item two"), "Should preserve list item text")
    }

    func testStripsNumberedListMarkers() {
        let text = "1. First\n2. Second"
        let stripped = MarkdownHelper.stripMarkdown(text)
        XCTAssertTrue(stripped.contains("First"), "Should preserve numbered list text")
        XCTAssertTrue(stripped.contains("Second"), "Should preserve numbered list text")
    }

    func testPreservesPlainText() {
        let text = "This is plain text."
        let stripped = MarkdownHelper.stripMarkdown(text)
        XCTAssertEqual(stripped, text, "Should preserve plain text unchanged")
    }

    func testStripsMultipleFormattingTypes() {
        let text = "**Bold** and *italic* and `code`"
        let stripped = MarkdownHelper.stripMarkdown(text)
        XCTAssertEqual(stripped, "Bold and italic and code", "Should strip all formatting")
    }
}
