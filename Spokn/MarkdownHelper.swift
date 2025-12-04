import Foundation

/// Helper for detecting and processing Markdown text
struct MarkdownHelper {

    /// Strong Markdown patterns - these clearly indicate markdown
    private static let strongMarkdownPatterns: [String] = [
        "\\*\\*[^*]+\\*\\*",  // **bold**
        "__[^_]+__",  // __bold__
        "~~[^~]+~~",  // ~~strikethrough~~
        "^#{1,6}\\s+\\S",  // # headers (must have content after)
        "\\[([^\\]]+)\\]\\(https?://[^)]+\\)",  // [link](url) - require http(s) URL
        "```",  // code blocks
    ]

    /// Weak Markdown patterns - need multiple matches to count
    private static let weakMarkdownPatterns: [String] = [
        "\\*[^*\\s][^*]*[^*\\s]\\*",  // *italic* - at least 2 non-space chars
        "_[^_\\s][^_]*[^_\\s]_",  // _italic_ - at least 2 non-space chars
        "`[^`]+`",  // `code`
        "^\\s*[-*+]\\s+\\S",  // - list items (must have content)
        "^\\s*\\d+\\.\\s+\\S",  // 1. numbered lists (must have content)
    ]

    /// Detect if text contains Markdown formatting
    /// Requires either one strong pattern match OR multiple weak pattern matches
    static func containsMarkdown(_ text: String) -> Bool {
        // Check for strong patterns - any single match is enough
        for pattern in strongMarkdownPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
            {
                let range = NSRange(text.startIndex..., in: text)
                if regex.firstMatch(in: text, options: [], range: range) != nil {
                    return true
                }
            }
        }

        // Check for weak patterns - need at least 2 different types
        var weakMatchCount = 0
        for pattern in weakMarkdownPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
            {
                let range = NSRange(text.startIndex..., in: text)
                if regex.firstMatch(in: text, options: [], range: range) != nil {
                    weakMatchCount += 1
                    if weakMatchCount >= 2 {
                        return true
                    }
                }
            }
        }

        return false
    }

    /// Strip Markdown formatting to get plain text for speech
    /// This preserves the actual words and structure but removes formatting syntax
    static func stripMarkdown(_ text: String) -> String {
        var result = text

        // Remove bold/italic markers
        result = result.replacingOccurrences(
            of: "\\*\\*([^*]+)\\*\\*", with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(
            of: "\\*([^*]+)\\*", with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(
            of: "__([^_]+)__", with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(
            of: "_([^_]+)_", with: "$1", options: .regularExpression)

        // Remove strikethrough
        result = result.replacingOccurrences(
            of: "~~([^~]+)~~", with: "$1", options: .regularExpression)

        // Remove inline code backticks
        result = result.replacingOccurrences(
            of: "`([^`]+)`", with: "$1", options: .regularExpression)

        // Remove headers (keep the text) - use NSRegularExpression for multiline
        result = replaceWithRegex(result, pattern: "^#{1,6}\\s*", replacement: "")

        // Remove link syntax, keep link text
        result = result.replacingOccurrences(
            of: "\\[([^\\]]+)\\]\\([^)]+\\)", with: "$1", options: .regularExpression)

        // Remove list markers but keep the line structure
        result = replaceWithRegex(result, pattern: "^\\s*[-*+]\\s+", replacement: "")
        result = replaceWithRegex(result, pattern: "^\\s*\\d+\\.\\s+", replacement: "")

        // Normalize multiple newlines to single newline
        result = replaceWithRegex(result, pattern: "\n{3,}", replacement: "\n\n")

        return result
    }

    /// Helper to replace using NSRegularExpression with multiline support
    private static func replaceWithRegex(_ text: String, pattern: String, replacement: String)
        -> String
    {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
        else {
            return text
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(
            in: text, options: [], range: range, withTemplate: replacement)
    }

    /// Parse text into segments with formatting information
    struct TextSegment {
        let text: String
        let isBold: Bool
        let isItalic: Bool
        let isCode: Bool
        let isStrikethrough: Bool

        var isPlain: Bool {
            !isBold && !isItalic && !isCode && !isStrikethrough
        }
    }

    /// Parse Markdown into segments (simplified version)
    static func parseSegments(_ text: String) -> [TextSegment] {
        // For now, just return plain text
        // A full implementation would parse inline formatting
        return [
            TextSegment(
                text: text, isBold: false, isItalic: false, isCode: false, isStrikethrough: false)
        ]
    }
}
