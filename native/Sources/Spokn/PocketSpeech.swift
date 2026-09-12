import AppKit
import AVFoundation
import FluidAudio

nonisolated struct PocketVoice: Sendable {
    let name: String
    let key: String
    let language: String
    var highQuality = false
    var identifier: String { "pocket.\(language).\(key)\(highQuality ? ".hq" : "")" }
    static func voices(for language: String) -> [PocketVoice] {
        let names: [(String, String)]
        switch language {
        case "en": names = [("Alba", "alba"), ("Marius", "marius"), ("Cosette", "cosette")]
        case "de": names = [("Jürgen", "juergen"), ("Alba", "alba")]
        case "fr": names = [("Estelle", "estelle"), ("Alba", "alba")]
        case "es": names = [("Lola", "lola"), ("Alba", "alba")]
        case "it": names = [("Giovanni", "giovanni"), ("Alba", "alba")]
        case "pt": names = [("Rafael", "rafael"), ("Alba", "alba")]
        default: names = []
        }
        return names.map { PocketVoice(name: $0.0, key: $0.1, language: language) }
    }
    var pack: PocketTtsLanguage {
        switch language {
        case "de": highQuality ? .german24L : .german
        case "fr": .french24L
        case "es": .spanish
        case "it": .italian
        case "pt": .portuguese
        default: .english
        }
    }
}

nonisolated struct AudioWord: Sendable {
    let range: NSRange
    let start: TimeInterval
    let end: TimeInterval
}

/// Matches recognized words back to the original UTF-16 text. Unmatched words
/// remain unhighlighted instead of inventing timestamps from character counts.
nonisolated enum AudioAlignment {
    static func match(text: String, words: [NSRange], timings: [WordTiming]) -> [AudioWord] {
        func normalized(_ value: String) -> String {
            value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
                .filter { $0.isLetter || $0.isNumber }
        }
        let original = text as NSString
        let source = words.map { normalized(original.substring(with: $0)) }
        let heard = timings.map { normalized($0.word) }
        // Sentence-sized inputs keep this dynamic-programming table small.
        var lengths = Array(repeating: Array(repeating: 0, count: heard.count + 1), count: source.count + 1)
        for i in source.indices.reversed() {
            for j in heard.indices.reversed() {
                lengths[i][j] = !source[i].isEmpty && source[i] == heard[j]
                    ? lengths[i + 1][j + 1] + 1 : max(lengths[i + 1][j], lengths[i][j + 1])
            }
        }
        var i = 0, j = 0
        var result: [AudioWord] = []
        while i < source.count && j < heard.count {
            if !source[i].isEmpty && source[i] == heard[j] {
                let time = timings[j]
                if time.startTime.isFinite, time.endTime.isFinite, time.startTime >= 0, time.endTime > time.startTime {
                    result.append(AudioWord(range: words[i], start: time.startTime, end: time.endTime))
                }
                i += 1; j += 1
            } else if lengths[i + 1][j] >= lengths[i][j + 1] { i += 1 }
            else { j += 1 }
        }
        return result
    }
}

/// Download callbacks can arrive for every network buffer. Coalesce equal labels
/// before hopping to the UI so first-use downloads do not flood the event loop.
nonisolated private final class PocketProgress: @unchecked Sendable {
    private let lock = NSLock()
    private var previous: String?
    private let callback: @Sendable (String) -> Void
    init(_ callback: @escaping @Sendable (String) -> Void) { self.callback = callback }
    func report(_ message: String) {
        let changed = lock.withLock {
            guard previous != message else { return false }
            previous = message; return true
        }
        if changed { callback(message) }
    }
}

/// Model inference lives on an actor, away from AppKit's event loop. Only one
/// two most recently used language packs stay resident; word timing is shared.
actor PocketResources {
    private var managers: [PocketTtsLanguage: PocketTtsManager] = [:]
    private var recent: [PocketTtsLanguage] = []
    private(set) var modelLoadCount = 0
    private var aligner: AsrManager?
    nonisolated static var directory: URL {
        URL.applicationSupportDirectory.appendingPathComponent("Spokn/Models", isDirectory: true)
    }
    nonisolated static func isDownloaded(_ voice: PocketVoice) -> Bool {
        let root = directory.appendingPathComponent("Models/pocket-tts/\(voice.pack.repoSubdirectory)")
        let required = ModelNames.PocketTTS.requiredModels(precision: .int8)
            .union(["constants_bin/\(voice.key).safetensors", "constants_bin/bos_before_voice.bin"])
        return required.allSatisfy { FileManager.default.fileExists(atPath: root.appendingPathComponent($0).path) }
    }
    func prepare(_ voice: PocketVoice, alignment: Bool, progress: @escaping @Sendable (String) -> Void) async throws {
        let reporter = PocketProgress(progress)
        let progress: @Sendable (String) -> Void = { reporter.report($0) }
        if managers[voice.pack] == nil {
            // Evict before loading to keep peak residency bounded as well.
            if recent.count >= 2 { managers.removeValue(forKey: recent.removeFirst()) }
            if !Self.isDownloaded(voice) { progress("Downloading Pocket TTS \(voice.language.uppercased()) voice pack…") }
            _ = try await PocketTtsResourceDownloader.ensureModels(language: voice.pack, directory: Self.directory, precision: .int8) { update in
                progress("Pocket TTS voice pack · \(Int(update.fractionCompleted * 100))%")
            }
            try Task.checkCancellation()
            progress("Loading Pocket TTS…")
            let next = PocketTtsManager(language: voice.pack, directory: Self.directory, precision: .int8, computeUnits: .avoidNeuralEngine)
            try await next.initialize()
            try Task.checkCancellation()
            managers[voice.pack] = next
            modelLoadCount += 1
        }
        recent.removeAll { $0 == voice.pack }; recent.append(voice.pack)
        if alignment, aligner == nil {
            progress("Preparing word timing · first use downloads a shared model…")
            let models = try await AsrModels.downloadAndLoad(to: Self.directory.appendingPathComponent("Alignment"), version: .v3, encoderPrecision: .int8, encoderComputeUnits: .cpuAndGPU) { update in
                progress("Word timing model · \(Int(update.fractionCompleted * 100))%")
            }
            try Task.checkCancellation()
            aligner = AsrManager(models: models)
        }
    }
    func generate(text: String, voice: PocketVoice, alignment: Bool) async throws -> (Data, [WordTiming]) {
        for attempt in 0..<2 {
            let result = try await generateAttempt(text: text, voice: voice, alignment: alignment)
            // A rare failed stochastic generation produces no recognizable
            // speech. Retry once before exposing that audio to the listener.
            if !alignment || !result.1.isEmpty { return result }
            if attempt == 0 { try Task.checkCancellation() }
        }
        throw MacIntegration.CaptureError(message: "This voice could not produce clear speech. Please try another voice.")
    }
    private func generateAttempt(text: String, voice: PocketVoice, alignment: Bool) async throws -> (Data, [WordTiming]) {
        guard let manager = managers[voice.pack] else { throw MacIntegration.CaptureError(message: "Pocket TTS is not ready.") }
        let data = try await manager.synthesize(text: text, voice: voice.key)
        try Task.checkCancellation()
        guard alignment, let aligner else { return (data, []) }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("Spokn-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: file) }
        try data.write(to: file, options: .atomic)
        var decoder = try TdtDecoderState()
        // Silence gives the recognizer context at both edges of short sentences.
        // Subtract that padding so timestamps still address the original audio.
        let samples = try AudioConverter(sampleRate: 16_000).resampleAudioFile(file)
        let padding = Array(repeating: Float(0), count: 8_000)
        let result = try await aligner.transcribe(padding + samples + padding, decoderState: &decoder)
        try Task.checkCancellation()
        let timings = buildWordTimings(from: result.tokenTimings ?? []).map {
            WordTiming(word: $0.word, startTime: max(0, $0.startTime - 0.5), endTime: min(Double(samples.count) / 16_000, $0.endTime - 0.5))
        }
        return (data, timings)
    }
}

private struct PreparedSpeech {
    let range: NSRange
    let player: AVAudioPlayer
    let words: [AudioWord]
}

/// A few seconds of lookahead absorb inference variation without retaining an
/// entire article in memory. Both producer and consumer run on the main actor;
/// only model inference leaves it.
private final class SpeechBuffer {
    var audio: [PreparedSpeech] = []
    var finished = false
    var error: Error?
    func waitForSpace() async throws {
        while audio.count >= 3 { try await Task.sleep(for: .milliseconds(20)) }
        try Task.checkCancellation()
    }
    func waitForAudio(count: Int = 1) async throws {
        while audio.count < count && !finished { try await Task.sleep(for: .milliseconds(10)) }
        try Task.checkCancellation()
        if audio.isEmpty, let error { throw error }
    }
}

final class PocketSpeech {
    private let resources = PocketResources()
    private var warmup: Task<Void, Never>?
    private var task: Task<Void, Never>?
    private var player: AVAudioPlayer?
    private var session = UUID()
    private var paused = false
    var rate: Float = 1 { didSet { player?.rate = rate } }
    var onStatus: ((String?) -> Void)?
    var onWord: ((NSRange?) -> Void)?
    var onSentence: ((NSRange) -> Void)?
    var onFinish: (() -> Void)?
    var onError: ((String) -> Void)?
    // Used by the real-audio regression test to measure gaps between chunks.
    var onChunkStarted: ((NSRange, TimeInterval) -> Void)?

    func warm(_ voice: PocketVoice) {
        guard warmup == nil, PocketResources.isDownloaded(voice) else { return }
        let resources = resources
        warmup = Task {
            let alignment = AsrModels.modelsExist(at: PocketResources.directory.appendingPathComponent("parakeet-tdt-0.6b-v3"))
            try? await resources.prepare(voice, alignment: alignment) { _ in }
        }
    }

    func start(document: ReadingDocument, offset: Int, voice: PocketVoice, preview: Bool = false) {
        let previous = task
        stop()
        let identity = session
        task = Task { [weak self] in
            await self?.warmup?.value
            await previous?.value
            guard let self, self.session == identity, !Task.isCancelled else { return }
            do {
                try await self.resources.prepare(voice, alignment: !preview) { [weak self] message in
                    Task { @MainActor in
                        guard let self, self.session == identity else { return }
                        self.onStatus?(message)
                    }
                }
                let ranges = Self.chunks(document: document, offset: offset)
                let buffer = SpeechBuffer()
                self.onStatus?("Preparing \(voice.name)…")
                do {
                    // A structured child task is cancelled and joined before a
                    // replacement session can access the same model resources.
                    async let generation: Void = self.fill(buffer, document: document, ranges: ranges, voice: voice, preview: preview)
                    // Start with one passage in reserve, so 2× playback does not
                    // immediately catch the generator at a sentence boundary.
                    try await buffer.waitForAudio(count: min(2, ranges.count))
                    var previousEnd: Date?
                    while true {
                        if buffer.audio.isEmpty && !buffer.finished { self.onStatus?("Preparing \(voice.name)…") }
                        try await buffer.waitForAudio()
                        guard !buffer.audio.isEmpty else { break }
                        let next = buffer.audio.removeFirst()
                        let player = next.player, range = next.range
                        self.player = player
                        while self.paused { try await Task.sleep(for: .milliseconds(30)) }
                        player.rate = self.rate
                        guard player.play() else { throw MacIntegration.CaptureError(message: "The audio output could not start.") }
                        self.onChunkStarted?(range, previousEnd.map { Date().timeIntervalSince($0) } ?? 0)
                        self.onStatus?(nil)
                        var previousWord: NSRange?
                        var previousSentence: NSRange?
                        if !preview {
                            previousSentence = document.sentence(containing: NSRange(location: range.location, length: 1))
                            if let previousSentence { self.onSentence?(previousSentence) }
                        }
                        repeat {
                            try Task.checkCancellation()
                            let time = player.currentTime
                            let current = next.words.first(where: { time >= $0.start && time < $0.end })
                                .map { NSRange(location: range.location + $0.range.location, length: $0.range.length) }
                            if current != previousWord, !preview {
                                if let current, let sentence = document.sentence(containing: current), sentence != previousSentence {
                                    self.onSentence?(sentence); previousSentence = sentence
                                }
                                self.onWord?(current); previousWord = current
                            }
                            try await Task.sleep(for: .milliseconds(10))
                        } while player.isPlaying || self.paused
                        previousEnd = Date()
                        self.player = nil
                        if !preview { self.onWord?(nil) }
                    }
                    await generation
                }
                guard self.session == identity else { return }
                self.onFinish?()
            } catch is CancellationError { }
            catch {
                guard self.session == identity, !Task.isCancelled else { return }
                self.onError?("Pocket TTS: \(error.localizedDescription) Choose an Apple voice to keep listening, or retry.")
            }
        }
    }
    private func fill(_ buffer: SpeechBuffer, document: ReadingDocument, ranges: [NSRange], voice: PocketVoice, preview: Bool) async {
        defer { buffer.finished = true }
        do {
            for range in ranges {
                try await buffer.waitForSpace()
                let text = (document.text as NSString).substring(with: range)
                let (audio, timings) = try await resources.generate(text: text, voice: voice, alignment: !preview)
                try Task.checkCancellation()
                let local = ReadingDocument(attributedText: NSAttributedString(string: text))
                let words = AudioAlignment.match(text: text, words: local.words, timings: timings)
                let player = try AVAudioPlayer(data: audio)
                player.enableRate = true
                guard player.prepareToPlay() else { throw MacIntegration.CaptureError(message: "The audio output could not be prepared.") }
                buffer.audio.append(PreparedSpeech(range: range, player: player, words: words))
            }
        } catch { buffer.error = error }
    }
    func pause() { paused = true; player?.pause() }
    func resume() { paused = false; player?.play() }
    func stop() { session = UUID(); task?.cancel(); player?.stop(); player = nil; paused = false }
    static func chunks(document: ReadingDocument, offset: Int) -> [NSRange] {
        var result: [NSRange] = []
        for sentence in document.sentences where NSMaxRange(sentence) > offset {
            var start = max(offset, sentence.location)
            while start < NSMaxRange(sentence) {
                let limit = min(start + 260, NSMaxRange(sentence))
                let end = limit == NSMaxRange(sentence) ? limit : document.words.last(where: { $0.location > start && $0.location <= limit })?.location ?? NSMaxRange(sentence)
                let range = NSRange(location: start, length: end - start)
                // Tiny sentences otherwise finish before the next inference can
                // complete. Preserve their text and sentence ranges when grouped.
                if let previous = result.last, previous.length < 100,
                   NSMaxRange(previous) == start, previous.length + range.length <= 260 {
                    result[result.count - 1].length += range.length
                } else { result.append(range) }
                start = end
            }
        }
        return result
    }
}
