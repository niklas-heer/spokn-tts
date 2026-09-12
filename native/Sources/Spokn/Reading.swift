import AppKit
import NaturalLanguage

struct ReadingDocument {
    let attributedText: NSAttributedString
    let text: String
    let words: [NSRange]
    let sentences: [NSRange]
    let language: String
    var utf16Count: Int { (text as NSString).length }

    init(attributedText: NSAttributedString) {
        self.attributedText = attributedText.copy() as! NSAttributedString
        let output = attributedText.string
        text = output
        let recognizer = NLLanguageRecognizer(); recognizer.processString(output)
        language = recognizer.dominantLanguage?.rawValue ?? "en"
        func ranges(_ unit: NLTokenUnit) -> [NSRange] {
            let tokenizer = NLTokenizer(unit: unit); tokenizer.string = output
            if let detected = recognizer.dominantLanguage { tokenizer.setLanguage(detected) }
            var ranges: [NSRange] = []
            tokenizer.enumerateTokens(in: output.startIndex..<output.endIndex) { range, _ in ranges.append(NSRange(range, in: output)); return true }
            return ranges
        }
        words = ranges(.word); sentences = ranges(.sentence)
    }
    func sentence(containing word: NSRange) -> NSRange? {
        sentences.first { NSIntersectionRange($0, word).length > 0 }
    }
    func wordStart(near offset: Int) -> Int {
        words.last(where: { $0.location <= max(0, offset) })?.location ?? 0
    }
    func sentenceStart(from offset: Int, direction: Int) -> Int {
        if direction > 0 { return sentences.first(where: { $0.location > offset })?.location ?? utf16Count }
        return sentences.last(where: { $0.location < max(0, offset - 2) })?.location ?? 0
    }
}

/// Speech APIs and NSTextStorage both use UTF-16. Never mix their NSRanges with String.count.
struct SpeechCursor {
    private(set) var session: UUID?
    private(set) var base = 0
    private(set) var word: NSRange?
    private(set) var length = 0
    mutating func begin(length: Int, offset: Int) -> UUID {
        let token = UUID(); session = token; self.length = length
        base = min(max(offset, 0), length); word = nil
        return token
    }
    mutating func accept(_ range: NSRange, session token: UUID) -> NSRange? {
        guard token == session, range.location != NSNotFound, range.location >= 0, range.length > 0,
              range.location <= length - base, range.length <= length - base - range.location else { return nil }
        let mapped = NSRange(location: base + range.location, length: range.length)
        word = mapped; return mapped
    }
    mutating func invalidate() { session = nil }
    var restartOffset: Int { word?.location ?? base }
}
