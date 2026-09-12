import Testing
import AppKit
import AVFoundation
import FluidAudio
@testable import Spokn

/// An opt-in diagnostic corpus, not a claim that ASR measures naturalness.
@Suite(.serialized) @MainActor struct VoiceReviewTests {
    private struct Example {
        let category: String
        let raw: String
        var spoken: String? = nil
    }
    private struct Clip: Codable {
        let language: String
        let voice: String
        let category: String
        let variant: String
        let trial: Int
        let chunk: Int
        let text: String
        let detectedLanguage: String
        let transcript: String
        let duration: Double
        let generationSeconds: Double
        let peak: Float
        let rms: Double
        let clippedFraction: Double
        let matchedWords: Int
        let sourceWords: Int
        let file: String
        let error: String?
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["SPOKN_REVIEW_VOICES"] == "1"))
    func generatePronunciationCorpus() async throws {
        let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("build/voice-review")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let english = [
            Example(category: "ordinary", raw: "This is a quiet moment to listen. The words should sound clear and natural, with a short pause between sentences."),
            Example(category: "speed-symbols", raw: "Jürgen now prepares audio ahead; sustained 2× playback passed without generation stalls. Set the speed to 1.75×.", spoken: "Jürgen now prepares audio ahead; sustained two times playback passed without generation stalls. Set the speed to one point seven five times."),
            Example(category: "shortcut", raw: "Select a paragraph and press ⌘⇧S. Press ⌘V to paste it, or Esc to dismiss.", spoken: "Select a paragraph and press Command Shift S. Press Command V to paste it, or Escape to dismiss."),
            Example(category: "technical", raw: "Pocket TTS runs on macOS. The API uses UTF-16. Version 0.3.0 uses 450 MB of storage.", spoken: "Pocket text to speech runs on Mac O S. The A P I uses U T F sixteen. Version zero point three point zero uses four hundred and fifty megabytes of storage."),
            Example(category: "names", raw: "Jürgen and Alba meet Niklas in München. They discuss Spokn, Raycast, and Kyutai over coffee."),
            Example(category: "bullets", raw: "Installed and verified.\n\t•\tThe first paragraph stays separate.\n\t•\tThe next sentence uses a natural pause.\n\nBack to your day.", spoken: "Installed and verified. The first paragraph stays separate. The next sentence uses a natural pause. Back to your day."),
            Example(category: "long-sentence", raw: "When you select a longer passage containing several related ideas, the reader should preserve the flow of the sentence while preparing enough audio to continue smoothly, even when the reading speed increases and the original text includes a subordinate clause that continues beyond the boundary of the first generated chunk, because stopping in the middle of that thought would make the explanation harder to follow.")
        ]
        let german = [
            Example(category: "ordinary", raw: "Nimm dir einen ruhigen Moment zum Zuhören. Die Stimme sollte klar und natürlich klingen, mit einer kurzen Pause zwischen den Sätzen."),
            Example(category: "speed-symbols", raw: "Jürgen bereitet die nächsten Sätze vor. Die Wiedergabe läuft mit 2× Geschwindigkeit. Stelle das Tempo auf 1,75×.", spoken: "Jürgen bereitet die nächsten Sätze vor. Die Wiedergabe läuft mit zweifacher Geschwindigkeit. Stelle das Tempo auf eins Komma sieben fünf mal die normale Geschwindigkeit."),
            Example(category: "shortcut", raw: "Markiere einen Absatz und drücke ⌘⇧S. Mit ⌘V fügst du den Text ein. Drücke Esc zum Schließen.", spoken: "Markiere einen Absatz und drücke Command Umschalt S. Mit Command V fügst du den Text ein. Drücke Escape zum Schließen."),
            Example(category: "technical", raw: "Pocket TTS läuft unter macOS. Die API verwendet UTF-16. Version 0.3.0 benötigt 450 MB Speicherplatz.", spoken: "Pocket Text zu Sprache läuft unter Mac O S. Die A P I verwendet U T F sechzehn. Version null Punkt drei Punkt null benötigt vierhundertfünfzig Megabyte Speicherplatz."),
            Example(category: "names", raw: "Jürgen und Alba treffen Niklas in München. Sie sprechen über Spokn, Raycast und Kyutai und trinken einen Kaffee."),
            Example(category: "bullets", raw: "Installiert und geprüft.\n\t•\tDer erste Absatz bleibt erhalten.\n\t•\tDer nächste Satz bekommt eine natürliche Pause.\n\nZurück an die Arbeit.", spoken: "Installiert und geprüft. Der erste Absatz bleibt erhalten. Der nächste Satz bekommt eine natürliche Pause. Zurück an die Arbeit."),
            Example(category: "long-sentence", raw: "Wenn du einen längeren Abschnitt mit mehreren zusammenhängenden Gedanken auswählst, sollte die Stimme den Zusammenhang des Satzes bewahren und gleichzeitig genügend Audio vorbereiten, damit die Wiedergabe auch bei höherer Geschwindigkeit gleichmäßig weiterläuft, obwohl ein eingeschobener Nebensatz über die Grenze des ersten erzeugten Abschnitts hinausreicht und erst später zum eigentlichen Gedanken zurückführt.")
        ]
        let resources = PocketResources()
        var clips: [Clip] = []
        for (language, examples) in [("en", english), ("de", german)] {
            let voice = try #require(PocketVoice.voices(for: language).first)
            try await resources.prepare(voice, alignment: true) { print($0) }
            for example in examples {
                var variants = [("raw", example.raw)]
                if let spoken = example.spoken { variants.append(("expanded", spoken)) }
                for (variant, fullText) in variants {
                    let document = ReadingDocument(attributedText: NSAttributedString(string: fullText))
                    for trial in 1...2 {
                        for (chunk, range) in PocketSpeech.chunks(document: document, offset: 0).enumerated() {
                            let text = (fullText as NSString).substring(with: range)
                            let file = "\(language)-\(example.category)-\(variant)-\(trial)-\(chunk + 1).wav"
                            let started = Date()
                            do {
                                let (audio, timings) = try await resources.generate(text: text, voice: voice, alignment: true)
                                let elapsed = Date().timeIntervalSince(started)
                                let url = output.appendingPathComponent(file)
                                try audio.write(to: url)
                                let samples = try AudioConverter(sampleRate: 24_000).resampleAudioFile(url)
                                let peak = samples.map { abs($0) }.max() ?? 0
                                let rms = sqrt(samples.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(max(1, samples.count)))
                                let clipped = Double(samples.filter { abs($0) >= 0.999 }.count) / Double(max(1, samples.count))
                                let local = ReadingDocument(attributedText: NSAttributedString(string: text))
                                let matched = AudioAlignment.match(text: text, words: local.words, timings: timings)
                                let transcript = timings.map(\.word).joined(separator: " ")
                                clips.append(Clip(language: language, voice: voice.name, category: example.category, variant: variant, trial: trial, chunk: chunk + 1, text: text, detectedLanguage: document.language, transcript: transcript, duration: Double(samples.count) / 24_000, generationSeconds: elapsed, peak: peak, rms: rms, clippedFraction: clipped, matchedWords: matched.count, sourceWords: local.words.count, file: file, error: nil))
                                #expect(samples.allSatisfy { $0.isFinite })
                                #expect(rms > 0.00001)
                                print("REVIEW \(file): \(transcript)")
                            } catch {
                                clips.append(Clip(language: language, voice: voice.name, category: example.category, variant: variant, trial: trial, chunk: chunk + 1, text: text, detectedLanguage: document.language, transcript: "", duration: 0, generationSeconds: Date().timeIntervalSince(started), peak: 0, rms: 0, clippedFraction: 0, matchedWords: 0, sourceWords: 0, file: file, error: error.localizedDescription))
                                print("REVIEW FAILED \(file): \(error.localizedDescription)")
                            }
                            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                            try encoder.encode(clips).write(to: output.appendingPathComponent("results.json"), options: .atomic)
                        }
                    }
                }
            }
        }
        #expect(!clips.isEmpty)
        print("REVIEW COMPLETE: \(clips.count) clips, \(clips.filter { $0.error != nil }.count) failures")
    }
}
