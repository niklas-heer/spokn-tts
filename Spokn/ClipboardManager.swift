import AppKit
import ApplicationServices
import Carbon

/// Represents the type of content retrieved from clipboard
enum ClipboardContentType {
    case html(String, plainText: String)  // HTML content with plain text fallback
    case rtf(Data, plainText: String)  // RTF data with plain text fallback
    case markdown(String)  // Detected as Markdown
    case plainText(String)  // Plain text
    case empty

    /// Get the plain text representation for speech
    var speechText: String {
        switch self {
        case .html(_, let plainText):
            return ClipboardContentType.normalizeText(plainText)
        case .rtf(_, let plainText):
            return ClipboardContentType.normalizeText(plainText)
        case .markdown(let text):
            return ClipboardContentType.normalizeText(MarkdownHelper.stripMarkdown(text))
        case .plainText(let text):
            return ClipboardContentType.normalizeText(text)
        case .empty:
            return ""
        }
    }

    /// Get the display text (original format)
    var displayText: String {
        switch self {
        case .html(let html, _):
            return html
        case .rtf(_, let plainText):
            return plainText
        case .markdown(let text):
            return text
        case .plainText(let text):
            return text
        case .empty:
            return ""
        }
    }

    var isEmpty: Bool {
        switch self {
        case .empty:
            return true
        default:
            return speechText.isEmpty
        }
    }

    /// Normalize text for better speech and display
    /// - Collapses multiple newlines into paragraph breaks
    /// - Removes excessive whitespace
    /// - Preserves intentional paragraph structure
    private static func normalizeText(_ text: String) -> String {
        var result = text

        // Replace Windows line endings with Unix
        result = result.replacingOccurrences(of: "\r\n", with: "\n")
        result = result.replacingOccurrences(of: "\r", with: "\n")

        // Replace multiple spaces with single space
        while result.contains("  ") {
            result = result.replacingOccurrences(of: "  ", with: " ")
        }

        // Normalize multiple newlines (3+ becomes 2, preserving paragraph breaks)
        while result.contains("\n\n\n") {
            result = result.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }

        // Replace single newlines that aren't paragraph breaks with spaces
        // (common in web copy where each line is wrapped)
        // But preserve double newlines (paragraph breaks)
        let paragraphs = result.components(separatedBy: "\n\n")
        let normalizedParagraphs = paragraphs.map { paragraph -> String in
            // Within a paragraph, replace single newlines with spaces
            paragraph
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespaces)
        }
        result = normalizedParagraphs.joined(separator: "\n\n")

        // Trim leading/trailing whitespace
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)

        return result
    }
}

/// Manages clipboard access and getting selected text
struct ClipboardManager {

    /// Get the currently selected content with type detection
    /// - Returns: The clipboard content with detected type
    static func getSelectedContent() -> ClipboardContentType {
        // First, trigger copy to get selected content into clipboard
        triggerCopyToClipboard()

        // Now read from clipboard with type detection
        return readClipboardContent()
    }

    /// Get the currently selected text (legacy method for compatibility)
    /// - Returns: The selected text, or empty string if none
    static func getSelectedText() -> String {
        let content = getSelectedContent()
        return content.speechText
    }

    /// Read clipboard content with type detection
    private static func readClipboardContent() -> ClipboardContentType {
        let pasteboard = NSPasteboard.general

        // Get plain text (we'll need this for all cases)
        let plainText = pasteboard.string(forType: .string) ?? ""

        // Check for HTML content first (most common from web)
        if let htmlData = pasteboard.data(forType: .html),
            let htmlString = String(data: htmlData, encoding: .utf8),
            !htmlString.isEmpty
        {
            print("[Spokn] Detected HTML content")
            return .html(htmlString, plainText: plainText)
        }

        // Check for RTF content (from documents)
        if let rtfData = pasteboard.data(forType: .rtf),
            !rtfData.isEmpty
        {
            print("[Spokn] Detected RTF content")
            return .rtf(rtfData, plainText: plainText)
        }

        // Check if plain text looks like Markdown
        if !plainText.isEmpty && MarkdownHelper.containsMarkdown(plainText) {
            print("[Spokn] Detected Markdown content")
            return .markdown(plainText)
        }

        // Default to plain text
        if !plainText.isEmpty {
            print("[Spokn] Plain text content")
            return .plainText(plainText)
        }

        return .empty
    }

    /// Trigger copy to get selected content into clipboard
    private static func triggerCopyToClipboard() {
        // Method 1: Try to get selected text via Accessibility API
        if let text = getSelectedTextViaAccessibility(), !text.isEmpty {
            print(
                "[Spokn] Got text via Accessibility API: '\(text.prefix(50))...' (length: \(text.count))"
            )
            // Put it in clipboard so we can read other formats
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            return
        }

        // Method 2: Fall back to simulating Cmd+C
        print("[Spokn] Accessibility API failed, trying Cmd+C simulation")
        simulateCopyAndWait()
    }

    /// Get selected text using the Accessibility API
    private static func getSelectedTextViaAccessibility() -> String? {
        // Get the frontmost application
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            print("[Spokn] No frontmost application")
            return nil
        }

        let pid = frontApp.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)

        // Get the focused element
        var focusedElement: CFTypeRef?
        let focusResult = AXUIElementCopyAttributeValue(
            appElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)

        guard focusResult == .success, let focused = focusedElement else {
            print("[Spokn] Could not get focused element: \(focusResult.rawValue)")
            return nil
        }

        // Try to get selected text from the focused element
        var selectedText: CFTypeRef?
        let textResult = AXUIElementCopyAttributeValue(
            focused as! AXUIElement, kAXSelectedTextAttribute as CFString, &selectedText)

        if textResult == .success, let text = selectedText as? String, !text.isEmpty {
            return text
        }

        print("[Spokn] Could not get selected text attribute: \(textResult.rawValue)")
        return nil
    }

    /// Simulate Cmd+C and wait for clipboard to update
    private static func simulateCopyAndWait() {
        let pasteboard = NSPasteboard.general
        let initialChangeCount = pasteboard.changeCount

        // Simulate Cmd+C to copy selected text
        simulateCopy()

        // Wait for clipboard to change (with timeout)
        let startTime = Date()
        let timeout: TimeInterval = 0.3  // 300ms timeout

        while Date().timeIntervalSince(startTime) < timeout {
            if pasteboard.changeCount != initialChangeCount {
                // Clipboard changed
                print("[Spokn] Clipboard updated via Cmd+C")
                return
            }
            usleep(20000)  // 20ms
        }

        print("[Spokn] Cmd+C timeout - clipboard may not have updated")
    }

    /// Simulate pressing Cmd+C
    private static func simulateCopy() {
        // Create event source
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            print("[Spokn] Failed to create event source")
            return
        }

        // Create key down event for 'C' (keycode 0x08)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: true)
        else {
            print("[Spokn] Failed to create key down event")
            return
        }
        keyDown.flags = .maskCommand

        // Create key up event
        guard let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: false)
        else {
            print("[Spokn] Failed to create key up event")
            return
        }
        keyUp.flags = .maskCommand

        // Post events
        keyDown.post(tap: .cgSessionEventTap)
        usleep(20000)  // 20ms delay
        keyUp.post(tap: .cgSessionEventTap)

        print("[Spokn] Simulated Cmd+C")
    }
}
