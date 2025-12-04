import MarkdownUI
import NaturalLanguage
import SwiftUI

/// A view that displays content and scrolls to follow speech progress
struct DimmingContentView: View {
    let content: ClipboardContentType
    let speechText: String
    let currentSentence: String
    let currentSentenceRange: Range<String.Index>?
    let speechProgress: Double

    var body: some View {
        switch content {
        case .markdown(let text):
            // For markdown, use MarkdownUI with progress-based scrolling
            MarkdownScrollView(
                markdownText: text,
                speechText: speechText,
                progress: speechProgress
            )

        case .html(_, let plainText), .rtf(_, let plainText), .plainText(let plainText):
            // For plain text, show sentences and highlight current one
            ScrollViewReader { proxy in
                ScrollView {
                    SentenceListView(
                        text: speechText.isEmpty ? plainText : speechText,
                        currentSentence: currentSentence
                    )
                    .padding()
                }
                .onChange(of: currentSentence) { oldValue, newValue in
                    if !newValue.isEmpty && newValue != oldValue {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo("activeSentence", anchor: .center)
                        }
                    }
                }
            }

        case .empty:
            Text("No content")
                .foregroundColor(.white.opacity(0.5))
        }
    }
}

/// Shows markdown content with MarkdownUI and progress-based scrolling
struct MarkdownScrollView: View {
    let markdownText: String
    let speechText: String
    let progress: Double

    @State private var contentHeight: CGFloat = 0
    @State private var viewportHeight: CGFloat = 0

    var body: some View {
        GeometryReader { outerGeometry in
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Markdown(markdownText)
                            .markdownTheme(.speakToMe)
                            .textSelection(.enabled)
                            .background(
                                GeometryReader { innerGeometry in
                                    Color.clear.preference(
                                        key: ContentHeightKey.self,
                                        value: innerGeometry.size.height
                                    )
                                }
                            )

                        // Invisible anchor at the bottom for scrolling
                        Color.clear
                            .frame(height: 1)
                            .id("bottom")
                    }
                    .padding()
                }
                .onPreferenceChange(ContentHeightKey.self) { height in
                    contentHeight = height
                }
                .onChange(of: progress) { _, newProgress in
                    // Scroll based on speech progress
                    scrollToProgress(
                        newProgress, proxy: proxy, viewportHeight: outerGeometry.size.height)
                }
            }
            .onAppear {
                viewportHeight = outerGeometry.size.height
            }
        }
    }

    private func scrollToProgress(
        _ progress: Double, proxy: ScrollViewProxy, viewportHeight: CGFloat
    ) {
        // Calculate approximate scroll position based on progress
        // We want to keep the "current" position roughly centered
        guard contentHeight > viewportHeight else { return }

        // Only scroll if we have meaningful progress
        guard progress > 0.05 else { return }

        // Scroll smoothly towards the bottom as progress increases
        withAnimation(.easeInOut(duration: 0.3)) {
            if progress > 0.95 {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }
}

/// Preference key for tracking content height
private struct ContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Shows text as a list of sentences with the current one highlighted
struct SentenceListView: View {
    let text: String
    let currentSentence: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(sentences.enumerated()), id: \.offset) { index, sentence in
                let isActive =
                    sentence.trimmingCharacters(in: .whitespacesAndNewlines)
                    == currentSentence.trimmingCharacters(in: .whitespacesAndNewlines)

                Text(sentence)
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(isActive ? 1.0 : 0.85))
                    .padding(.vertical, 4)
                    .padding(.horizontal, isActive ? 8 : 0)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isActive ? Color.white.opacity(0.15) : Color.clear)
                    )
                    .id(isActive ? "activeSentence" : "sentence-\(index)")
            }
        }
    }

    private var sentences: [String] {
        var result: [String] = []

        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text

        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let sentenceText = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentenceText.isEmpty {
                result.append(sentenceText)
            }
            return true
        }

        if result.isEmpty && !text.isEmpty {
            result.append(text)
        }

        return result
    }
}

// MARK: - Markdown Theme

extension MarkdownUI.Theme {
    static let speakToMe = Theme()
        .text {
            ForegroundColor(.white.opacity(0.9))
            FontSize(16)
        }
        .code {
            FontFamilyVariant(.monospaced)
            FontSize(14)
            ForegroundColor(.white.opacity(0.85))
            BackgroundColor(.white.opacity(0.1))
        }
        .strong {
            FontWeight(.bold)
        }
        .emphasis {
            FontStyle(.italic)
        }
        .heading1 { configuration in
            configuration.label
                .markdownTextStyle {
                    FontWeight(.bold)
                    FontSize(28)
                    ForegroundColor(.white)
                }
                .markdownMargin(top: 24, bottom: 16)
        }
        .heading2 { configuration in
            configuration.label
                .markdownTextStyle {
                    FontWeight(.bold)
                    FontSize(24)
                    ForegroundColor(.white)
                }
                .markdownMargin(top: 20, bottom: 12)
        }
        .heading3 { configuration in
            configuration.label
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(20)
                    ForegroundColor(.white)
                }
                .markdownMargin(top: 16, bottom: 8)
        }
        .paragraph { configuration in
            configuration.label
                .markdownMargin(top: 0, bottom: 8)
        }
        .blockquote { configuration in
            HStack(spacing: 0) {
                Rectangle()
                    .fill(Color.white.opacity(0.3))
                    .frame(width: 3)
                configuration.label
                    .markdownTextStyle {
                        ForegroundColor(.white.opacity(0.7))
                        FontStyle(.italic)
                    }
                    .padding(.leading, 12)
            }
            .markdownMargin(top: 8, bottom: 8)
        }
        .codeBlock { configuration in
            configuration.label
                .markdownTextStyle {
                    FontFamilyVariant(.monospaced)
                    FontSize(13)
                    ForegroundColor(.white.opacity(0.85))
                }
                .padding(12)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .markdownMargin(top: 8, bottom: 8)
        }
        .listItem { configuration in
            configuration.label
                .markdownMargin(top: 4, bottom: 4)
        }
        .link {
            ForegroundColor(Color(red: 0.5, green: 0.8, blue: 1.0))
        }
}
