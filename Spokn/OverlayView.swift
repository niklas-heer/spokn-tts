import SwiftUI

/// The floating overlay that appears when reading text
struct OverlayView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            // Header with language indicator and close button
            headerBar

            Divider()

            // Main content area
            DimmingContentView(
                content: appState.clipboardContent,
                speechText: appState.speechText,
                currentSentence: appState.currentSentence,
                currentSentenceRange: appState.currentSentenceRange,
                speechProgress: appState.speechProgress
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Karaoke bar showing current sentence with word highlighting
            if !appState.currentSentence.isEmpty {
                Divider()
                KaraokeBarView(
                    sentence: appState.currentSentence,
                    currentWordRange: appState.currentWordInSentenceRange
                )
            }

            Divider()

            // Playback controls
            controlsBar
        }
        .frame(minWidth: 500, minHeight: 350)
        .background(VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            // Language indicator
            languagePicker

            Spacer()

            // Close button
            Button(action: { appState.closeOverlay() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var languagePicker: some View {
        Menu {
            Button(action: { appState.languageOverride = nil }) {
                HStack {
                    Text("Auto-detect")
                    if appState.languageOverride == nil {
                        Image(systemName: "checkmark")
                    }
                }
            }

            Divider()

            ForEach(LanguageDetector.Language.allCases) { language in
                Button(action: { appState.languageOverride = language }) {
                    HStack {
                        Text("\(language.flag) \(language.displayName)")
                        if appState.languageOverride == language {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(appState.effectiveLanguage.flag)
                Text(appState.effectiveLanguage.displayName)
                    .font(.subheadline)
                if appState.languageOverride == nil {
                    Text("(auto)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.down")
                    .font(.caption)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.primary.opacity(0.05))
            .clipShape(Capsule())
        }
        .menuStyle(.borderlessButton)
    }

    // MARK: - Controls

    private var controlsBar: some View {
        HStack(spacing: 20) {
            // Progress bar
            ProgressView(value: appState.speechProgress)
                .frame(maxWidth: .infinity)

            // Speed control
            speedControl

            // Playback buttons
            playbackButtons
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var speedControl: some View {
        HStack(spacing: 8) {
            Image(systemName: "tortoise.fill")
                .font(.caption)
                .foregroundStyle(.secondary)

            Slider(
                value: Binding(
                    get: { appState.speechRate },
                    set: { appState.setSpeechRate($0) }
                ),
                in: 0.5...3.0,
                step: 0.1
            )
            .frame(width: 100)

            Image(systemName: "hare.fill")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(String(format: "%.1fx", appState.speechRate))
                .font(.caption)
                .monospacedDigit()
                .frame(width: 35)
        }
    }

    private var playbackButtons: some View {
        HStack(spacing: 12) {
            // Stop button
            Button(action: { appState.stop() }) {
                Image(systemName: "stop.fill")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(".", modifiers: .command)

            // Play/Pause button
            Button(action: { appState.togglePause() }) {
                Image(systemName: appState.isPaused ? "play.fill" : "pause.fill")
                    .font(.title2)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.space, modifiers: [])

            // Restart button
            Button(action: { appState.restartPlayback() }) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("r", modifiers: .command)
        }
    }
}

// MARK: - Visual Effect Blur

struct VisualEffectBlur: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

#Preview {
    let appState = AppState()
    appState.currentText =
        "This is a sample text that demonstrates the word highlighting feature. The current word should be highlighted as the text is being read aloud."

    return OverlayView(appState: appState)
        .frame(width: 600, height: 300)
}
