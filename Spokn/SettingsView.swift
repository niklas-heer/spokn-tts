import SwiftUI

/// Settings view for configuring voices and preferences
struct SettingsView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        TabView {
            VoicesSettingsView(speechService: appState.speechService)
                .tabItem {
                    Label("Voices", systemImage: "waveform")
                }

            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
        }
        .frame(width: 450, height: 350)
    }
}

// MARK: - Voices Settings

struct VoicesSettingsView: View {
    @ObservedObject var speechService: SpeechService
    @State private var previewText = "Hello, this is a preview of the selected voice."
    @State private var previewTextGerman = "Hallo, dies ist eine Vorschau der ausgewählten Stimme."

    var body: some View {
        Form {
            Section {
                Picker("German Voice:", selection: $speechService.selectedGermanVoiceId) {
                    ForEach(speechService.germanVoices) { voice in
                        Text(voice.displayName)
                            .tag(voice.id as String?)
                    }
                }

                HStack {
                    Button("Preview") {
                        previewVoice(language: "de")
                    }
                    .disabled(speechService.isSpeaking)

                    if speechService.isSpeaking {
                        Button("Stop") {
                            speechService.stop()
                        }
                    }
                }
            } header: {
                HStack {
                    Text("🇩🇪")
                    Text("German")
                }
            }

            Section {
                Picker("English Voice:", selection: $speechService.selectedEnglishVoiceId) {
                    ForEach(speechService.englishVoices) { voice in
                        Text(voice.displayName)
                            .tag(voice.id as String?)
                    }
                }

                HStack {
                    Button("Preview") {
                        previewVoice(language: "en")
                    }
                    .disabled(speechService.isSpeaking)

                    if speechService.isSpeaking {
                        Button("Stop") {
                            speechService.stop()
                        }
                    }
                }
            } header: {
                HStack {
                    Text("🇬🇧")
                    Text("English")
                }
            }

            Section {
                HStack {
                    Text("Speech Rate:")
                    Slider(value: $speechService.rate, in: 0.5...3.0, step: 0.1)
                    Text(String(format: "%.1fx", speechService.rate))
                        .monospacedDigit()
                        .frame(width: 40)
                }
            } header: {
                Text("Playback")
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func previewVoice(language: String) {
        let text = language == "de" ? previewTextGerman : previewText
        speechService.speak(text: text, language: language)
    }
}

// MARK: - General Settings

struct GeneralSettingsView: View {
    @AppStorage("launchAtLogin") private var launchAtLogin = false

    var body: some View {
        Form {
            Section {
                Toggle("Launch at Login", isOn: $launchAtLogin)
            } header: {
                Text("Startup")
            }

            Section {
                HStack {
                    Text("Read Selected Text:")
                    Spacer()
                    Text("⌘⇧S")
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            } header: {
                Text("Keyboard Shortcut")
            } footer: {
                Text("Select text in any application, then press the shortcut to read it aloud.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Spokn needs Accessibility permissions to:")
                        .font(.subheadline)

                    VStack(alignment: .leading, spacing: 4) {
                        Label("Register global keyboard shortcuts", systemImage: "keyboard")
                        Label("Copy selected text from other apps", systemImage: "doc.on.clipboard")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Button("Open Accessibility Settings") {
                        openAccessibilitySettings()
                    }
                    .padding(.top, 4)
                }
            } header: {
                Text("Permissions")
            }

            Section {
                HStack {
                    Text("Version")
                    Spacer()
                    Text(appVersion)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Copyright")
                    Spacer()
                    Text("Niklas Heer")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("License")
                    Spacer()
                    Text("MIT")
                        .foregroundStyle(.secondary)
                }
                Link(
                    "View on GitHub",
                    destination: URL(string: "https://github.com/niklas-heer/spokn-tts")!)
            } header: {
                Text("About")
            }

            Section {
                DependencyRow(
                    name: "MarkdownUI", url: "https://github.com/gonzalezreal/swift-markdown-ui",
                    license: "MIT")
            } header: {
                Text("Open Source Libraries")
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var appVersion: String {
        let version =
            Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
        return "\(version) (\(build))"
    }

    private func openAccessibilitySettings() {
        if let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        {
            NSWorkspace.shared.open(url)
        }
    }
}

struct DependencyRow: View {
    let name: String
    let url: String
    let license: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.body)
                Text(license)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Link(destination: URL(string: url)!) {
                Image(systemName: "arrow.up.right.square")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }
}

#Preview("Settings") {
    SettingsView(appState: AppState())
}

#Preview("Voices") {
    VoicesSettingsView(speechService: SpeechService())
        .frame(width: 400, height: 300)
}
