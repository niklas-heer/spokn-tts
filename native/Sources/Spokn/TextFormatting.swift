import AppKit

/// Convert textual markup once, before tokenizing. Display, seeking and speech then
/// share the same rendered UTF-16 string, including list markers and paragraph breaks.
enum TextFormatting {
    static func prepare(_ source: NSAttributedString) -> NSAttributedString {
        guard source.length > 0 else { return source }
        let text = source.string
        // Preserve formatting already supplied by a browser, editor, or accessibility.
        var styled = false
        var firstFont: NSFont?
        source.enumerateAttributes(in: NSRange(location: 0, length: source.length)) { attributes, _, _ in
            if attributes[.link] != nil || attributes[.attachment] != nil { styled = true }
            if let paragraph = attributes[.paragraphStyle] as? NSParagraphStyle, !paragraph.textLists.isEmpty { styled = true }
            if let font = attributes[.font] as? NSFont {
                if let firstFont, firstFont != font { styled = true }
                firstFont = firstFont ?? font
                if !NSFontManager.shared.traits(of: font).intersection([.boldFontMask, .italicFontMask]).isEmpty { styled = true }
            }
        }
        if styled { return source }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{\\rtf"), let data = trimmed.data(using: .utf8),
           let rich = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil) { return rich }
        if trimmed.range(of: #"(?is)^<(?:!doctype\s+html|html|p|div|h[1-6]|ul|ol|blockquote|pre|table)\b"#, options: .regularExpression) != nil,
           let rich = MacIntegration.richHTML(Data(trimmed.utf8)), rich.length > 0 { return rich }
        return markdown(text) ?? source
    }

    static func markdown(_ text: String) -> NSAttributedString? {
        guard let parsed = try? AttributedString(markdown: text, options: .init(interpretedSyntax: .full, failurePolicy: .throwError)) else { return nil }
        let hasMarkup = parsed.runs.contains { run in
            if let inline = run.inlinePresentationIntent,
               !inline.intersection([.stronglyEmphasized, .emphasized, .code, .strikethrough]).isEmpty { return true }
            if run.link != nil || run.imageURL != nil { return true }
            return run.presentationIntent?.components.contains { component in
                if case .paragraph = component.kind { return false }
                return true
            } ?? false
        }
        // Ordinary prose keeps its exact line breaks, whitespace and punctuation.
        guard hasMarkup else { return nil }
        let result = NSMutableAttributedString()
        var previousBlock: Int?
        var previousRow: Int?
        var listedItems: Set<Int> = []
        for run in parsed.runs {
            let components = run.presentationIntent?.components ?? []
            let block = components.first?.identity
            var font = NSFont.systemFont(ofSize: 14)
            let paragraph = NSMutableParagraphStyle()
            paragraph.paragraphSpacing = 10
            var listItem: (id: Int, ordinal: Int)?
            var ordered = false
            var depth = 0
            var row: Int?
            for component in components {
                switch component.kind {
                case .header(let level): font = .systemFont(ofSize: CGFloat(max(16, 24 - level * 2)), weight: .bold)
                case .codeBlock: font = .monospacedSystemFont(ofSize: 13, weight: .regular)
                case .blockQuote: paragraph.headIndent += 18; paragraph.firstLineHeadIndent += 18
                case .listItem(let ordinal): if listItem == nil { listItem = (component.identity, ordinal) }
                case .orderedList: if depth == 0 { ordered = true }; depth += 1
                case .unorderedList: depth += 1
                case .tableRow, .tableHeaderRow: row = component.identity
                default: break
                }
            }
            if result.length > 0, block != previousBlock {
                result.append(NSAttributedString(string: row != nil && row == previousRow ? "\t" : "\n"))
            }
            if let listItem {
                paragraph.firstLineHeadIndent = CGFloat(max(0, depth - 1)) * 16
                paragraph.headIndent = paragraph.firstLineHeadIndent + 22
                paragraph.tabStops = [NSTextTab(textAlignment: .left, location: paragraph.headIndent)]
                if listedItems.insert(listItem.id).inserted {
                    result.append(NSAttributedString(string: ordered ? "\(listItem.ordinal).\t" : "•\t", attributes: [.font: font, .paragraphStyle: paragraph]))
                }
            }
            var attributes: [NSAttributedString.Key: Any] = [.paragraphStyle: paragraph]
            if let inline = run.inlinePresentationIntent {
                if inline.contains(.code) { font = .monospacedSystemFont(ofSize: 13, weight: .regular) }
                if inline.contains(.stronglyEmphasized) { font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) }
                if inline.contains(.emphasized) { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
                if inline.contains(.strikethrough) { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            }
            attributes[.font] = font
            if let link = run.link, ["http", "https", "mailto"].contains(link.scheme?.lowercased() ?? "") { attributes[.link] = link }
            result.append(NSAttributedString(string: String(parsed[run.range].characters), attributes: attributes))
            previousBlock = block; previousRow = row
        }
        return result.length > 0 ? result : nil
    }
}
