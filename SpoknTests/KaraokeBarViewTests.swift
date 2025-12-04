import SwiftUI
import XCTest

@testable import Spokn

final class KaraokeBarViewTests: XCTestCase {

    // MARK: - Word Parsing Tests

    func testWordParsingSimpleSentence() {
        let sentence = "Hello world test"
        let words = parseWords(from: sentence)
        XCTAssertEqual(words.count, 3)
        XCTAssertEqual(words[0], "Hello")
        XCTAssertEqual(words[1], "world")
        XCTAssertEqual(words[2], "test")
    }

    func testWordParsingWithMultipleSpaces() {
        let sentence = "Hello   world"
        let words = parseWords(from: sentence)
        XCTAssertEqual(words.count, 2)
        XCTAssertEqual(words[0], "Hello")
        XCTAssertEqual(words[1], "world")
    }

    func testWordParsingEmptyString() {
        let sentence = ""
        let words = parseWords(from: sentence)
        XCTAssertEqual(words.count, 0)
    }

    func testWordParsingSingleWord() {
        let sentence = "Hello"
        let words = parseWords(from: sentence)
        XCTAssertEqual(words.count, 1)
        XCTAssertEqual(words[0], "Hello")
    }

    func testWordParsingWithPunctuation() {
        let sentence = "Hello, world!"
        let words = parseWords(from: sentence)
        XCTAssertEqual(words.count, 2)
        XCTAssertEqual(words[0], "Hello,")
        XCTAssertEqual(words[1], "world!")
    }

    // MARK: - Active Word Index Tests

    func testFindActiveWordIndexFirstWord() {
        let sentence = "Hello world test"
        let range = sentence.startIndex..<sentence.index(sentence.startIndex, offsetBy: 5)
        let index = findActiveWordIndex(sentence: sentence, range: range)
        XCTAssertEqual(index, 0)
    }

    func testFindActiveWordIndexMiddleWord() {
        let sentence = "Hello world test"
        let worldRange = sentence.range(of: "world")!
        let index = findActiveWordIndex(sentence: sentence, range: worldRange)
        XCTAssertEqual(index, 1)
    }

    func testFindActiveWordIndexLastWord() {
        let sentence = "Hello world test"
        let testRange = sentence.range(of: "test")!
        let index = findActiveWordIndex(sentence: sentence, range: testRange)
        XCTAssertEqual(index, 2)
    }

    func testFindActiveWordIndexNilRange() {
        let sentence = "Hello world"
        let index = findActiveWordIndex(sentence: sentence, range: nil)
        XCTAssertEqual(index, 0, "Should default to 0 when no range")
    }

    // MARK: - Helper methods (replicating logic from KaraokeBarView)

    private func parseWords(from sentence: String) -> [String] {
        sentence
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
    }

    private func findActiveWordIndex(sentence: String, range: Range<String.Index>?) -> Int {
        guard let range = range else { return 0 }

        let words = parseWords(from: sentence)
        var searchIndex = sentence.startIndex

        for (wordIndex, word) in words.enumerated() {
            while searchIndex < sentence.endIndex && sentence[searchIndex].isWhitespace {
                searchIndex = sentence.index(after: searchIndex)
            }

            guard searchIndex < sentence.endIndex else { return 0 }

            let wordEndIndex =
                sentence.index(searchIndex, offsetBy: word.count, limitedBy: sentence.endIndex)
                ?? sentence.endIndex
            let wordRange = searchIndex..<wordEndIndex

            if wordRange.overlaps(range)
                || (range.lowerBound >= searchIndex && range.lowerBound < wordEndIndex)
            {
                return wordIndex
            }

            searchIndex = wordEndIndex
        }

        return 0
    }
}
