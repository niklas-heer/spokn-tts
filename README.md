# Spokn

A little space to listen. Select text anywhere, press **⌘⇧S**, and a quiet floating panel reads it aloud. The current sentence glows softly; the spoken word has a stronger highlight. Spokn stays visible beside your work until you dismiss it.

Built entirely with **Swift 6.3 and AppKit**: `NSPanel`, TextKit, Natural Language and AVFoundation. No web view, JavaScript runtime, Python service, account, or cloud synthesis. Optional open source Pocket TTS voices run locally through Core ML and FluidAudio.

## Use

- Select text in another app and press **⌘⇧S**. Allow Spokn under **System Settings → Privacy & Security → Accessibility** once. The welcome panel has an **Enable Selection Access…** button. After enabling it, return to the source app and press the shortcut again. Local ad-hoc builds may need their Accessibility entry re-enabled or re-added after an update.
- Spokn sends Copy to the source app to preserve paragraphs, lists, emphasis, and links, then restores the prior clipboard formats. Accessibility selection is the fallback when Copy is unavailable. It never reads an unchanged clipboard as a new selection.
- Or open Spokn from the menu bar and press **⌘V**. Rich clipboard text retains emphasis, headings, paragraphs and lists; RTF and accessibility text can also preserve links. Browser HTML is reduced to structural markup before import, removing scripts, styles, resource tags and attributes. Source selection formatting is preserved when the app exposes attributed accessibility text; otherwise the exact plain text and line breaks are retained. Type size and ink adapt to the panel.
- Move the **0.5×–2× speed slider** to find your pace. Labeled ticks snap in 0.25× steps, with 1× marked as normal. Both highlights follow the speech engine's actual word callbacks, including after a speed change. Scrubbing is coalesced to avoid repeatedly interrupting speech; the current word restarts when the new rate takes effect. Apple speech rate is nonlinear, so the multiplier represents the speech-rate setting, not an exact duration ratio.
- Plain-text Markdown renders headings, emphasis, links, lists, quotes, code, and simple tables through Apple's built-in parser. Pasted HTML and RTF markup also render as text. Existing rich text is preserved. The rendered text is tokenized once so clicking and highlighting remain aligned.
- **Space** pauses/resumes. **← / →** move between sentences. **Click a word** to jump backward or forward; paused playback stays paused. Drag and double-click still select text, and **Read from Here** remains in the context menu.
- Controls fade when you move away from them; the text expands into the footer space. Hover to restore them, or use the keyboard. Keyboard-focused controls and VoiceOver remain visible; Reduce Motion is respected.
- **Escape** stops and dismisses. Clicking another app leaves the floating panel visible. Enable **Hide After Playback** in the Spokn menu if you'd like completed passages to dismiss automatically; it is off by default and remembered.

**Open source voices are implemented:** choose **Alba · Pocket TTS**, **Jürgen · Pocket TTS**, or another matching Pocket voice in the dropdown. First use downloads the language pack and a shared word-timing model; progress appears in the panel. Subsequent playback stays on your Mac. The speaker button previews the selected voice, and changing voices on the welcome screen automatically previews it. See [local voice details](docs/embedded-voices.md) for storage, timing, and attribution.

Spokn detects the passage's dominant language and chooses an available matching system voice, preferring premium or enhanced voices. The labeled Voice dropdown at the top shows the actual active voice and stays available on the welcome screen. It lists Apple and Pocket voices matching the detected language, including regional variants and quality levels. Your choice is remembered per language; choose Automatic to restore the best available Apple voice. Downloaded Apple voices refresh when you open the menu or panel. Changing voices resumes at the current word and preserves a paused state. Use **Download System Voices…** in the menu bar to manage voices. Selections stay in memory; no reading history is stored. Existing libraries from earlier experiments are left untouched.

## Develop with mise

Requires macOS 14 or later and current Xcode or Command Line Tools for the macOS SDK. Install [mise](https://mise.jdx.dev/getting-started.html), then:

```sh
mise trust
mise install
mise run setup
mise run dev
```

`mise.toml` pins **Swift 6.3.3** (latest stable checked September 12, 2026), with toolchain signature verification, and requires **mise 2026.9.5**. Swift 6 language mode and main actor isolation are enabled. The app uses the installed macOS system frameworks and voices; keep macOS updated for their fixes and features.

```sh
mise run test    # Swift Testing: Unicode, callback sessions, language, rich text, native layout
mise run build   # build/native/Spokn.app
mise run dmg     # build/native/Spokn.dmg
mise run install # update /Applications/Spokn.app; quit Spokn first
mise run check  # tests + release build
```

Build scripts create an ad-hoc signed application bundle and an installable DMG. Public distribution still requires your Developer ID signing and Apple notarization. GitHub Actions use the same mise tasks and pin current actions by commit SHA. The repository contains only the native app, tests, resources and build/release tooling.

## Structure

- `native/Sources/Spokn` — floating AppKit panel, rich text, language detection, speech and system integration.
- `native/Tests/SpoknTests` — tests for speech offsets and native behavior.
- `native/Resources` — app icon and its editable SVG source.
- `scripts` — application bundle and DMG packaging.

Pocket voices use timestamps recognized from generated audio and the actual audio playback position. Unmatched words keep sentence highlighting rather than estimated word timing.

The display and speech engine share one immutable UTF-16 text representation. Each utterance has a session identity; stale callbacks from a stopped or replaced utterance cannot move the highlights. Sentence highlighting is derived from the accepted word's sentence, rather than a separate timer. Highlight rectangles use the line baseline and font metrics, excluding line and paragraph spacing; sentence and word fills share the same vertical center.
