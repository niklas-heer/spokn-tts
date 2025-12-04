import SwiftUI

/// A karaoke-style bar where text flows horizontally and the active word stays centered
struct KaraokeBarView: View {
    let sentence: String
    let currentWordRange: Range<String.Index>?

    private let highlightColor = Color(red: 0.4, green: 0.6, blue: 1.0)

    var body: some View {
        GeometryReader { geometry in
            let viewWidth = geometry.size.width
            let viewCenter = viewWidth / 2
            let wordsArray = parseWords()
            let activeIdx = findActiveWordIndex(in: wordsArray)
            let xOffset = computeOffset(
                words: wordsArray, activeIndex: activeIdx, centerX: viewCenter)

            // Single horizontal line of words - no wrapping
            HStack(spacing: 5) {
                ForEach(Array(wordsArray.enumerated()), id: \.offset) { index, word in
                    WordChip(
                        text: word,
                        isActive: index == activeIdx,
                        highlightColor: highlightColor
                    )
                }
            }
            .fixedSize(horizontal: true, vertical: false)  // Prevent wrapping - always single line
            .frame(height: geometry.size.height)
            .offset(x: xOffset)
            .animation(.easeOut(duration: 0.15), value: activeIdx)
        }
        .frame(height: 48)
        .background(Color.black.opacity(0.4))
        .clipped()  // Clip overflow on sides
    }

    // MARK: - Word Parsing

    private func parseWords() -> [String] {
        // Split by whitespace, filter empty
        sentence
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
    }

    private func findActiveWordIndex(in words: [String]) -> Int {
        guard let range = currentWordRange else { return 0 }

        // Walk through the sentence to find which word index contains our range
        var searchIndex = sentence.startIndex

        for (wordIndex, word) in words.enumerated() {
            // Skip whitespace
            while searchIndex < sentence.endIndex && sentence[searchIndex].isWhitespace {
                searchIndex = sentence.index(after: searchIndex)
            }

            guard searchIndex < sentence.endIndex else { return 0 }

            // Calculate end of this word
            let wordEndIndex =
                sentence.index(searchIndex, offsetBy: word.count, limitedBy: sentence.endIndex)
                ?? sentence.endIndex

            // Check if the active range overlaps with this word
            let wordRange = searchIndex..<wordEndIndex
            if wordRange.overlaps(range)
                || range.lowerBound >= searchIndex && range.lowerBound < wordEndIndex
            {
                return wordIndex
            }

            // Move to next word
            searchIndex = wordEndIndex
        }

        return 0
    }

    private func computeOffset(words: [String], activeIndex: Int, centerX: CGFloat) -> CGFloat {
        // Calculate where each word would be positioned
        // and determine offset to center the active word

        let spacing: CGFloat = 5
        var positions: [CGFloat] = []  // Center X of each word
        var currentX: CGFloat = 0

        for word in words {
            let wordWidth = measureWord(word)
            let wordCenterX = currentX + wordWidth / 2
            positions.append(wordCenterX)
            currentX += wordWidth + spacing
        }

        guard activeIndex < positions.count else { return 0 }

        let activeWordCenterX = positions[activeIndex]
        return centerX - activeWordCenterX
    }

    private func measureWord(_ word: String) -> CGFloat {
        // More accurate measurement using NSString
        let font = NSFont.systemFont(ofSize: 17, weight: .regular)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let size = (word as NSString).size(withAttributes: attributes)
        // Add padding (6 horizontal padding on each side = 12 total)
        return size.width + 14
    }
}

/// Individual word chip with highlight
private struct WordChip: View {
    let text: String
    let isActive: Bool
    let highlightColor: Color

    var body: some View {
        Text(text)
            .font(.system(size: 17, weight: isActive ? .semibold : .regular))
            .foregroundColor(isActive ? .white : .white.opacity(0.5))
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isActive ? highlightColor : Color.clear)
            )
            .lineLimit(1)  // Never wrap
    }
}

// MARK: - Preview

#Preview("Karaoke Bar Tests") {
    VStack(spacing: 30) {
        Group {
            Text("No active word:").foregroundColor(.white)
            KaraokeBarView(
                sentence: "This is a test sentence with several words",
                currentWordRange: nil
            )
        }

        Group {
            Text("Active word 'test':").foregroundColor(.white)
            let s = "This is a test sentence with several words"
            let r = s.range(of: "test")!
            KaraokeBarView(sentence: s, currentWordRange: r)
        }

        Group {
            Text("Active word 'sentence':").foregroundColor(.white)
            let s = "This is a test sentence with several words"
            let r = s.range(of: "sentence")!
            KaraokeBarView(sentence: s, currentWordRange: r)
        }

        Group {
            Text("Active word 'words' (last):").foregroundColor(.white)
            let s = "This is a test sentence with several words"
            let r = s.range(of: "words")!
            KaraokeBarView(sentence: s, currentWordRange: r)
        }
    }
    .padding()
    .frame(width: 500)
    .background(Color(white: 0.12))
}
