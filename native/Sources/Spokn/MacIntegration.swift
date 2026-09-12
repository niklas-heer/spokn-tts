import AppKit
@preconcurrency import ApplicationServices
import Carbon

struct CapturedText {
    let content: NSAttributedString
    let source: String
}

final class MacIntegration {
    var onCapture: ((Result<CapturedText, Error>) -> Void)?
    private var captureTask: Task<Void, Never>?
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var lastExternalApplication: NSRunningApplication?
    private(set) var shortcutRegistered = false
    init() {
        rememberSource(NSWorkspace.shared.frontmostApplication)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(applicationActivated(_:)), name: NSWorkspace.didActivateApplicationNotification, object: nil)
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            // Carbon delivers application events on the main event loop.
            MainActor.assumeIsolated {
                Unmanaged<MacIntegration>.fromOpaque(context).takeUnretainedValue().capture()
            }
            return noErr
        }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler)
        let id = EventHotKeyID(signature: OSType(0x53504F4B), id: 1)
        shortcutRegistered = RegisterEventHotKey(UInt32(kVK_ANSI_S), UInt32(cmdKey | shiftKey), id, GetApplicationEventTarget(), 0, &hotKey) == noErr
    }
    isolated deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        captureTask?.cancel()
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }
    static var accessibilityEnabled: Bool { AXIsProcessTrusted() }
    @objc private func applicationActivated(_ notification: Notification) {
        rememberSource(notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)
    }
    private func rememberSource(_ application: NSRunningApplication?) {
        guard let application, application.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              application.activationPolicy == .regular else { return }
        lastExternalApplication = application
    }
    static func openAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(url) }
    }
    nonisolated struct CaptureError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
    func capture() {
        // Keep the source app in front until capture completes. Showing our panel
        // first steals the focused accessibility element and the Copy destination.
        guard captureTask == nil else { return }
        guard Self.accessibilityEnabled else {
            onCapture?(.failure(CaptureError(message: "Spokn needs permission to read your highlighted text. Click Enable Selection Access below, enable Spokn, then return to your text and press ⌘⇧S. You can also paste here with ⌘V."))); return
        }
        let frontmost = NSWorkspace.shared.frontmostApplication
        let source = frontmost?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? lastExternalApplication : frontmost
        guard let source, !source.isTerminated else { failSelection(); return }
        // Browser accessibility selections can flatten block boundaries ("end.Next")
        // even when Copy supplies faithful HTML. Keep AX as a fallback only.
        let accessibilityContent = Self.accessibilitySelection(pid: source.processIdentifier)
        captureTask = Task { [weak self] in
            defer { self?.captureTask = nil }
            do {
                // Choosing Read Selection from Spokn's menu activates Spokn.
                // Restore the remembered editor only for that explicit action.
                if NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier {
                    source.activate(options: [])
                    for _ in 0..<20 where NSWorkspace.shared.frontmostApplication?.processIdentifier != source.processIdentifier {
                        try await Task.sleep(for: .milliseconds(25))
                    }
                }
                // Do not synthesize Copy while the user is still holding ⌘⇧S.
                for _ in 0..<60 {
                    try Task.checkCancellation()
                    if NSEvent.modifierFlags.intersection([.command, .shift, .control, .option]).isEmpty { break }
                    try await Task.sleep(for: .milliseconds(25))
                }
                guard NSEvent.modifierFlags.intersection([.command, .shift, .control, .option]).isEmpty,
                      NSWorkspace.shared.frontmostApplication?.processIdentifier == source.processIdentifier else {
                    self?.failSelection(); return
                }
                let content = try await Self.copySelection(from: .general) {
                    guard NSWorkspace.shared.frontmostApplication?.processIdentifier == source.processIdentifier,
                          let eventSource = CGEventSource(stateID: .privateState),
                          let down = CGEvent(keyboardEventSource: eventSource, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: true),
                          let up = CGEvent(keyboardEventSource: eventSource, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: false) else { return }
                    down.flags = .maskCommand; up.flags = .maskCommand
                    down.postToPid(source.processIdentifier); up.postToPid(source.processIdentifier)
                }
                guard NSWorkspace.shared.frontmostApplication?.processIdentifier == source.processIdentifier,
                      let content = Self.preferredSelection(copied: content, accessibility: accessibilityContent) else { self?.failSelection(); return }
                self?.onCapture?(.success(CapturedText(content: content, source: source.localizedName ?? "Selected text")))
            } catch is CancellationError {
                // Dismissal or a newer request must never replay old clipboard text.
            } catch { self?.failSelection() }
        }
    }
    func cancelCapture() { captureTask?.cancel() }

    static func preferredSelection(copied: NSAttributedString?, accessibility: NSAttributedString?) -> NSAttributedString? {
        if let copied, !copied.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return copied }
        return accessibility
    }

    static func accessibilitySelection(pid: pid_t) -> NSAttributedString? {
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.4)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        let element = focused as! AXUIElement
        AXUIElementSetMessagingTimeout(element, 0.4)
        var value: CFTypeRef?
        var selection: CFTypeRef?
        var rich: CFTypeRef?
        var text: String?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &value) == .success {
            text = value as? String
        }
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selection) == .success,
           let selection, CFGetTypeID(selection) == AXValueGetTypeID() {
            if AXUIElementCopyParameterizedAttributeValue(element, kAXAttributedStringForRangeParameterizedAttribute as CFString, selection, &rich) == .success,
               let attributed = rich as? NSAttributedString,
               !attributed.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               text == nil || text == attributed.string { return attributed }
            // Some native editors expose the selection range but no selected-text attribute.
            var range = CFRange()
            if (text == nil || text?.isEmpty == true),
               AXValueGetValue(selection as! AXValue, .cfRange, &range),
               AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success,
               let full = value as? String {
                text = selectedSubstring(full, range: NSRange(location: range.location, length: range.length))
            }
        }
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return NSAttributedString(string: text)
    }
    static func selectedSubstring(_ text: String, range: NSRange) -> String? {
        let string = text as NSString
        guard range.location >= 0, range.length > 0, range.location <= string.length,
              range.length <= string.length - range.location else { return nil }
        return string.substring(with: range)
    }

    /// Snapshot every clipboard representation before Copy and restore it only if
    /// the clipboard still contains the result we consumed. Never read stale text.
    static func copySelection(from board: NSPasteboard, sendCopy: () -> Void) async throws -> NSAttributedString? {
        var saved: [NSPasteboardItem] = []
        var bytes = 0
        let before = board.changeCount
        for item in board.pasteboardItems ?? [] {
            let snapshot = NSPasteboardItem()
            for type in item.types {
                guard let data = item.data(forType: type) else { return nil }
                bytes += data.count
                guard bytes <= 32_000_000 else { return nil }
                snapshot.setData(data, forType: type)
            }
            saved.append(snapshot)
        }
        guard board.changeCount == before else { return nil }
        var consumed: Int?
        defer {
            if let consumed, board.changeCount == consumed {
                board.clearContents()
                if !saved.isEmpty { board.writeObjects(saved) }
            }
        }
        sendCopy()
        for _ in 0..<40 {
            try await Task.sleep(for: .milliseconds(25))
            guard board.changeCount != before else { continue }
            let changed = board.changeCount
            consumed = changed
            // Copy may publish multiple formats in successive writes.
            try await Task.sleep(for: .milliseconds(50))
            guard board.changeCount == changed else { continue }
            consumed = changed
            return clipboard(from: board)?.content
        }
        return nil
    }
    private func failSelection() {
        onCapture?(.failure(CaptureError(message: "No selected text was received. Highlight a passage in the source app and press ⌘⇧S again. You can also copy it and paste here with ⌘V.")))
    }
    static func richHTML(_ data: Data) -> NSAttributedString? {
        guard data.count <= 2_000_000, var html = String(data: data, encoding: .utf8) else { return nil }
        // Only structural markup and safe link destinations reach the importer.
        // Active/resource elements and resource-loading attributes are stripped.
        html = html.replacingOccurrences(of: #"(?is)<(script|style|head|iframe|object|svg|math)\b[^>]*>.*?</\1\s*>"#, with: "", options: .regularExpression)
        let allowed: Set<String> = ["p", "div", "br", "a", "b", "strong", "i", "em", "u", "s", "strike", "blockquote", "pre", "code", "h1", "h2", "h3", "h4", "h5", "h6", "ul", "ol", "li", "table", "tr", "td", "th"]
        let pattern = try! NSRegularExpression(pattern: #"<[^>]*>"#)
        let original = html as NSString
        let safe = NSMutableString(string: html)
        for match in pattern.matches(in: html, range: NSRange(location: 0, length: original.length)).reversed() {
            let tag = original.substring(with: match.range)
            let inner = tag.dropFirst().dropLast().trimmingCharacters(in: .whitespacesAndNewlines)
            let closing = inner.hasPrefix("/")
            let name = inner.drop(while: { $0 == "/" }).prefix(while: { $0.isLetter || $0.isNumber }).lowercased()
            var replacement = allowed.contains(name) ? "<\(closing ? "/" : "")\(name)>" : ""
            if name == "a", !closing,
               let href = tag.range(of: #"(?is)\bhref\s*=\s*(["'])(.*?)\1"#, options: .regularExpression) {
                let attribute = String(tag[href])
                if let equals = attribute.firstIndex(of: "=") {
                    let value = attribute[attribute.index(after: equals)...].trimmingCharacters(in: .whitespacesAndNewlines).dropFirst().dropLast()
                    if let scheme = URL(string: String(value))?.scheme?.lowercased(), ["https", "http", "mailto"].contains(scheme) {
                        let escaped = value.replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
                        replacement = "<a href=\"\(escaped)\">"
                    }
                }
            }
            safe.replaceCharacters(in: match.range, with: replacement)
        }
        let body = "<html><body>\(safe)</body></html>"
        return try? NSAttributedString(data: Data(body.utf8), options: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue], documentAttributes: nil)
    }

    static func clipboard(from board: NSPasteboard = .general) -> CapturedText? {
        // RTF preserves paragraphs, lists, emphasis and links without loading remote HTML resources.
        if let data = board.data(forType: .rtf), data.count <= 2_000_000,
           let rich = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil) {
            return CapturedText(content: rich, source: "Clipboard")
        }
        if let data = board.data(forType: .html), let rich = richHTML(data) {
            return CapturedText(content: rich, source: "Clipboard")
        }
        guard let plain = board.string(forType: .string) else { return nil }
        return CapturedText(content: NSAttributedString(string: plain), source: "Clipboard")
    }
}
