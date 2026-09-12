import Testing
import AppKit
@testable import Spokn

@Suite(.serialized) @MainActor struct ReadingTests {
    @Test func preservesRichTextAndUnicode() {
        let text = "Grüße 👩🏽‍💻\nDas ist schön.\n\n• Café\n• Spaß\n\nEin Gedanke."
        let rich = NSMutableAttributedString(string: text)
        let emphasis = (text as NSString).range(of: "schön")
        rich.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: 16), range: emphasis)
        let document = ReadingDocument(attributedText: rich)
        #expect(document.text == text)
        #expect(document.language == "de")
        for word in document.words { #expect(Range(word, in: text) != nil) }
        #expect(document.attributedText.attribute(.font, at: emphasis.location, effectiveRange: nil) as? NSFont == .boldSystemFont(ofSize: 16))
        rich.mutableString.setString("Changed source")
        #expect(document.text == text)
        #expect(document.attributedText.string == text)
    }
    @Test func browserClipboardPreservesEmphasisWithoutResources() throws {
        let html = "<html><head><style>body { background: url(https://example.com/pixel); }</style></head><body><h2>A thought</h2><p>Hello <b>beautiful</b> world.</p><script>alert('no')</script><img src='https://example.com/pixel'></body></html>"
        let rich = try #require(MacIntegration.richHTML(Data(html.utf8)))
        #expect(rich.string.contains("A thought"))
        #expect(rich.string.contains("Hello beautiful world."))
        #expect(!rich.string.contains("alert"))
        let bold = (rich.string as NSString).range(of: "beautiful")
        let font = try #require(rich.attribute(.font, at: bold.location, effectiveRange: nil) as? NSFont)
        #expect(NSFontManager.shared.traits(of: font).contains(.boldFontMask))
    }
    @Test func sentenceTracksWordAfterSpeedChange() {
        let text = "Hello 👩🏽‍💻. Eine schöne Welt. Noch ein Satz."
        let document = ReadingDocument(attributedText: NSAttributedString(string: text))
        let offset = (text as NSString).range(of: "schöne").location
        var cursor = SpeechCursor()
        let old = cursor.begin(length: document.utf16Count, offset: 0)
        #expect(cursor.accept(NSRange(location: offset, length: 6), session: old)?.location == offset)
        let fresh = cursor.begin(length: document.utf16Count, offset: cursor.restartOffset)
        #expect(cursor.accept(NSRange(location: 0, length: 5), session: old) == nil)
        let word = cursor.accept(NSRange(location: 0, length: 6), session: fresh)!
        #expect(word == NSRange(location: offset, length: 6))
        let sentence = document.sentence(containing: word)!
        #expect((text as NSString).substring(with: sentence).contains("Eine schöne Welt."))
        #expect(!((text as NSString).substring(with: sentence).contains("Noch")))
    }
    @Test func pauseSeekAndStopRejectStaleCallbacks() {
        var cursor = SpeechCursor()
        let first = cursor.begin(length: 100, offset: 25)
        _ = cursor.accept(NSRange(location: 7, length: 4), session: first)
        cursor.invalidate()
        #expect(cursor.restartOffset == 32)
        #expect(cursor.accept(NSRange(location: 12, length: 5), session: first) == nil)
        let resumed = cursor.begin(length: 100, offset: 32)
        #expect(cursor.accept(NSRange(location: 0, length: 4), session: resumed)?.location == 32)
        let seek = cursor.begin(length: 100, offset: 70)
        #expect(cursor.accept(NSRange(location: 5, length: 4), session: resumed) == nil)
        #expect(cursor.accept(NSRange(location: 0, length: 8), session: seek)?.location == 70)
        cursor.invalidate()
        #expect(cursor.accept(NSRange(location: 10, length: 4), session: seek) == nil)
    }
    @Test func rejectsInvalidSpeechRanges() {
        var cursor = SpeechCursor(); let token = cursor.begin(length: 20, offset: 10)
        for range in [NSRange(location: NSNotFound, length: 1), NSRange(location: -1, length: 2), NSRange(location: 9, length: 3), NSRange(location: 0, length: 0), NSRange(location: Int.max, length: Int.max)] {
            #expect(cursor.accept(range, session: token) == nil)
        }
    }
    @Test func sentenceNavigationAndEmptyText() {
        let document = ReadingDocument(attributedText: NSAttributedString(string: "First thought. Another idea!"))
        let next = document.sentenceStart(from: 0, direction: 1)
        #expect(next > 0)
        #expect(document.sentenceStart(from: next, direction: -1) == 0)
        #expect(document.sentenceStart(from: next, direction: 1) == document.utf16Count)
        let empty = ReadingDocument(attributedText: NSAttributedString(string: ""))
        #expect(empty.words.isEmpty)
        #expect(empty.sentence(containing: NSRange(location: 0, length: 1)) == nil)
    }
    @Test func voiceFollowsLanguageAndRateIsBounded() {
        let controller = SpeechController()
        let originalRate = controller.rate
        defer { controller.setRate(originalRate) }
        for (text, language) in [("Das ist ein deutscher Text. Wir hören den Worten aufmerksam zu.", "de"), ("This is an English passage. We are listening carefully to the words.", "en")] {
            controller.load(ReadingDocument(attributedText: NSAttributedString(string: text)))
            #expect(controller.document.language == language)
            if let voice = controller.selectedVoice { #expect(voice.language.hasPrefix(language)) }
        }
        controller.setRate(10); #expect(controller.rate == 2)
        controller.setRate(0); #expect(controller.rate == 0.5)
        controller.setRate(.nan); #expect(controller.rate == 0.5)
    }
    @Test func panelIsFloatingCompactAndDoesNotBecomeMainWindow() {
        _ = NSApplication.shared
        let controller = FloatingPanelController()
        let panel = controller.window as! FloatingPanel
        panel.contentView?.layoutSubtreeIfNeeded()
        #expect(panel.level == .floating)
        #expect(panel.styleMask.contains(.nonactivatingPanel))
        #expect(panel.canBecomeKey)
        #expect(!panel.canBecomeMain)
        #expect(panel.frame.width == 720)
        #expect(panel.frame.height == 480)
        #expect(controller.reader.scroll.frame.height > 200)
        #expect(controller.reader.scroll.frame.height < 400)
    }
    @Test func completionStaysVisibleUnlessEnabledAndReopeningCancelsDismissal() async throws {
        _ = NSApplication.shared
        let suite = "SpoknPanelTests.\(UUID().uuidString)"
        let preferences = try #require(UserDefaults(suiteName: suite))
        let controller = FloatingPanelController(preferences: preferences)
        defer { controller.dismiss(); preferences.removePersistentDomain(forName: suite) }
        #expect(!controller.dismissAfterPlayback)
        #expect(controller.window?.hidesOnDeactivate == false)
        guard controller.reader.speech.selectedVoice != nil else { return }
        controller.receive(CapturedText(content: NSAttributedString(string: "Hello."), source: "Test"))
        for _ in 0..<100 where controller.reader.speech.state != .finished {
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(controller.reader.speech.state == .finished)
        #expect(controller.reader.view.frame.height == 480)
        try await Task.sleep(for: .milliseconds(1500))
        #expect(controller.window?.isVisible == true)
        controller.dismissAfterPlayback = true
        #expect(FloatingPanelController(preferences: preferences).dismissAfterPlayback)
        try await Task.sleep(for: .milliseconds(1500))
        #expect(controller.window?.isVisible == false)
        controller.show()
        controller.reader.speech.start()
        for _ in 0..<100 where controller.reader.speech.state != .finished {
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(controller.reader.speech.state == .finished)
        controller.show()
        try await Task.sleep(for: .milliseconds(1500))
        #expect(controller.window?.isVisible == true)
        controller.dismissAfterPlayback = true
        controller.dismissAfterPlayback = false
        try await Task.sleep(for: .milliseconds(1500))
        #expect(controller.window?.isVisible == true)
    }
    @Test func highlightsAreCenteredOnTypeAndExcludeParagraphSpacing() throws {
        _ = NSApplication.shared
        let reader = ReaderController(); _ = reader.view
        let font = NSFont.systemFont(ofSize: 21)
        let style = NSMutableParagraphStyle(); style.lineSpacing = 20; style.paragraphSpacing = 70
        let text = "A centered thought.\nAnother sentence that wraps onto several lines in a narrow container."
        reader.textView.textStorage?.setAttributedString(NSAttributedString(string: text, attributes: [.font: font, .paragraphStyle: style]))
        reader.textView.textContainer?.widthTracksTextView = false
        reader.textView.textContainer?.containerSize = NSSize(width: 220, height: 2000)
        let word = (text as NSString).range(of: "centered")
        let sentence = (text as NSString).range(of: "A centered thought.")
        let wordRect = try #require(reader.highlightLayout.highlightRects(for: word).first)
        let sentenceRect = try #require(reader.highlightLayout.highlightRects(for: sentence).first)
        #expect(abs(wordRect.midY - sentenceRect.midY) < 0.1)
        #expect(wordRect.height < 30, "Highlight height must not absorb line/paragraph spacing")
        #expect(sentenceRect.width < 220, "Highlight must stop at text, not fill trailing line space")
        let wraps = reader.highlightLayout.highlightRects(for: NSRange(location: NSMaxRange(sentence) + 1, length: (text as NSString).length - NSMaxRange(sentence) - 1))
        #expect(wraps.count > 1)
        #expect(wraps.allSatisfy { abs($0.height - wordRect.height) < 0.1 })
        #expect(reader.highlightLayout.highlightRects(for: NSRange(location: Int.max, length: 5)).isEmpty)
    }
    @Test(.enabled(if: ProcessInfo.processInfo.environment["SPOKN_RENDER_PREVIEW"] != nil))
    func renderPreview() throws {
        _ = NSApplication.shared
        let controller = FloatingPanelController()
        let reader = controller.reader
        let text = "# A little space to listen.\n\nSometimes the best way to **understand** an idea is to hear it aloud.\n\n- Listen to the rhythm.\n- Notice what stands out.\n\nClick any word to revisit a thought. Spokn stays beside your work, and its controls quietly fade to give these words more room."
        reader.load(CapturedText(content: NSAttributedString(string: text), source: "Preview"))
        reader.speech.toggle()
        defer { reader.speech.stop() }
        let word = (reader.textView.string as NSString).range(of: "understand")
        reader.highlightLayout.sentence = reader.speech.document.sentence(containing: word)
        reader.highlightLayout.word = word
        for (name, appearance) in [("dark", NSAppearance.Name.darkAqua), ("light", NSAppearance.Name.aqua), ("focus", NSAppearance.Name.darkAqua)] {
            reader.headerChrome.setHovered(name != "focus"); reader.footerChrome.setHovered(name != "focus")
            reader.view.appearance = NSAppearance(named: appearance)
            reader.view.layoutSubtreeIfNeeded()
            let bitmap = try #require(reader.view.bitmapImageRepForCachingDisplay(in: reader.view.bounds))
            reader.view.cacheDisplay(in: reader.view.bounds, to: bitmap)
            let data = try #require(bitmap.representation(using: .png, properties: [:]))
            let folder = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("build/native")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: folder.appendingPathComponent("preview-\(name).png"))
        }
    }
    @Test func speedScaleUsesQuarterSteps() {
        for (input, expected): (Float, Float) in [(0.51, 0.5), (0.72, 0.75), (0.99, 1), (1.24, 1.25), (1.49, 1.5), (1.76, 1.75), (1.99, 2)] {
            #expect(SpeechController.snappedRate(input) == expected)
        }
        let reader = ReaderController(); _ = reader.view
        #expect(reader.speed.numberOfTickMarks == 7)
        #expect(reader.speed.allowsTickMarkValuesOnly)
        #expect(reader.speed.tickMarkValue(at: 2) == 1)
    }
    @Test func visibleVoicePickerCanChangeVoiceOnWelcomeScreen() throws {
        _ = NSApplication.shared
        let panel = FloatingPanelController()
        let reader = panel.reader
        reader.view.layoutSubtreeIfNeeded()
        let picker = reader.voicePicker
        #expect(picker.isEnabled)
        #expect(picker.isBordered)
        #expect(picker.frame.width >= 240)
        #expect(!picker.isHiddenOrHasHiddenAncestor)
        let original = reader.speech.preferredVoiceID
        defer { reader.speech.stop(); reader.speech.selectVoice(original); reader.speech.stop() }
        guard let voice = reader.speech.matchingVoices.first else { return }
        #expect(picker.title.contains(reader.speech.selectedVoice!.name))
        let item = try #require(picker.itemArray.first(where: { $0.representedObject as? String == voice.identifier }))
        picker.select(item)
        #expect(picker.sendAction(picker.action, to: picker.target))
        #expect(reader.speech.selectedVoice?.identifier == voice.identifier)
        #expect(picker.title.contains(voice.name))
    }
    @Test func voicePreferencesAreRestrictedAndRememberedPerLanguage() throws {
        let suite = "SpoknTests.\(UUID().uuidString)"
        let preferences = try #require(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let controller = SpeechController(preferences: preferences)
        let english = ReadingDocument(attributedText: NSAttributedString(string: "This is an English passage. Listen to the words."))
        let german = ReadingDocument(attributedText: NSAttributedString(string: "Dies ist ein deutscher Text. Wir hören den Worten aufmerksam zu."))
        controller.load(english)
        #expect(controller.matchingVoices.allSatisfy { $0.language.hasPrefix("en") })
        guard let englishVoice = controller.matchingVoices.last else { return }
        controller.selectVoice(englishVoice.identifier)
        #expect(controller.selectedVoice?.identifier == englishVoice.identifier)
        controller.load(german)
        #expect(controller.matchingVoices.allSatisfy { $0.language.hasPrefix("de") })
        controller.selectVoice(englishVoice.identifier)
        #expect(controller.preferredVoiceID == nil)
        if let voice = controller.matchingVoices.first {
            controller.selectVoice(voice.identifier)
            #expect(controller.selectedVoice?.identifier == voice.identifier)
        }
        controller.load(english)
        #expect(controller.selectedVoice?.identifier == englishVoice.identifier)
        let restarted = SpeechController(preferences: preferences)
        restarted.load(english)
        #expect(restarted.selectedVoice?.identifier == englishVoice.identifier)
        restarted.selectVoice(nil)
        #expect(restarted.preferredVoiceID == nil)
        #expect(SpeechController.voiceLanguage("zh-CN", matches: "zh-Hans"))
        #expect(!SpeechController.voiceLanguage("zh-TW", matches: "zh-Hans"))
    }
    @Test func highlightsDoNotModifyOriginalFormatting() {
        _ = NSApplication.shared
        let reader = ReaderController(); _ = reader.view
        let rich = NSAttributedString(string: "Bold thought. Another sentence.", attributes: [.font: NSFont.boldSystemFont(ofSize: 14)])
        reader.textView.textStorage?.setAttributedString(rich)
        let word = NSRange(location: 0, length: 4)
        reader.highlightLayout.sentence = NSRange(location: 0, length: 13)
        reader.highlightLayout.word = word
        #expect(reader.textView.attributedString().isEqual(to: rich))
        reader.highlightLayout.word = nil; reader.highlightLayout.sentence = nil
        #expect(reader.textView.attributedString().isEqual(to: rich))
    }

    @Test func markdownRendersStructureBeforeSpeechTokenization() throws {
        let input = "# Grüße 👩🏽‍💻\n\nA **bold** and *gentle* thought with `code`.\n\n- First idea\n- [Second idea](https://example.com)\n\n> A quotation.\n\n```swift\nlet value = 1\nprint(value)\n```"
        let rich = TextFormatting.prepare(NSAttributedString(string: input))
        #expect(rich.string.hasPrefix("Grüße 👩🏽‍💻\nA bold and gentle thought with code.\n•\tFirst idea\n•\tSecond idea\n"))
        #expect(rich.string.contains("let value = 1\nprint(value)"))
        let bold = (rich.string as NSString).range(of: "bold")
        let font = try #require(rich.attribute(.font, at: bold.location, effectiveRange: nil) as? NSFont)
        #expect(NSFontManager.shared.traits(of: font).contains(.boldFontMask))
        let link = (rich.string as NSString).range(of: "Second idea")
        #expect(rich.attribute(.link, at: link.location, effectiveRange: nil) as? URL == URL(string: "https://example.com"))
        let document = ReadingDocument(attributedText: rich)
        #expect(document.wordStart(near: bold.location + 2) == bold.location)
        #expect(document.words.allSatisfy { Range($0, in: rich.string) != nil })
        let literal = "A plain line.\nAnother line.\n\nPrice: $5 * 2; foo_bar_baz."
        #expect(TextFormatting.prepare(NSAttributedString(string: literal)).string == literal)
        let styled = NSAttributedString(string: "**Keep the editor's text**", attributes: [.font: NSFont.boldSystemFont(ofSize: 15)])
        #expect(TextFormatting.prepare(styled).isEqual(to: styled))
        let html = TextFormatting.prepare(NSAttributedString(string: "<h1>A heading</h1><p>A <strong>thought</strong>.</p>"))
        #expect(html.string.contains("A heading\n"))
        #expect(html.string.contains("A thought."))
    }

    @Test func wordHitTestingAndSeekingFollowRenderedUTF16Text() throws {
        _ = NSApplication.shared
        let panel = FloatingPanelController()
        let reader = panel.reader
        reader.load(CapturedText(content: NSAttributedString(string: "# A thought\n\nHello 👩🏽‍💻. A **beautiful** second sentence.\n\nThe last thought."), source: "Test"))
        reader.speech.stop()
        defer { reader.speech.stop() }
        reader.view.layoutSubtreeIfNeeded()
        reader.highlightLayout.ensureLayout(for: try #require(reader.textView.textContainer))
        let text = reader.textView.string as NSString
        for target in ["last", "beautiful", "Hello"] {
            let range = text.range(of: target)
            let box = try #require(reader.highlightLayout.highlightRects(for: range).first)
            let origin = reader.textView.textContainerOrigin
            let point = NSPoint(x: box.midX + origin.x, y: box.midY + origin.y)
            let position = try #require(reader.textView.character(at: point))
            #expect(NSLocationInRange(position, range))
            reader.textView.onReadHere?(position)
            #expect(reader.speech.cursor.restartOffset == range.location)
            #expect(reader.highlightLayout.word == range)
            #expect(reader.highlightLayout.sentence == reader.speech.document.sentence(containing: range))
        }
        #expect(reader.textView.character(at: NSPoint(x: -10, y: -10)) == nil)
        #expect(reader.textView.character(at: NSPoint(x: 700, y: 1000)) == nil)
    }

    @Test func idleControlsMakeRoomAndRestoreOnHoverOrKeyboard() {
        _ = NSApplication.shared
        let panel = FloatingPanelController()
        let reader = panel.reader
        reader.view.layoutSubtreeIfNeeded()
        let compactHeight = reader.scroll.frame.height
        reader.footerChrome.fadesWhenIdle = true
        reader.footerChrome.setHovered(false)
        reader.view.layoutSubtreeIfNeeded()
        #expect(!reader.footerChrome.revealed)
        #expect(reader.scroll.frame.height > compactHeight + 50)
        reader.footerChrome.setHovered(true)
        #expect(reader.footerChrome.revealed)
        #expect(abs(reader.scroll.frame.height - compactHeight) < 1)
        reader.footerChrome.setHovered(false)
        reader.revealControlsForKeyboard()
        #expect(reader.footerChrome.revealed)
        #expect(reader.headerChrome.revealed)
    }
}
