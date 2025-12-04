import AVFoundation
import Combine
import NaturalLanguage

/// Represents an available system voice
struct VoiceOption: Identifiable, Hashable {
    let id: String
    let name: String
    let language: String
    let quality: AVSpeechSynthesisVoiceQuality

    var displayName: String {
        let qualityLabel = quality == .enhanced ? " (Premium)" : ""
        return "\(name)\(qualityLabel)"
    }

    var voice: AVSpeechSynthesisVoice? {
        AVSpeechSynthesisVoice(identifier: id)
    }
}

/// Service that handles text-to-speech with word-by-word progress callbacks
final class SpeechService: NSObject, ObservableObject {

    // MARK: - Published Properties

    @Published var isSpeaking: Bool = false
    @Published var isPaused: Bool = false
    @Published var currentWordRange: Range<String.Index>?
    @Published var currentSentence: String = ""
    @Published var currentSentenceRange: Range<String.Index>?
    @Published var currentWordInSentenceRange: Range<String.Index>?
    @Published var progress: Double = 0.0

    /// Speech rate multiplier (0.5 = half speed, 1.0 = normal, 3.0 = triple)
    @Published var rate: Float = 1.0

    /// Available German voices
    @Published private(set) var germanVoices: [VoiceOption] = []

    /// Available English voices
    @Published private(set) var englishVoices: [VoiceOption] = []

    /// Selected German voice identifier
    @Published var selectedGermanVoiceId: String? {
        didSet {
            if let id = selectedGermanVoiceId {
                UserDefaults.standard.set(id, forKey: "selectedGermanVoice")
            }
        }
    }

    /// Selected English voice identifier
    @Published var selectedEnglishVoiceId: String? {
        didSet {
            if let id = selectedEnglishVoiceId {
                UserDefaults.standard.set(id, forKey: "selectedEnglishVoice")
            }
        }
    }

    // MARK: - Properties

    private let synthesizer = AVSpeechSynthesizer()
    private var currentText: String = ""
    private var currentLanguage: String = "en"
    private var currentUtterance: AVSpeechUtterance?
    private var currentCharacterIndex: Int = 0
    private var isChangingRate: Bool = false
    private var sentences: [(text: String, range: Range<String.Index>)] = []

    // MARK: - Initialization

    override init() {
        super.init()
        synthesizer.delegate = self
        loadAvailableVoices()
        loadSavedVoicePreferences()
        loadSavedRatePreference()
    }

    /// Load saved speech rate from UserDefaults
    private func loadSavedRatePreference() {
        let savedRate = UserDefaults.standard.float(forKey: "speechRate")
        if savedRate > 0 {
            rate = savedRate
        } else {
            // Default to 1.0x if no saved rate
            rate = 1.0
        }
    }

    // MARK: - Voice Management

    /// Load all available system voices for German and English
    private func loadAvailableVoices() {
        let allVoices = AVSpeechSynthesisVoice.speechVoices()

        // Filter German voices
        germanVoices =
            allVoices
            .filter { $0.language.hasPrefix("de") }
            .map {
                VoiceOption(
                    id: $0.identifier, name: $0.name, language: $0.language, quality: $0.quality)
            }
            .sorted { lhs, rhs in
                // Sort by quality (premium first), then by name
                if lhs.quality != rhs.quality {
                    return lhs.quality == .enhanced
                }
                return lhs.name < rhs.name
            }

        // Filter English voices
        englishVoices =
            allVoices
            .filter { $0.language.hasPrefix("en") }
            .map {
                VoiceOption(
                    id: $0.identifier, name: $0.name, language: $0.language, quality: $0.quality)
            }
            .sorted { lhs, rhs in
                // Sort by quality (premium first), then by name
                if lhs.quality != rhs.quality {
                    return lhs.quality == .enhanced
                }
                return lhs.name < rhs.name
            }
    }

    /// Load saved voice preferences from UserDefaults
    private func loadSavedVoicePreferences() {
        // Load saved German voice or pick first premium voice
        if let savedGerman = UserDefaults.standard.string(forKey: "selectedGermanVoice"),
            germanVoices.contains(where: { $0.id == savedGerman })
        {
            selectedGermanVoiceId = savedGerman
        } else {
            // Default to first premium voice, or first available
            selectedGermanVoiceId =
                germanVoices.first(where: { $0.quality == .enhanced })?.id
                ?? germanVoices.first?.id
        }

        // Load saved English voice or pick first premium voice
        if let savedEnglish = UserDefaults.standard.string(forKey: "selectedEnglishVoice"),
            englishVoices.contains(where: { $0.id == savedEnglish })
        {
            selectedEnglishVoiceId = savedEnglish
        } else {
            // Default to first premium voice, or first available
            selectedEnglishVoiceId =
                englishVoices.first(where: { $0.quality == .enhanced })?.id
                ?? englishVoices.first?.id
        }
    }

    /// Get the currently selected voice for a language
    private func voice(for language: String) -> AVSpeechSynthesisVoice? {
        if language.hasPrefix("de") {
            if let id = selectedGermanVoiceId {
                return AVSpeechSynthesisVoice(identifier: id)
            }
            return AVSpeechSynthesisVoice(language: "de-DE")
        } else {
            if let id = selectedEnglishVoiceId {
                return AVSpeechSynthesisVoice(identifier: id)
            }
            return AVSpeechSynthesisVoice(language: "en-US")
        }
    }

    // MARK: - Public Methods

    /// Speak the given text in the specified language
    /// - Parameters:
    ///   - text: The text to speak
    ///   - language: The language code ("de" for German, "en" for English)
    func speak(text: String, language: String) {
        // Stop any current speech
        synthesizer.stopSpeaking(at: .immediate)

        currentText = text
        currentLanguage = language
        currentCharacterIndex = 0

        // Parse sentences for tracking
        sentences = parseSentences(from: text)

        speakFromCurrentPosition()
    }

    /// Parse text into sentences with their ranges
    private func parseSentences(from text: String) -> [(text: String, range: Range<String.Index>)] {
        var result: [(text: String, range: Range<String.Index>)] = []

        // Use NLTokenizer for better sentence detection
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text

        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let sentenceText = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentenceText.isEmpty {
                result.append((text: sentenceText, range: range))
            }
            return true
        }

        // Fallback if no sentences found
        if result.isEmpty && !text.isEmpty {
            result.append((text: text, range: text.startIndex..<text.endIndex))
        }

        return result
    }

    /// Find which sentence contains the given character index
    private func findCurrentSentence(at characterIndex: Int) {
        guard !currentText.isEmpty, characterIndex < currentText.count else { return }

        let targetIndex = currentText.index(currentText.startIndex, offsetBy: characterIndex)

        for sentence in sentences {
            if sentence.range.contains(targetIndex)
                || (targetIndex == sentence.range.upperBound
                    && sentence.range.upperBound == currentText.endIndex)
            {
                currentSentence = sentence.text
                currentSentenceRange = sentence.range

                // Calculate word range relative to sentence
                if let wordRange = currentWordRange {
                    // Convert word range to be relative to sentence start
                    let sentenceStart = sentence.range.lowerBound
                    if wordRange.lowerBound >= sentenceStart
                        && wordRange.upperBound <= sentence.range.upperBound
                    {
                        let relativeStart = currentText.distance(
                            from: sentenceStart, to: wordRange.lowerBound)
                        let relativeEnd = currentText.distance(
                            from: sentenceStart, to: wordRange.upperBound)

                        if relativeStart >= 0 && relativeEnd <= sentence.text.count {
                            let sentenceStartIndex = sentence.text.index(
                                sentence.text.startIndex, offsetBy: relativeStart)
                            let sentenceEndIndex = sentence.text.index(
                                sentence.text.startIndex,
                                offsetBy: min(relativeEnd, sentence.text.count))
                            currentWordInSentenceRange = sentenceStartIndex..<sentenceEndIndex
                        }
                    }
                }
                return
            }
        }
    }

    /// Speak from the current character position (used for rate changes)
    private func speakFromCurrentPosition() {
        guard !currentText.isEmpty else { return }

        // Get remaining text from current position
        let startIndex = currentText.index(
            currentText.startIndex, offsetBy: min(currentCharacterIndex, currentText.count))
        let remainingText = String(currentText[startIndex...])

        guard !remainingText.isEmpty else {
            reset()
            return
        }

        let utterance = AVSpeechUtterance(string: remainingText)
        utterance.voice = voice(for: currentLanguage)

        // Convert user-facing rate (0.5x - 3.0x) to AVSpeechUtterance rate (0.0 - 1.0)
        //
        // AVSpeechUtterance rate scale:
        // - 0.0 = minimum (very slow)
        // - 0.5 = default
        // - 1.0 = maximum (very fast)
        //
        // Industry standard (YouTube, Pocket Casts, Speechify):
        // - 1x = normal comfortable speed (~150 WPM for Speechify)
        // - 2x = twice as fast (linear scaling)
        // - 0.5x = half speed
        //
        // We set our "1x" baseline at 0.35 (slower than AVSpeech default of 0.5)
        // This gives a comfortable listening speed similar to Speechify
        // Then we scale linearly: 2x = 0.70, 3x = 1.05 (clamped to 1.0)
        //
        // User rate -> AVSpeech rate mapping (linear):
        // 0.5x -> 0.175
        // 1.0x -> 0.35  (comfortable baseline)
        // 1.5x -> 0.525
        // 2.0x -> 0.70
        // 2.5x -> 0.875
        // 3.0x -> 1.0 (clamped)

        let baselineRate: Float = 0.35  // Our "1.0x" speed - comfortable listening
        let avRate = baselineRate * rate

        // Clamp to valid range
        utterance.rate = max(
            AVSpeechUtteranceMinimumSpeechRate,
            min(AVSpeechUtteranceMaximumSpeechRate, avRate))

        currentUtterance = utterance
        isSpeaking = true
        isPaused = false
        synthesizer.speak(utterance)
    }

    /// Change the speech rate - restarts from current position with new rate
    func setRate(_ newRate: Float) {
        let wasPlaying = isSpeaking && !isPaused

        // Save ALL state before stopping
        let savedText = currentText
        let savedLanguage = currentLanguage
        let savedIndex = currentCharacterIndex
        let savedSentences = sentences
        let savedCurrentSentence = currentSentence
        let savedCurrentSentenceRange = currentSentenceRange
        let savedProgress = progress

        rate = newRate

        // Save rate preference
        UserDefaults.standard.set(newRate, forKey: "speechRate")

        // If currently speaking, restart from current position with new rate
        if wasPlaying && !savedText.isEmpty && savedIndex > 0 {
            // Set flag to prevent didCancel from interfering
            isChangingRate = true

            synthesizer.stopSpeaking(at: .immediate)

            // Restore ALL state immediately (don't wait for async)
            currentText = savedText
            currentLanguage = savedLanguage
            currentCharacterIndex = savedIndex
            sentences = savedSentences
            currentSentence = savedCurrentSentence
            currentSentenceRange = savedCurrentSentenceRange
            progress = savedProgress

            // Small delay to let the stop complete, then restart
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard let self = self else { return }
                self.isChangingRate = false
                guard !self.currentText.isEmpty else { return }
                self.speakFromCurrentPosition()
            }
        }
    }

    /// Pause the current speech
    func pause() {
        guard isSpeaking && !isPaused else { return }
        synthesizer.pauseSpeaking(at: .word)
    }

    /// Resume paused speech
    func resume() {
        guard isPaused else { return }
        synthesizer.continueSpeaking()
    }

    /// Toggle between pause and resume
    func togglePause() {
        if isPaused {
            resume()
        } else {
            pause()
        }
    }

    /// Stop speaking completely
    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        reset()
    }

    // MARK: - Private Methods

    private func reset() {
        currentText = ""
        currentUtterance = nil
        currentWordRange = nil
        currentSentence = ""
        currentSentenceRange = nil
        currentWordInSentenceRange = nil
        sentences = []
        currentCharacterIndex = 0
        progress = 0.0
        isSpeaking = false
        isPaused = false
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension SpeechService: AVSpeechSynthesizerDelegate {

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didStart utterance: AVSpeechUtterance
    ) {
        DispatchQueue.main.async { [weak self] in
            self?.isSpeaking = true
            self?.isPaused = false
        }
    }

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didPause utterance: AVSpeechUtterance
    ) {
        DispatchQueue.main.async { [weak self] in
            self?.isPaused = true
        }
    }

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didContinue utterance: AVSpeechUtterance
    ) {
        DispatchQueue.main.async { [weak self] in
            self?.isPaused = false
        }
    }

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            // Don't reset if we're in the middle of a rate change
            if !self.isChangingRate {
                self.reset()
            }
        }
    }

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        // Don't reset here - might be restarting with new rate
    }

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        willSpeakRangeOfSpeechString characterRange: NSRange,
        utterance: AVSpeechUtterance
    ) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, !self.currentText.isEmpty else { return }

            // The characterRange is relative to the utterance text (which may be a substring)
            // We need to calculate the actual position in the full text
            // baseOffset is where we started speaking from in the original text
            let baseOffset = self.currentText.count - utterance.speechString.count
            let actualLocation = baseOffset + characterRange.location
            let actualRange = NSRange(location: actualLocation, length: characterRange.length)

            // Update currentCharacterIndex to track where we are for rate change resume
            // This is the position of the word we're about to speak
            self.currentCharacterIndex = actualLocation

            // Convert NSRange to Range<String.Index> safely
            if actualRange.location + actualRange.length <= self.currentText.count,
                let range = Range(actualRange, in: self.currentText)
            {
                self.currentWordRange = range
            }

            // Update current sentence tracking
            self.findCurrentSentence(at: actualLocation)

            // Calculate progress based on full text (clamped to valid range)
            let endPosition = actualLocation + characterRange.length
            let rawProgress = Double(endPosition) / Double(self.currentText.count)
            self.progress = min(1.0, max(0.0, rawProgress))
        }
    }
}
