import AppKit

/// Paint highlights behind glyphs, without changing the captured text's attributes.
nonisolated final class ReadingLayoutManager: NSLayoutManager {
    var sentence: NSRange? { didSet { invalidateHighlights(oldValue, sentence) } }
    var word: NSRange? { didSet { invalidateHighlights(oldValue, word) } }
    private func invalidateHighlights(_ old: NSRange?, _ new: NSRange?) {
        for range in [old, new].compactMap({ $0 }) {
            invalidateDisplay(forCharacterRange: range)
        }
    }
    /// Use each line's baseline and font metrics, never its paragraph/line spacing.
    /// Word and sentence fills share this geometry, including mixed font sizes.
    func highlightRects(for range: NSRange) -> [NSRect] {
        guard let storage = textStorage, let container = textContainers.first,
              range.location >= 0, range.location <= storage.length,
              range.length > 0, range.length <= storage.length - range.location else { return [] }
        ensureLayout(for: container)
        let glyphs = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        var boxes: [NSRect] = []
        enumerateLineFragments(forGlyphRange: glyphs) { line, _, _, lineGlyphs, _ in
            let intersection = NSIntersectionRange(glyphs, lineGlyphs)
            let characters = self.characterRange(forGlyphRange: intersection, actualGlyphRange: nil)
            let content = (storage.string as NSString).substring(with: characters) as NSString
            let first = content.rangeOfCharacter(from: .whitespacesAndNewlines.inverted)
            let last = content.rangeOfCharacter(from: .whitespacesAndNewlines.inverted, options: .backwards)
            guard first.location != NSNotFound, last.location != NSNotFound else { return }
            let trimmed = NSRange(location: characters.location + first.location, length: NSMaxRange(last) - first.location)
            let selected = self.glyphRange(forCharacterRange: trimmed, actualCharacterRange: nil)
            let horizontal = self.boundingRect(forGlyphRange: selected, in: container)
            let baseline = line.minY + self.location(forGlyphAt: lineGlyphs.location).y
            var top: CGFloat = 0, bottom: CGFloat = 0
            let lineCharacters = self.characterRange(forGlyphRange: lineGlyphs, actualGlyphRange: nil)
            storage.enumerateAttribute(.font, in: lineCharacters) { value, _, _ in
                let font = value as? NSFont ?? .systemFont(ofSize: 21)
                top = max(top, font.capHeight); bottom = max(bottom, -font.descender)
            }
            boxes.append(NSRect(x: horizontal.minX - 3, y: baseline - top - 3,
                                width: horizontal.width + 6, height: top + bottom + 6))
        }
        return boxes
    }
    override func drawBackground(forGlyphRange glyphs: NSRange, at origin: NSPoint) {
        super.drawBackground(forGlyphRange: glyphs, at: origin)
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        for (range, color, radius) in [(sentence, Design.accent.withAlphaComponent(0.10), 5.0), (word, Design.accent.withAlphaComponent(0.32), 4.0)] {
            guard let range, NSIntersectionRange(glyphRange(forCharacterRange: range, actualCharacterRange: nil), glyphs).length > 0 else { continue }
            color.setFill()
            for rect in highlightRects(for: range) {
                NSBezierPath(roundedRect: rect.offsetBy(dx: origin.x, dy: origin.y), xRadius: radius, yRadius: radius).fill()
            }
        }
    }

}

final class ReadingTextView: NSTextView {
    var onReadHere: ((Int) -> Void)?
    private var clickedLink = false
    /// Hit-test glyph bounds, not the nearest insertion point (which also hits blank space).
    func character(at point: NSPoint) -> Int? {
        guard let layoutManager, let textContainer else { return nil }
        layoutManager.ensureLayout(for: textContainer)
        let local = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        let glyph = layoutManager.glyphIndex(for: local, in: textContainer)
        guard glyph < layoutManager.numberOfGlyphs,
              layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: textContainer).contains(local) else { return nil }
        return layoutManager.characterIndexForGlyph(at: glyph)
    }
    override func mouseDown(with event: NSEvent) {
        let position = character(at: convert(event.locationInWindow, from: nil))
        clickedLink = false
        // NSTextView tracks through mouse-up, preserving drag and double-click selection.
        super.mouseDown(with: event)
        guard event.clickCount == 1, (selectedRange().length == 0 || clickedLink),
              event.modifierFlags.intersection([.shift, .command, .option, .control]).isEmpty,
              let position else { return }
        onReadHere?(position)
    }
    override func clicked(onLink link: Any, at charIndex: Int) {
        // A normal word click always seeks, including words styled as hyperlinks.
        clickedLink = true
        if NSApp.currentEvent?.modifierFlags.contains(.command) == true { super.clicked(onLink: link, at: charIndex) }
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        menu.addItem(.separator())
        let item = NSMenuItem(title: "Read from Here", action: #selector(readHere), keyEquivalent: "")
        item.target = self; menu.addItem(item); return menu
    }
    @objc private func readHere() { onReadHere?(selectedRange().location) }
}

final class ReaderController: NSViewController, NSMenuDelegate {
    let speech = SpeechController()
    let highlightLayout = ReadingLayoutManager()
    let textView: ReadingTextView
    let scroll = NSScrollView()
    var onFinish: (() -> Void)?
    var onInteraction: (() -> Void)?
    var onDismiss: (() -> Void)?
    var onPaste: (() -> Void)?
    private let sourceLabel = Design.label("READY WHEN YOU ARE", size: 10, weight: .semibold, color: .secondaryLabelColor)
    private let statusLabel = Design.label("Select text anywhere · ⌘⇧S", size: 12, color: .secondaryLabelColor)
    let voicePicker = NSPopUpButton(frame: .zero, pullsDown: false)
    private let voiceHeading = Design.label("VOICE", size: 9, weight: .semibold, color: .secondaryLabelColor)
    private var voiceMenuLanguage: String?
    private var voiceMenuIDs: [String] = []
    private let speedLabel = Design.label("1×", size: 13, weight: .semibold, color: Design.accent)
    let speed = NSSlider(value: 1, minValue: 0.5, maxValue: 2, target: nil, action: nil)
    private let progress = NSProgressIndicator()
    let selectionAccess = NSButton(title: "Enable Selection Access…", target: nil, action: nil)
    private var preview: NSButton!
    private var play: NSButton!
    private var previous: NSButton!
    private var next: NSButton!
    private var previousState: SpeechController.State = .idle
    private var rateCommit: DispatchWorkItem?
    private var pendingRate: Float?
    private var isWelcome = true
    let headerChrome = HoverControlsView(dimmedAlpha: 0.22)
    let footerChrome = HoverControlsView(dimmedAlpha: 0)
    private var expandedTextBottom: NSLayoutConstraint?
    private var compactTextBottom: NSLayoutConstraint?

    init() {
        let storage = NSTextStorage()
        storage.addLayoutManager(highlightLayout)
        let container = NSTextContainer(size: NSSize(width: 660, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        highlightLayout.addTextContainer(container)
        textView = ReadingTextView(frame: .zero, textContainer: container)
        super.init(nibName: nil, bundle: nil)
        speech.onClearWord = { [weak self] in self?.highlightLayout.word = nil }
        speech.onSentence = { [weak self] in self?.highlightLayout.sentence = $0 }
        speech.onWord = { [weak self] in self?.highlight($0) }
        speech.onChange = { [weak self] in self?.updatePlayback() }
        textView.onReadHere = { [weak self] position in
            guard let self, !self.isWelcome,
                  self.speech.document.words.contains(where: { NSLocationInRange(position, $0) }) else { return }
            self.onInteraction?(); self.speech.seek(to: position)
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        let glass = PanelSurface()
        glass.clipsToBounds = true; glass.wantsLayer = true; glass.layer?.cornerRadius = 20; glass.layer?.masksToBounds = true
        glass.layer?.borderWidth = 1; glass.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        view = glass
        let mark = WaveView(); mark.setAccessibilityLabel("Spokn")
        let brand = Design.stack([Design.label("Spokn", size: 15, weight: .semibold), sourceLabel], spacing: 4)
        let close = Design.button("xmark", label: "Dismiss · Escape", target: self, action: #selector(dismissPanel))
        let paste = Design.button("doc.on.clipboard", label: "Paste and read · ⌘V", target: self, action: #selector(pasteText))
        voicePicker.controlSize = .regular; voicePicker.font = .systemFont(ofSize: 12, weight: .medium)
        voicePicker.bezelStyle = .rounded; voicePicker.isBordered = true
        voicePicker.target = self; voicePicker.action = #selector(changeVoice)
        voicePicker.setAccessibilityLabel("Voice for detected language")
        voicePicker.translatesAutoresizingMaskIntoConstraints = false
        voicePicker.widthAnchor.constraint(equalToConstant: 244).isActive = true
        voicePicker.heightAnchor.constraint(equalToConstant: 30).isActive = true
        preview = Design.button("speaker.wave.2", label: "Preview selected voice", target: self, action: #selector(previewVoice))
        let voiceRow = Design.stack([voicePicker, preview], orientation: .horizontal, spacing: 6)
        let voiceControl = Design.stack([voiceHeading, voiceRow], spacing: 4)
        voiceControl.alignment = .width
        let header = Design.stack([mark, brand, NSView(), voiceControl, paste, close], orientation: .horizontal, spacing: 12)
        header.wantsLayer = true
        headerChrome.install(header); glass.addSubview(headerChrome)

        textView.clipsToBounds = true; scroll.contentView.clipsToBounds = true
        textView.isEditable = false; textView.isSelectable = true
        textView.drawsBackground = false; textView.isRichText = true
        textView.isVerticallyResizable = true; textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]; textView.textContainerInset = NSSize(width: 28, height: 16)
        textView.minSize = .zero; textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.setAccessibilityLabel("Reading text")
        scroll.wantsLayer = true
        scroll.documentView = textView; scroll.drawsBackground = false
        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.borderType = .noBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false; glass.addSubview(scroll)

        previous = Design.button("backward.end", label: "Previous sentence · ←", target: self, action: #selector(back))
        next = Design.button("forward.end", label: "Next sentence · →", target: self, action: #selector(forward))
        play = NSButton(image: Design.symbol("play.fill", "Play", size: 18)!, target: self, action: #selector(toggle))
        play.bezelStyle = .circular; play.isBordered = false; play.contentTintColor = .white
        play.wantsLayer = true; play.layer?.backgroundColor = Design.accent.cgColor; play.layer?.cornerRadius = 23
        play.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([play.widthAnchor.constraint(equalToConstant: 46), play.heightAnchor.constraint(equalToConstant: 46)])
        play.setAccessibilityLabel("Play or pause")
        speed.cell = SpeedSliderCell()
        speed.minValue = 0.5; speed.maxValue = 2
        speed.target = self; speed.action = #selector(changeSpeed); speed.isContinuous = true
        speed.numberOfTickMarks = 7; speed.allowsTickMarkValuesOnly = true; speed.tickMarkPosition = .below
        speed.controlSize = .regular; speed.setAccessibilityLabel("Reading speed")
        speed.toolTip = "Reading speed · 0.5× to 2×"; speed.translatesAutoresizingMaskIntoConstraints = false
        speed.widthAnchor.constraint(equalToConstant: 250).isActive = true
        speed.heightAnchor.constraint(equalToConstant: 26).isActive = true
        speedLabel.alignment = .right
        speedLabel.widthAnchor.constraint(equalToConstant: 48).isActive = true
        let scale = SpeedScaleView(slider: speed)
        let speedTitle = Design.stack([Design.label("READING SPEED", size: 9, weight: .semibold, color: .secondaryLabelColor), NSView(), speedLabel], orientation: .horizontal, spacing: 10)
        let speedTrack = Design.stack([speedTitle, speed, scale], spacing: 3)
        speedTrack.alignment = .width
        scale.heightAnchor.constraint(equalToConstant: 16).isActive = true
        let controls = Design.stack([previous, play, next, NSView(), speedTrack], orientation: .horizontal, spacing: 12)
        let hint = Design.label("Esc to dismiss", size: 10, color: .tertiaryLabelColor)
        selectionAccess.bezelStyle = .rounded
        selectionAccess.controlSize = .small
        selectionAccess.target = self; selectionAccess.action = #selector(enableSelectionAccess)
        let detail = Design.stack([statusLabel, NSView(), selectionAccess, hint], orientation: .horizontal, spacing: 12)
        let footer = Design.stack([controls, detail], spacing: 14)
        footer.wantsLayer = true
        footer.alignment = .width; footerChrome.install(footer); glass.addSubview(footerChrome)
        progress.isIndeterminate = false; progress.minValue = 0; progress.maxValue = 1
        progress.style = .bar; progress.controlSize = .small; progress.translatesAutoresizingMaskIntoConstraints = false
        glass.addSubview(progress)
        NSLayoutConstraint.activate([
            headerChrome.leadingAnchor.constraint(equalTo: glass.leadingAnchor, constant: 28), headerChrome.trailingAnchor.constraint(equalTo: glass.trailingAnchor, constant: -20),
            headerChrome.topAnchor.constraint(equalTo: glass.topAnchor, constant: 20), headerChrome.heightAnchor.constraint(equalToConstant: 48),
            scroll.leadingAnchor.constraint(equalTo: glass.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: glass.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: headerChrome.bottomAnchor, constant: 18),
            footerChrome.leadingAnchor.constraint(equalTo: glass.leadingAnchor, constant: 28), footerChrome.trailingAnchor.constraint(equalTo: glass.trailingAnchor, constant: -28),
            footerChrome.bottomAnchor.constraint(equalTo: progress.topAnchor, constant: -20),
            progress.leadingAnchor.constraint(equalTo: glass.leadingAnchor, constant: 28), progress.trailingAnchor.constraint(equalTo: glass.trailingAnchor, constant: -28),
            progress.bottomAnchor.constraint(equalTo: glass.bottomAnchor, constant: -14), progress.heightAnchor.constraint(equalToConstant: 3)
        ])
        expandedTextBottom = scroll.bottomAnchor.constraint(equalTo: progress.topAnchor, constant: -12)
        compactTextBottom = scroll.bottomAnchor.constraint(equalTo: footerChrome.topAnchor, constant: -20)
        compactTextBottom?.isActive = true
        footerChrome.onReveal = { [weak self] visible in
            guard let self else { return }
            self.compactTextBottom?.isActive = false; self.expandedTextBottom?.isActive = false
            (visible ? self.compactTextBottom : self.expandedTextBottom)?.isActive = true
            self.view.layoutSubtreeIfNeeded()
        }
        showWelcome()
    }

    func showWelcome(message: String? = nil) {
        _ = view
        isWelcome = true; speech.stop(); highlightLayout.word = nil; highlightLayout.sentence = nil
        headerChrome.fadesWhenIdle = false; footerChrome.fadesWhenIdle = false
        sourceLabel.stringValue = "A LITTLE SPACE TO LISTEN"
        let title = "Your words. A moment of clarity.\n\n"
        let copy = message ?? "Select something you'd like to hear, then press ⌘⇧S. Spokn stays beside your work as it reads aloud.\n\nClick a word to jump there. Hover over the controls to bring them back, or press Escape to dismiss. You can also paste with ⌘V."
        let rich = NSMutableAttributedString(string: title + copy)
        rich.addAttribute(.font, value: NSFont.systemFont(ofSize: 29, weight: .semibold), range: NSRange(location: 0, length: (title as NSString).length))
        render(rich); updatePlayback()
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isWelcome else { return }
            self.scroll.contentView.scroll(to: .zero)
            self.scroll.reflectScrolledClipView(self.scroll.contentView)
        }
    }
    func load(_ capture: CapturedText) {
        _ = view
        onInteraction?(); rateCommit?.cancel(); rateCommit = nil
        if let pendingRate { speech.setRate(pendingRate); self.pendingRate = nil }
        isWelcome = false
        headerChrome.fadesWhenIdle = true; footerChrome.fadesWhenIdle = true
        highlightLayout.word = nil; highlightLayout.sentence = nil
        sourceLabel.stringValue = capture.source.uppercased()
        let document = ReadingDocument(attributedText: TextFormatting.prepare(capture.content))
        render(document.attributedText); speech.load(document); scroll.contentView.scroll(to: .zero)
        speech.start()
    }
    private func render(_ captured: NSAttributedString) {
        // Preserve text, emphasis, lists, indents and links. Normalize ink and type scale for the panel.
        let result = NSMutableAttributedString(attributedString: captured)
        let full = NSRange(location: 0, length: result.length)
        result.removeAttribute(.backgroundColor, range: full)
        result.removeAttribute(.attachment, range: full)
        result.addAttribute(.foregroundColor, value: NSColor.labelColor, range: full)
        captured.enumerateAttributes(in: full) { attributes, range, _ in
            let original = attributes[.font] as? NSFont
            let size = original.map { min(32, max(18, $0.pointSize * (21 / 14))) } ?? 21
            var font = NSFont.systemFont(ofSize: size)
            if let original {
                let traits = NSFontManager.shared.traits(of: original)
                if traits.contains(.fixedPitchFontMask) { font = .monospacedSystemFont(ofSize: min(size, 19), weight: .regular) }
                font = NSFontManager.shared.convert(font, toHaveTrait: traits.intersection([.boldFontMask, .italicFontMask]))
            }
            result.addAttribute(.font, value: font, range: range)
            let paragraph = (attributes[.paragraphStyle] as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
            paragraph.lineSpacing = 7; paragraph.paragraphSpacing = max(10, paragraph.paragraphSpacing)
            // Wide source layouts should wrap naturally within the floating panel.
            paragraph.firstLineHeadIndent = min(40, paragraph.firstLineHeadIndent)
            paragraph.headIndent = min(40, paragraph.headIndent); paragraph.tailIndent = 0
            result.addAttribute(.paragraphStyle, value: paragraph, range: range)
        }
        textView.textStorage?.setAttributedString(result)
    }
    private func highlight(_ word: NSRange) {
        guard !isWelcome, NSMaxRange(word) <= textView.string.utf16.count else { return }
        let sentence = speech.document.sentence(containing: word)
        highlightLayout.sentence = sentence; highlightLayout.word = word
        // Follow each word only when it leaves the viewport; long sentences remain readable.
        let glyphs = highlightLayout.glyphRange(forCharacterRange: word, actualCharacterRange: nil)
        if let container = textView.textContainer {
            let rect = highlightLayout.boundingRect(forGlyphRange: glyphs, in: container).offsetBy(dx: textView.textContainerOrigin.x, dy: textView.textContainerOrigin.y)
            if !textView.visibleRect.insetBy(dx: 0, dy: 24).contains(rect) { textView.scrollRangeToVisible(word) }
        }
    }
    func refreshEnvironment() {
        speech.refreshVoices()
        updatePlayback()
    }
    func revealControlsForKeyboard() {
        headerChrome.revealForKeyboard(); footerChrome.revealForKeyboard()
    }
    @objc private func enableSelectionAccess() { onInteraction?(); MacIntegration.openAccessibility() }
    @objc private func previewVoice() { onInteraction?(); if speech.isPreviewing { speech.toggle() } else { speech.previewVoice() } }
    private func updatePlayback() {
        guard isViewLoaded else { return }
        let state = speech.state
        // Preparation and errors need visible feedback even when the pointer is elsewhere.
        footerChrome.fadesWhenIdle = !isWelcome && !speech.isStarting && speech.playbackError == nil
        selectionAccess.isHidden = !isWelcome || MacIntegration.accessibilityEnabled
        preview.isEnabled = speech.canSpeak
        preview.contentTintColor = speech.isPreviewing ? Design.accent : .secondaryLabelColor
        play.image = Design.symbol(state == .speaking ? "pause.fill" : "play.fill", "Play or pause", size: 18)
        play.isEnabled = speech.isPreviewing || (!isWelcome && speech.canSpeak && !speech.document.words.isEmpty)
        previous.isEnabled = play.isEnabled; next.isEnabled = play.isEnabled
        if pendingRate == nil { speed.floatValue = speech.rate; speedLabel.stringValue = Self.rateText(speech.rate) }
        let language = Locale.current.localizedString(forLanguageCode: speech.document.language) ?? speech.document.language
        updateVoiceMenu(language: language)
        switch state {
        case .idle: statusLabel.stringValue = isWelcome ? "Select text anywhere · ⌘⇧S" : (!speech.canSpeak ? "Install a voice in System Settings → Accessibility → Spoken Content" : "Ready · Space to play")
        case .speaking: statusLabel.stringValue = speech.isStarting ? "Starting \(speech.activeVoiceName)…" : speech.isPreviewing ? "Voice preview" : "Listening · Space to pause"
        case .paused: statusLabel.stringValue = "Paused · Space to resume"
        case .finished: statusLabel.stringValue = "All read. Back to your day."
        }
        if let message = speech.preparationStatus, state != .paused { statusLabel.stringValue = message }
        if let error = speech.playbackError { statusLabel.stringValue = error }
        statusLabel.toolTip = statusLabel.stringValue
        statusLabel.maximumNumberOfLines = 2
        progress.doubleValue = isWelcome ? 0 : state == .finished ? 1 : Double(speech.cursor.restartOffset) / Double(max(1, speech.document.utf16Count))
        if state == .idle { highlightLayout.word = nil; highlightLayout.sentence = nil }
        if !isWelcome && state == .finished && previousState != .finished { onFinish?() }
        previousState = state
    }
    private func updateVoiceMenu(language: String) {
        let ids = speech.pocketVoices.map(\.identifier) + speech.matchingVoices.map(\.identifier)
        if voiceMenuLanguage != speech.document.language || voiceMenuIDs != ids || voicePicker.numberOfItems == 0 {
            voicePicker.removeAllItems()
            voicePicker.addItem(withTitle: "Automatic")
            for voice in speech.pocketVoices {
                voicePicker.addItem(withTitle: "\(voice.name) · Pocket TTS")
                voicePicker.lastItem?.representedObject = voice.identifier
                voicePicker.lastItem?.toolTip = "Open source · on-device. First use downloads a language pack (about 450 MB for English/German) and shared word timing (about 470 MB)."
            }
            for voice in speech.matchingVoices {
                let locale = Locale.current.localizedString(forIdentifier: voice.language) ?? voice.language
                let region = Locale(identifier: voice.language).region?.identifier ?? voice.language
                let quality = voice.quality == .premium && !voice.name.contains("Premium") ? " · Premium" : voice.quality == .enhanced && !voice.name.contains("Enhanced") ? " · Enhanced" : ""
                voicePicker.addItem(withTitle: "\(voice.name) · \(region)\(quality)")
                voicePicker.lastItem?.toolTip = locale
                voicePicker.lastItem?.representedObject = voice.identifier
            }
            voicePicker.menu?.addItem(.separator())
            voicePicker.addItem(withTitle: "Get more Apple voices…")
            voicePicker.lastItem?.representedObject = "download-voices"
            voicePicker.menu?.delegate = self
            voiceMenuLanguage = speech.document.language; voiceMenuIDs = ids
        }
        let selected = speech.preferredVoiceID.flatMap { ids.firstIndex(of: $0).map { $0 + 1 } } ?? 0
        voicePicker.selectItem(at: selected)
        voiceHeading.stringValue = "VOICE · \(language.uppercased())"
        let automaticName = selected == 0 ? speech.selectedVoice?.name : nil
        voicePicker.item(at: 0)?.title = automaticName.map { "\($0) · Automatic" } ?? "Automatic voice"
        voicePicker.isEnabled = true
        voicePicker.toolTip = isWelcome ? "Choose a voice now. Spokn detects the language when you add text." : "Choose an Apple or open source \(language) voice"
        voicePicker.setAccessibilityValue(voicePicker.title)
    }
    func menuWillOpen(_ menu: NSMenu) { onInteraction?(); speech.refreshVoices() }
    @objc private func changeVoice() {
        onInteraction?()
        let identifier = voicePicker.selectedItem?.representedObject as? String
        if identifier == "download-voices" {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.universalaccess?SpokenContent") { NSWorkspace.shared.open(url) }
            voicePicker.selectItem(at: speech.preferredVoiceID.flatMap { voiceMenuIDs.firstIndex(of: $0).map { $0 + 1 } } ?? 0)
        } else {
            speech.selectVoice(identifier)
            if isWelcome && !speech.isPreviewing { speech.previewVoice() }
        }
    }
    private static func rateText(_ value: Float) -> String { String(format: "%.2f", value).replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression) + "×" }
    @objc func toggle() { guard !isWelcome || speech.isPreviewing else { return }; onInteraction?(); speech.toggle() }
    @objc func back() { guard !isWelcome else { return }; onInteraction?(); speech.skip(-1) }
    @objc func forward() { guard !isWelcome else { return }; onInteraction?(); speech.skip(1) }
    @objc private func dismissPanel() { onDismiss?() }
    @objc private func pasteText() { onPaste?() }
    @objc private func changeSpeed() {
        onInteraction?()
        let value = SpeechController.snappedRate(speed.floatValue)
        speed.floatValue = value
        pendingRate = value; speedLabel.stringValue = Self.rateText(value)
        rateCommit?.cancel()
        // Debounce slider scrubbing so dragging doesn't repeatedly interrupt the voice.
        let commit = DispatchWorkItem { [weak self] in
            guard let self, let rate = self.pendingRate else { return }
            self.pendingRate = nil; self.speech.setRate(rate)
        }
        rateCommit = commit; DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: commit)
    }
}
