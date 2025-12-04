import XCTest

@testable import Spokn

final class ClipboardContentTypeTests: XCTestCase {

    // MARK: - Speech Text Tests

    func testPlainTextSpeechText() {
        let content = ClipboardContentType.plainText("Hello world")
        XCTAssertEqual(content.speechText, "Hello world")
    }

    func testHTMLSpeechTextReturnsPlainText() {
        let content = ClipboardContentType.html("<p>Hello</p>", plainText: "Hello")
        XCTAssertEqual(content.speechText, "Hello")
    }

    func testRTFSpeechTextReturnsPlainText() {
        let rtfData = Data()
        let content = ClipboardContentType.rtf(rtfData, plainText: "Hello RTF")
        XCTAssertEqual(content.speechText, "Hello RTF")
    }

    func testMarkdownSpeechTextStripsFormatting() {
        let content = ClipboardContentType.markdown("**Bold** text")
        // Should strip markdown
        XCTAssertFalse(content.speechText.contains("**"))
        XCTAssertTrue(content.speechText.contains("Bold"))
        XCTAssertTrue(content.speechText.contains("text"))
    }

    func testEmptySpeechText() {
        let content = ClipboardContentType.empty
        XCTAssertEqual(content.speechText, "")
    }

    // MARK: - Display Text Tests

    func testPlainTextDisplayText() {
        let content = ClipboardContentType.plainText("Display me")
        XCTAssertEqual(content.displayText, "Display me")
    }

    func testHTMLDisplayTextReturnsHTML() {
        let htmlContent = "<p>HTML content</p>"
        let content = ClipboardContentType.html(htmlContent, plainText: "HTML content")
        XCTAssertEqual(content.displayText, htmlContent)
    }

    func testMarkdownDisplayTextPreservesMarkdown() {
        let mdContent = "# Header\n**Bold**"
        let content = ClipboardContentType.markdown(mdContent)
        XCTAssertEqual(content.displayText, mdContent)
    }

    func testEmptyDisplayText() {
        let content = ClipboardContentType.empty
        XCTAssertEqual(content.displayText, "")
    }

    // MARK: - isEmpty Tests

    func testEmptyIsEmpty() {
        let content = ClipboardContentType.empty
        XCTAssertTrue(content.isEmpty)
    }

    func testPlainTextIsNotEmpty() {
        let content = ClipboardContentType.plainText("Hello")
        XCTAssertFalse(content.isEmpty)
    }

    func testEmptyPlainTextIsEmpty() {
        let content = ClipboardContentType.plainText("")
        XCTAssertTrue(content.isEmpty)
    }

    func testHTMLWithContentIsNotEmpty() {
        let content = ClipboardContentType.html("<p>Hi</p>", plainText: "Hi")
        XCTAssertFalse(content.isEmpty)
    }

    func testMarkdownWithContentIsNotEmpty() {
        let content = ClipboardContentType.markdown("# Title")
        XCTAssertFalse(content.isEmpty)
    }
}
