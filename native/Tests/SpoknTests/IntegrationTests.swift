import Testing
import AppKit
import AVFoundation
import FluidAudio
@testable import Spokn

@Suite(.serialized) @MainActor struct IntegrationTests {
    @Test func formattedCopyWinsOverFlattenedAccessibilityText() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let html = "<p>Installed and verified.</p><ul><li><strong>Jürgen</strong> prepares audio ahead.</li><li>Speed changes preserve highlights.</li></ul><p><a href='https://example.com'>Pocket TTS</a> runs locally.</p>"
        board.setData(Data(html.utf8), forType: .html)
        board.setString("Installed and verified.Jürgen prepares audio ahead.Speed changes preserve highlights.Pocket TTS runs locally.", forType: .string)
        let copied = try #require(MacIntegration.clipboard(from: board)?.content)
        let flat = NSAttributedString(string: board.string(forType: .string)!)
        let selected = try #require(MacIntegration.preferredSelection(copied: copied, accessibility: flat))
        #expect(selected.string.components(separatedBy: .newlines).filter { !$0.isEmpty }.count >= 4)
        #expect(selected.string.contains("Jürgen"))
        let range = (selected.string as NSString).range(of: "Jürgen")
        let font = try #require(selected.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont)
        #expect(NSFontManager.shared.traits(of: font).contains(.boldFontMask))
        let link = (selected.string as NSString).range(of: "Pocket TTS")
        #expect(selected.attribute(.link, at: link.location, effectiveRange: nil) != nil)
        #expect(MacIntegration.preferredSelection(copied: nil, accessibility: flat)?.string == flat.string)
    }
    @Test func detectedLanguageSelectsOnlyMatchingVoicesAndRestoresChoices() throws {
        let suite = "SpoknLanguages.\(UUID().uuidString)"
        let preferences = try #require(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let speech = SpeechController(preferences: preferences)
        let cases = [
            ("en", "Installed and verified. Jürgen now prepares audio ahead. Speed changes preserve synchronized word and sentence highlights.", "alba"),
            ("de", "Dieser deutsche Text wird mit der passenden Stimme vorgelesen. Die Sätze bleiben dabei gut lesbar und die Wörter werden hervorgehoben.", "juergen"),
            ("fr", "Ce texte est écrit en français. La voix doit correspondre à la langue du passage et lire chaque phrase naturellement.", "estelle"),
            ("es", "Este texto está escrito en español. La voz debe coincidir con el idioma del texto y leer cada frase de forma natural.", "lola"),
            ("it", "Questo testo è scritto in italiano. La voce deve corrispondere alla lingua del testo e leggere ogni frase in modo naturale.", "giovanni"),
            ("pt", "Este texto está escrito em português. A voz deve corresponder ao idioma do texto e ler cada frase de forma natural.", "rafael")
        ]
        for (language, text, voice) in cases {
            speech.load(ReadingDocument(attributedText: NSAttributedString(string: text)))
            #expect(speech.document.language == language)
            #expect(speech.matchingVoices.allSatisfy { SpeechController.voiceLanguage($0.language, matches: language) })
            #expect(speech.pocketVoices.allSatisfy { $0.language == language })
            speech.selectVoice("pocket.\(language).\(voice)")
            #expect(speech.selectedPocketVoice?.language == language)
        }
        for (language, text, voice) in cases.reversed() {
            speech.load(ReadingDocument(attributedText: NSAttributedString(string: text)))
            #expect(speech.selectedPocketVoice?.identifier == "pocket.\(language).\(voice)")
        }
        speech.load(ReadingDocument(attributedText: NSAttributedString(string: "これは日本語の文章です。選択した文章の言語に合った声で読み上げます。")))
        #expect(speech.document.language == "ja")
        #expect(speech.selectedPocketVoice == nil)
        #expect(speech.matchingVoices.allSatisfy { $0.language.hasPrefix("ja") })
    }
    @Test(.enabled(if: ProcessInfo.processInfo.environment["SPOKN_VERIFY_POCKET"] == "1"))
    func realLanguageSwitchReusesLoadedModels() async throws {
        let resources = PocketResources()
        for language in ["en", "de", "en", "de"] {
            let voice = try #require(PocketVoice.voices(for: language).first)
            let start = Date()
            try await resources.prepare(voice, alignment: true) { _ in }
            let elapsed = Date().timeIntervalSince(start)
            print("LANGUAGE LOAD \(language): \(elapsed)s, loads=\(await resources.modelLoadCount)")
            #expect(await resources.modelLoadCount <= 2)
        }
        #expect(await resources.modelLoadCount == 2)
    }
    @Test(.enabled(if: ProcessInfo.processInfo.environment["SPOKN_BENCHMARK_HQ"] == "1"))
    func benchmarkGermanQuality() async throws {
        let resources = PocketResources()
        let text = "Mit Spokn kannst du jeden Text entspannt anhören. Die Stimme klingt natürlich und begleitet dich durch den ganzen Absatz."
        for quality in [true, false] {
            let voice = PocketVoice(name: "Jürgen", key: "juergen", language: "de", highQuality: quality)
            try await resources.prepare(voice, alignment: true) { print($0) }
            for iteration in 0..<3 {
                let start = Date()
                let (audio, _) = try await resources.generate(text: text, voice: voice, alignment: true)
                let elapsed = Date().timeIntervalSince(start)
                let duration = try AVAudioPlayer(data: audio).duration
                print("BENCHMARK HQ=\(quality) run=\(iteration) generation=\(elapsed)s audio=\(duration)s RTF=\(elapsed/duration)")
                if iteration == 2 { try audio.write(to: URL(fileURLWithPath: "build/native/pocket-german-\(quality ? "hq" : "fast").wav")) }
            }
        }
    }
    @Test func selectionRangeUsesUTF16AndRejectsInvalidRanges() {
        let text = "Before 👩🏽‍💻 Grüße after"
        let range = (text as NSString).range(of: "👩🏽‍💻 Grüße")
        #expect(MacIntegration.selectedSubstring(text, range: range) == "👩🏽‍💻 Grüße")
        #expect(MacIntegration.selectedSubstring(text, range: NSRange(location: NSNotFound, length: 1)) == nil)
        #expect(MacIntegration.selectedSubstring(text, range: NSRange(location: 0, length: Int.max)) == nil)
        #expect(MacIntegration.selectedSubstring(text, range: NSRange(location: 0, length: 0)) == nil)
    }
    @Test func copyFallbackRequiresFreshTextAndRestoresAllFormats() async throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.setString("Original clipboard", forType: .string)
        board.setData(Data([1, 2, 3]), forType: NSPasteboard.PasteboardType("test.custom"))
        let stale = try await MacIntegration.copySelection(from: board) { }
        #expect(stale == nil)
        let fresh = try await MacIntegration.copySelection(from: board) {
            board.clearContents(); board.setString("Selected text 👋", forType: .string)
        }
        #expect(fresh?.string == "Selected text 👋")
        #expect(board.string(forType: .string) == "Original clipboard")
        #expect(board.data(forType: NSPasteboard.PasteboardType("test.custom")) == Data([1, 2, 3]))
    }
    @Test func audioAlignmentHandlesRepeatedWordsAndRecognitionMistakes() {
        let text = "Hello 👋 world. Hello brave new world."
        let document = ReadingDocument(attributedText: NSAttributedString(string: text))
        let heard = ["Hello", "world", "Hello", "wrong", "new", "world"]
        let timings = heard.enumerated().map { WordTiming(word: $0.element, startTime: Double($0.offset), endTime: Double($0.offset) + 0.5) }
        let result = AudioAlignment.match(text: text, words: document.words, timings: timings)
        #expect(result.map { (text as NSString).substring(with: $0.range) } == ["Hello", "world", "Hello", "new", "world"])
        #expect(result.map(\.start) == [0, 1, 2, 4, 5])
        #expect(result.allSatisfy { $0.end > $0.start })
    }
    @Test func pocketVoicesAreRememberedOnlyForTheirLanguage() throws {
        let suite = "SpoknTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let speech = SpeechController(preferences: defaults)
        speech.selectVoice("pocket.en.alba")
        #expect(speech.selectedPocketVoice?.key == "alba")
        speech.load(ReadingDocument(attributedText: NSAttributedString(string: "Dies ist ein deutscher Text. Wir hören aufmerksam zu.")))
        #expect(speech.selectedPocketVoice == nil)
        speech.selectVoice("pocket.en.alba")
        #expect(speech.selectedPocketVoice == nil)
        speech.selectVoice("pocket.de.juergen")
        #expect(speech.selectedPocketVoice?.name == "Jürgen")
        #expect(speech.canSpeak)
    }
    @Test func longPocketPassagesKeepExactTextAndOffsets() {
        let text = String(repeating: "A sentence with beautiful words and spaces. ", count: 40)
        let document = ReadingDocument(attributedText: NSAttributedString(string: text))
        let chunks = PocketSpeech.chunks(document: document, offset: 0)
        #expect(chunks.map { (text as NSString).substring(with: $0) }.joined() == text)
        #expect(chunks.allSatisfy { $0.length <= 260 })
    }
    @Test(.enabled(if: ProcessInfo.processInfo.environment["SPOKN_VERIFY_POCKET"] == "1"))
    func realPocketVoicesProduceAudioAndWordTimings() async throws {
        let resources = PocketResources()
        let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("build/native")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for (language, text) in [("en", "Hello world. This voice runs entirely on your Mac."), ("de", "Hallo Welt. Diese Stimme läuft direkt auf deinem Mac.")] {
            for voice in PocketVoice.voices(for: language) {
            try await resources.prepare(voice, alignment: true) { message in print(message) }
            let (audio, timings) = try await resources.generate(text: text, voice: voice, alignment: true)
            let player = try AVAudioPlayer(data: audio)
            #expect(player.duration > 1)
            #expect(audio.count > 24_000)
            let document = ReadingDocument(attributedText: NSAttributedString(string: text))
            let matched = AudioAlignment.match(text: text, words: document.words, timings: timings)
            #expect(matched.count >= document.words.count / 2)
            #expect(matched.allSatisfy { $0.start < player.duration && $0.end <= player.duration + 0.2 })
            try audio.write(to: output.appendingPathComponent("pocket-\(language)-\(voice.key)-check.wav"))
            print("POCKET VERIFIED \(language)/\(voice.key): \(player.duration)s, \(matched.count)/\(document.words.count) words matched; \(timings.map(\.word).joined(separator: " "))")
            }
        }
    }
    @Test(.enabled(if: ProcessInfo.processInfo.environment["SPOKN_VERIFY_POCKET"] == "1"))
    func realGermanPlaybackDoesNotBufferAtDoubleSpeed() async throws {
        let speech = PocketSpeech()
        defer { speech.stop() }
        let text = "Hallo Welt. Diese Stimme läuft direkt auf deinem Mac. Mit Spokn kannst du längere Texte entspannt anhören. Die nächsten Sätze werden schon vorbereitet, während die aktuelle Passage spielt. Auch bei hohem Tempo soll die Wiedergabe gleichmäßig weiterlaufen. Der ganze Satz bleibt dezent markiert und das aktuelle Wort leuchtet etwas stärker. Wir prüfen mehrere Absätze und achten dabei besonders auf die Übergänge. Zum Schluss verschwindet das Fenster und du kannst einfach weiterarbeiten."
        let document = ReadingDocument(attributedText: NSAttributedString(string: text))
        var gaps: [TimeInterval] = []
        var finished = false
        var failure: String?
        var sentences: [NSRange] = []
        speech.rate = 2
        speech.onChunkStarted = { _, gap in gaps.append(gap) }
        speech.onSentence = { sentences.append($0) }
        speech.onFinish = { finished = true }
        speech.onError = { failure = $0 }
        speech.start(document: document, offset: 0, voice: PocketVoice(name: "Jürgen", key: "juergen", language: "de"))
        for _ in 0..<1200 where !finished && failure == nil { try await Task.sleep(for: .milliseconds(100)) }
        #expect(failure == nil)
        #expect(finished)
        #expect(gaps.count == PocketSpeech.chunks(document: document, offset: 0).count)
        #expect(gaps.count >= 3)
        #expect(gaps.dropFirst().allSatisfy { $0 < 0.15 }, "Audio must already be ready at sentence boundaries: \(gaps)")
        #expect(Set(sentences.map(\.location)).count >= 6)
        print("GERMAN 2× CHUNK GAPS: \(gaps)")
    }
    @Test(.enabled(if: ProcessInfo.processInfo.environment["SPOKN_VERIFY_POCKET"] == "1"))
    func realPocketPlaybackAutoplaysPausesAndChangesSpeed() async throws {
        let suite = "SpoknPlayback.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let controller = SpeechController(preferences: defaults)
        defer { controller.stop(); defaults.removePersistentDomain(forName: suite) }
        controller.load(ReadingDocument(attributedText: NSAttributedString(string: "This is a longer passage to check automatic playback, word highlighting, and changing the reading speed while we listen.")))
        controller.selectVoice("pocket.en.alba")
        var words: [NSRange] = []
        controller.onWord = { words.append($0) }
        controller.start()
        for _ in 0..<300 where words.isEmpty && controller.playbackError == nil {
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(controller.playbackError == nil)
        try #require(!words.isEmpty, "Pocket TTS must emit real word timings during playback")
        controller.toggle()
        #expect(controller.state == .paused)
        let pausedPosition = controller.cursor.restartOffset
        try await Task.sleep(for: .milliseconds(400))
        #expect(controller.cursor.restartOffset == pausedPosition)
        controller.setRate(2)
        #expect(controller.state == .paused)
        controller.toggle()
        #expect(controller.state == .speaking)
        for _ in 0..<200 where controller.state != .finished && controller.playbackError == nil {
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(controller.playbackError == nil)
        #expect(controller.state == .finished)
        #expect(words.count > 2)
        #expect(words.map(\.location) == words.map(\.location).sorted())
    }

}
