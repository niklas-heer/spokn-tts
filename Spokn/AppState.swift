import Combine
import SwiftUI

/// Central app state that coordinates all services
@MainActor
final class AppState: ObservableObject {

    // MARK: - Services

    let speechService = SpeechService()

    // MARK: - Forwarded Speech State (for SwiftUI reactivity)

    @Published var currentWordRange: Range<String.Index>?
    @Published var currentSentence: String = ""
    @Published var currentSentenceRange: Range<String.Index>?
    @Published var currentWordInSentenceRange: Range<String.Index>?
    @Published var speechProgress: Double = 0.0
    @Published var isSpeaking: Bool = false
    @Published var isPaused: Bool = false
    @Published var speechRate: Float = 1.0

    // MARK: - State

    /// The clipboard content with type information
    @Published var clipboardContent: ClipboardContentType = .empty

    /// The original text (may contain Markdown)
    @Published var currentText: String = ""

    /// Plain text for speech (Markdown stripped)
    @Published var speechText: String = ""

    @Published var detectedLanguage: LanguageDetector.Language = .english
    @Published var isOverlayVisible: Bool = false

    /// Manual language override (nil = auto-detect)
    @Published var languageOverride: LanguageDetector.Language? = nil

    // MARK: - Private

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Computed

    var effectiveLanguage: LanguageDetector.Language {
        languageOverride ?? detectedLanguage
    }

    // MARK: - Initialization

    init() {
        setupBindings()
    }

    private func setupBindings() {
        // Forward speech service state to AppState for SwiftUI reactivity
        speechService.$currentWordRange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] range in
                self?.currentWordRange = range
            }
            .store(in: &cancellables)

        speechService.$currentSentence
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sentence in
                self?.currentSentence = sentence
            }
            .store(in: &cancellables)

        speechService.$currentSentenceRange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] range in
                self?.currentSentenceRange = range
            }
            .store(in: &cancellables)

        speechService.$currentWordInSentenceRange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] range in
                self?.currentWordInSentenceRange = range
            }
            .store(in: &cancellables)

        speechService.$progress
            .receive(on: DispatchQueue.main)
            .sink { [weak self] progress in
                self?.speechProgress = progress
            }
            .store(in: &cancellables)

        speechService.$isSpeaking
            .receive(on: DispatchQueue.main)
            .sink { [weak self] speaking in
                self?.isSpeaking = speaking
            }
            .store(in: &cancellables)

        speechService.$isPaused
            .receive(on: DispatchQueue.main)
            .sink { [weak self] paused in
                self?.isPaused = paused
            }
            .store(in: &cancellables)

        speechService.$rate
            .receive(on: DispatchQueue.main)
            .sink { [weak self] rate in
                self?.speechRate = rate
            }
            .store(in: &cancellables)
    }

    // MARK: - Speech Rate

    func setSpeechRate(_ rate: Float) {
        speechRate = rate
        speechService.setRate(rate)
    }

    // MARK: - Actions

    /// Called when the global hotkey is triggered
    func onHotkeyTriggered() {
        print("[Spokn] Hotkey triggered")

        // Get selected content with type detection
        let content = ClipboardManager.getSelectedContent()

        guard !content.isEmpty else {
            print("[Spokn] No text selected, aborting")
            return
        }

        // Store the content with its type
        clipboardContent = content
        currentText = content.displayText
        speechText = content.speechText

        print("[Spokn] Content type: \(contentTypeDescription)")

        // Detect language from the speech text
        detectedLanguage = LanguageDetector.detect(text: speechText)

        print("[Spokn] Language detected: \(detectedLanguage.displayName), starting speech")

        // Show overlay and start speaking (use stripped text for speech)
        isOverlayVisible = true
        speechService.speak(text: speechText, language: effectiveLanguage.rawValue)
    }

    /// Description of the current content type for logging
    private var contentTypeDescription: String {
        switch clipboardContent {
        case .html: return "HTML"
        case .rtf: return "RTF"
        case .markdown: return "Markdown"
        case .plainText: return "Plain Text"
        case .empty: return "Empty"
        }
    }

    /// Stop playback and hide overlay
    func stop() {
        speechService.stop()
        isOverlayVisible = false
    }

    /// Close overlay (stops if playing)
    func closeOverlay() {
        speechService.stop()
        isOverlayVisible = false
        currentText = ""
    }

    /// Toggle pause/resume
    func togglePause() {
        speechService.togglePause()
    }

    /// Restart playback
    func restartPlayback() {
        speechService.speak(text: speechText, language: effectiveLanguage.rawValue)
    }
}
