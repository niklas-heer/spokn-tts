import AVFoundation
import AppKit

@MainActor final class SpeechController: NSObject, AVSpeechSynthesizerDelegate {
    enum State { case idle, speaking, paused, finished }
    private(set) var state: State = .idle
    private(set) var cursor = SpeechCursor()
    private(set) var document = ReadingDocument(attributedText: NSAttributedString(string: ""))
    private var synthesizer = AVSpeechSynthesizer()
    private let pocket = PocketSpeech()
    private(set) var preparationStatus: String?
    var pocketVoices: [PocketVoice] { PocketVoice.voices(for: document.language) }
    var selectedPocketVoice: PocketVoice? { pocketVoices.first { $0.identifier == preferredVoiceID } }
    var activeVoiceName: String { selectedPocketVoice.map { "\($0.name) · Pocket TTS" } ?? selectedVoice?.name ?? "No voice" }
    var canSpeak: Bool { selectedPocketVoice != nil || selectedVoice != nil }
    private var utterance: AVSpeechUtterance?
    private var token: UUID?
    private var restartOnResume = false
    private var startupWatchdog: DispatchWorkItem?
    private(set) var isStarting = false
    private(set) var isPreviewing = false
    private var previewReturnState: State = .idle
    private(set) var playbackError: String?
    var onChange: (() -> Void)?
    var onWord: ((NSRange) -> Void)?
    var onClearWord: (() -> Void)?
    var onSentence: ((NSRange) -> Void)?
    private(set) var rate: Float
    var voices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices().sorted {
            if $0.language != $1.language { return $0.language < $1.language }
            if $0.quality.rawValue != $1.quality.rawValue { return $0.quality.rawValue > $1.quality.rawValue }
            return $0.name < $1.name
        }
    }
    private let preferences: UserDefaults
    private(set) var matchingVoices: [AVSpeechSynthesisVoice] = []
    var preferredVoiceID: String? { preferences.string(forKey: "native.voice.\(document.language)") }
    static func snappedRate(_ value: Float) -> Float {
        guard value.isFinite else { return 1 }
        return min(2, max(0.5, (value * 4).rounded() / 4))
    }
    static func voiceLanguage(_ voiceLanguage: String, matches detected: String) -> Bool {
        let voice = Locale(identifier: voiceLanguage).language
        let text = Locale(identifier: detected).language
        guard voice.languageCode == text.languageCode else { return false }
        // Chinese script matters: do not offer a Traditional voice for Simplified text.
        if detected.hasPrefix("zh-") { return voice.script == text.script }
        return true
    }
    func selectVoice(_ identifier: String?) {
        guard identifier == nil || matchingVoices.contains(where: { $0.identifier == identifier }) || pocketVoices.contains(where: { $0.identifier == identifier }) else { return }
        preferences.set(identifier, forKey: "native.voice.\(document.language)")
        selectedVoice = chooseVoice()
        playbackError = nil
        restartIfNeeded(); onChange?()
    }
    func refreshVoices() {
        let previous = selectedVoice?.identifier
        matchingVoices = voices.filter { Self.voiceLanguage($0.language, matches: document.language) }
        selectedVoice = chooseVoice()
        if previous != selectedVoice?.identifier { restartIfNeeded() }
        onChange?()
    }
    private(set) var selectedVoice: AVSpeechSynthesisVoice?
    private func chooseVoice() -> AVSpeechSynthesisVoice? {
        let matches = matchingVoices
        if let preferredVoiceID, let voice = matches.first(where: { $0.identifier == preferredVoiceID }) { return voice }
        return matches.first(where: { $0.quality == .premium })
            ?? matches.first(where: { $0.quality == .enhanced })
            ?? AVSpeechSynthesisVoice(language: document.language) ?? matches.first
    }
    override convenience init() { self.init(preferences: .standard) }
    init(preferences: UserDefaults) {
        self.preferences = preferences
        let stored = preferences.float(forKey: "native.rate")
        rate = Self.snappedRate(stored >= 0.5 ? stored : 1)
        super.init(); synthesizer.delegate = self
        matchingVoices = voices.filter { Self.voiceLanguage($0.language, matches: document.language) }
        selectedVoice = chooseVoice()
        pocket.onStatus = { [weak self] message in
            guard let self else { return }
            self.preparationStatus = message; self.isStarting = message != nil; self.onChange?()
        }
        pocket.onWord = { [weak self] range in
            guard let self, !self.isPreviewing else { return }
            guard let range else { self.onClearWord?(); return }
            let relative = NSRange(location: range.location - self.cursor.base, length: range.length)
            if let token = self.token, let accepted = self.cursor.accept(relative, session: token) { self.onWord?(accepted) }
            self.onChange?()
        }
        pocket.onSentence = { [weak self] range in self?.onSentence?(range) }
        pocket.onFinish = { [weak self] in
            guard let self else { return }
            self.isStarting = false; self.preparationStatus = nil
            if self.isPreviewing { self.isPreviewing = false; self.state = self.previewReturnState }
            else { self.state = .finished }
            self.onChange?()
        }
        pocket.onError = { [weak self] in self?.failPlayback($0) }
    }
    func load(_ document: ReadingDocument, position: Int = 0) {
        stop(); self.document = document
        matchingVoices = voices.filter { Self.voiceLanguage($0.language, matches: document.language) }
        selectedVoice = chooseVoice()
        _ = cursor.begin(length: document.utf16Count, offset: document.wordStart(near: position)); cursor.invalidate()
        onChange?()
    }
    func warmLastVoice() {
        let language = preferences.string(forKey: "native.lastPocketLanguage") ?? document.language
        let identifier = preferences.string(forKey: "native.voice.\(language)")
        if let voice = PocketVoice.voices(for: language).first(where: { $0.identifier == identifier }) { pocket.warm(voice) }
    }
    func toggle() {
        if isPreviewing {
            invalidateUtterance(); isPreviewing = false; state = previewReturnState
            onChange?(); return
        }
        switch state {
        case .speaking:
            if selectedPocketVoice != nil { pocket.pause(); state = .paused; onChange?(); return }
            if synthesizer.pauseSpeaking(at: .immediate) { confirmedPlayback(); state = .paused; onChange?() }
        case .paused:
            if restartOnResume { start(at: cursor.restartOffset) }
            else if selectedPocketVoice != nil { pocket.resume(); state = .speaking; onChange?() }
            else if synthesizer.continueSpeaking() { state = .speaking; onChange?() }
        case .idle: start(at: cursor.restartOffset)
        case .finished: start(at: 0)
        }
    }
    func start(at offset: Int = 0) {
        guard !document.words.isEmpty else { return }
        guard canSpeak else {
            playbackError = "No voice for this language. Choose Get more voices… above."; onChange?(); return
        }
        invalidateUtterance()
        isPreviewing = false
        let position = document.wordStart(near: min(offset, max(0, document.utf16Count - 1)))
        if let voice = selectedPocketVoice {
            preferences.set(document.language, forKey: "native.lastPocketLanguage")
            token = cursor.begin(length: document.utf16Count, offset: position)
            state = .speaking; isStarting = true; restartOnResume = false; playbackError = nil
            preparationStatus = "Preparing Pocket TTS…"; pocket.rate = rate
            pocket.start(document: document, offset: position, voice: voice)
            onChange?(); return
        }
        let speech = AVSpeechUtterance(string: (document.text as NSString).substring(from: position))
        speech.voice = selectedVoice
        // A speed change creates a fresh utterance at the current word. No timer or delayed restart.
        speech.rate = max(AVSpeechUtteranceMinimumSpeechRate, min(AVSpeechUtteranceMaximumSpeechRate, AVSpeechUtteranceDefaultSpeechRate * rate))
        token = cursor.begin(length: document.utf16Count, offset: position)
        utterance = speech; restartOnResume = false; state = .speaking
        beginSpeaking(speech)
    }
    func previewVoice() {
        guard canSpeak else { return }
        let returning = isPreviewing ? previewReturnState : state
        invalidateUtterance()
        previewReturnState = returning == .speaking ? .paused : returning
        isPreviewing = true; restartOnResume = true
        let samples = [
            "en": "Hello. This is the voice I will use to read your text.",
            "de": "Hallo. Mit dieser Stimme lese ich dir deinen Text vor.",
            "fr": "Bonjour. Voici la voix que je vais utiliser pour lire votre texte.",
            "es": "Hola. Esta es la voz que usaré para leer tu texto.",
            "it": "Ciao. Questa è la voce che userò per leggere il tuo testo.",
            "pt": "Olá. Esta é a voz que vou usar para ler o seu texto.",
            "ja": "こんにちは。この声で文章を読み上げます。",
            "zh": "你好。我会用这个声音朗读你的文字。"
        ]
        let language = document.language
        let sample = document.sentences.first.map { (document.text as NSString).substring(with: $0) }
        let previewText = sample ?? samples[language] ?? activeVoiceName
        if let voice = selectedPocketVoice {
            let previewDocument = ReadingDocument(attributedText: NSAttributedString(string: previewText))
            state = .speaking; isStarting = true; playbackError = nil
            preparationStatus = "Preparing Pocket TTS preview…"; pocket.rate = 1
            pocket.start(document: previewDocument, offset: 0, voice: voice, preview: true)
            onChange?(); return
        }
        let speech = AVSpeechUtterance(string: previewText)
        speech.voice = selectedVoice; speech.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance = speech; state = .speaking
        beginSpeaking(speech)
    }
    private func beginSpeaking(_ speech: AVSpeechUtterance) {
        // A stopped synthesizer can still be cancelling its queue. Start a clean
        // engine so changing voices/rate cannot enqueue behind that cancellation.
        synthesizer.delegate = nil
        synthesizer = AVSpeechSynthesizer(); synthesizer.delegate = self
        playbackError = nil; isStarting = true
        let work = DispatchWorkItem { [weak self, weak speech] in
            guard let self, let speech, self.utterance === speech, self.isStarting else { return }
            self.failPlayback("\(speech.voice?.name ?? "This voice") could not start. Try another voice or finish its download in System Settings.")
        }
        startupWatchdog = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: work)
        onChange?(); synthesizer.speak(speech)
    }
    private func confirmedPlayback() {
        startupWatchdog?.cancel(); startupWatchdog = nil; isStarting = false
    }
    private func failPlayback(_ message: String) {
        invalidateUtterance(); isPreviewing = false; state = .idle
        playbackError = message; onChange?()
    }
    private func invalidateUtterance() {
        // Invalidate BEFORE stopping: cancelled/queued callbacks must not mutate a newer reading.
        startupWatchdog?.cancel(); startupWatchdog = nil; isStarting = false
        utterance = nil; token = nil; cursor.invalidate()
        synthesizer.stopSpeaking(at: .immediate)
        pocket.stop(); preparationStatus = nil
    }
    func stop() { invalidateUtterance(); isPreviewing = false; playbackError = nil; state = .idle; restartOnResume = false; _ = cursor.begin(length: document.utf16Count, offset: 0); cursor.invalidate(); onChange?() }
    func setRate(_ value: Float) {
        guard value.isFinite else { return }
        rate = Self.snappedRate(value); preferences.set(rate, forKey: "native.rate")
        if selectedPocketVoice != nil { pocket.rate = rate }
        else { restartIfNeeded() }
        onChange?()
    }
    private func restartIfNeeded() {
        let position = cursor.restartOffset
        if isPreviewing { previewVoice() }
        else if state == .speaking { start(at: position) }
        else if state == .paused { invalidateUtterance(); restartOnResume = true }
    }
    func seek(to offset: Int) {
        let position = document.wordStart(near: offset)
        if state == .speaking { start(at: position) }
        else {
            invalidateUtterance(); _ = cursor.begin(length: document.utf16Count, offset: position); cursor.invalidate()
            restartOnResume = true; state = .paused
            onChange?()
        }
        // Show the destination immediately, even while a local model prepares its audio.
        if let range = document.words.first(where: { $0.location == position }) { onWord?(range) }
    }
    func skip(_ direction: Int) {
        let position = document.sentenceStart(from: cursor.restartOffset, direction: direction)
        if position >= document.utf16Count { invalidateUtterance(); state = .finished; onChange?() }
        else { seek(to: position) }
    }
    // AVFoundation owns and mutates utterances. Across the callback boundary we
    // compare identity only; retaining the object prevents address reuse by a new utterance.
    nonisolated private final class UtteranceIdentity: @unchecked Sendable {
        private let retained: AVSpeechUtterance
        let id: ObjectIdentifier
        init(_ utterance: AVSpeechUtterance) { retained = utterance; id = ObjectIdentifier(utterance) }
    }
    nonisolated private func withCurrent(_ candidate: AVSpeechUtterance, _ body: @escaping @MainActor @Sendable (SpeechController) -> Void) {
        let identity = UtteranceIdentity(candidate)
        DispatchQueue.main.async { [weak self] in
            guard let self, let current = self.utterance, ObjectIdentifier(current) == identity.id else { return }; body(self)
        }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString range: NSRange, utterance: AVSpeechUtterance) {
        withCurrent(utterance) { controller in
            controller.confirmedPlayback()
            if controller.isPreviewing { controller.onChange?(); return }
            guard let token = controller.token, let word = controller.cursor.accept(range, session: token) else { return }
            controller.onWord?(word); controller.onChange?()
        }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        withCurrent(utterance) { controller in
            controller.confirmedPlayback()
            if controller.isPreviewing {
                controller.isPreviewing = false; controller.state = controller.previewReturnState
            } else { controller.state = .finished }
            controller.onChange?()
        }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        withCurrent(utterance) { controller in
            controller.failPlayback("Playback was interrupted. Press Play to retry or choose another voice.")
        }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        withCurrent(utterance) { controller in controller.state = .paused; controller.onChange?() }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {
        withCurrent(utterance) { controller in controller.state = .speaking; controller.onChange?() }
    }
}
