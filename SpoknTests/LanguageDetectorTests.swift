import XCTest

@testable import Spokn

final class LanguageDetectorTests: XCTestCase {

    func testDetectsEnglishText() {
        let englishText = "Hello, how are you doing today? The weather is nice."
        let result = LanguageDetector.detect(text: englishText)
        XCTAssertEqual(result, .english, "Should detect English text")
    }

    func testDetectsGermanText() {
        let germanText = "Guten Tag, wie geht es Ihnen? Das Wetter ist schön heute."
        let result = LanguageDetector.detect(text: germanText)
        XCTAssertEqual(result, .german, "Should detect German text")
    }

    func testDefaultsToEnglishForShortText() {
        let shortText = "Hi"
        let result = LanguageDetector.detect(text: shortText)
        XCTAssertEqual(result, .english, "Should default to English for short/ambiguous text")
    }

    func testDefaultsToEnglishForEmptyText() {
        let emptyText = ""
        let result = LanguageDetector.detect(text: emptyText)
        XCTAssertEqual(result, .english, "Should default to English for empty text")
    }

    func testDetectsGermanWithUmlauts() {
        let germanWithUmlauts = "Ich möchte einen Kaffee trinken. Können Sie mir helfen?"
        let result = LanguageDetector.detect(text: germanWithUmlauts)
        XCTAssertEqual(result, .german, "Should detect German text with umlauts")
    }

    func testLanguageDisplayNames() {
        XCTAssertEqual(LanguageDetector.Language.english.displayName, "English")
        XCTAssertEqual(LanguageDetector.Language.german.displayName, "German")
    }

    func testLanguageFlags() {
        XCTAssertEqual(LanguageDetector.Language.english.flag, "🇬🇧")
        XCTAssertEqual(LanguageDetector.Language.german.flag, "🇩🇪")
    }

    func testLanguageRawValues() {
        XCTAssertEqual(LanguageDetector.Language.english.rawValue, "en")
        XCTAssertEqual(LanguageDetector.Language.german.rawValue, "de")
    }
}
