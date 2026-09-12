# Local voices

Spokn integrates **Pocket TTS** using [FluidAudio 0.15.7](https://github.com/FluidInference/FluidAudio/releases/tag/v0.15.7), pinned in SwiftPM. Inference uses Core ML inside the native app. There is no Python service, subprocess, cloud synthesis, account, or API key.

The voice menu offers Pocket voices for the detected English, German, French, Spanish, Italian, or Portuguese text. Examples are Alba for English and Jürgen for German. Selecting one on the welcome screen downloads its pack and plays a preview. Selecting one while reading starts that voice at the current word. Apple voices remain available for other languages and as an explicit fallback.

## Installation and storage

The first use fetches the language pack from [FluidInference/pocket-tts-coreml](https://huggingface.co/FluidInference/pocket-tts-coreml). For word highlighting, the app also fetches one shared [Parakeet v3 timing model](https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml). Download progress appears in the panel. Escape cancels playback/preparation; retrying resumes through the upstream downloader. Models are cached under `~/Library/Application Support/Spokn/Models`. Measured English and German packs use about 453 MB each, plus about 470 MB for the shared timing model (about 1.3 GB for both languages); downloaded models work locally afterward.

Spokn uses the small, int8 FlowLM language packs (French requires the larger 24-layer pack). The two most recently used language packs remain loaded; a third evicts the oldest. The last selected, already-downloaded Pocket voice warms in the background when the app launches. Neural Engine use is disabled for Pocket stages to avoid upstream-reported device/OS crashes; Core ML uses the GPU and CPU. Parakeet's encoder also uses CPU/GPU to reduce first-load compilation delays on the tested Mac.

## Playback and highlighting

Text is synthesized in bounded sentence/clause chunks. A local recognition pass finds word timestamps in the generated audio; sequence matching maps those words back onto the immutable original UTF-16 text. Recognition mistakes are possible: unmatched words receive no strong highlight, while the current sentence stays highlighted. Spokn does not invent word timestamps from text length.

Generation runs ahead of playback with up to three prepared chunks. Playback starts with a passage in reserve, and short sentences are grouped to prevent 2× playback from catching the generator at each sentence boundary. Sentence highlights still follow the original sentence ranges. Pausing allows the small buffer to fill; stopping, seeking, or changing voices cancels both generation and playback.

`AVAudioPlayer.currentTime` drives highlights, including at 0.5×–2× speed and after pause/resume. Changing Pocket speed changes audio playback rate without regenerating the text. Changing voice or seeking cancels the previous session. Apple voices continue to use AVFoundation's native word callbacks.

Synthesis, model preparation, and timestamp extraction run outside the main actor. Generated audio is held in memory; a temporary WAV used by the timing engine is removed after processing. No reading history or voice recording is created.

## Validation

`mise run test` covers language-specific voice preferences, Unicode ranges, clipboard restoration, stale clipboard rejection, exact text chunking, timestamp matching, and native UI geometry.

`mise run test-pocket` downloads the real English/German packs and timing model, synthesizes speech, checks duration and recognized words, and writes diagnostic WAVs to `build/native/pocket-{language}-{voice}-check.wav`. It is opt-in so ordinary CI tests do not download large models.

It also checks autoplay, pause/resume, live speed changes, and sustained German playback at 2× with a maximum 150 ms wait between prepared audio chunks. `mise run benchmark-voices` compares the small and 24-layer German packs, including the cost of word alignment.

### Model choice, measured September 12, 2026

On this Apple M4 (24 GB, macOS 26.5.1), three German Jürgen samples took 0.29–0.32 seconds of generation plus alignment per second of audio with the small pack, versus 0.61–0.72 with the 24-layer pack. The larger model cannot sustain 2× playback on this configuration and remains a benchmark option. [Kyutai describes the larger variants as higher quality](https://kyutai-labs.github.io/pocket-tts/); this measurement compares throughput, not subjective voice quality or every available open model. Pocket's smaller model is the current choice for responsive native multilingual reading.

The first sustained German 2× regression measured 11–13 ms between prepared passages. This excludes natural silence inside synthesized audio and is a local measurement, not a guarantee under arbitrary system load. Diagnostic comparison WAVs are written to `build/native/pocket-german-{hq,fast}.wav`; the optional larger benchmark pack uses roughly 1.6 GB of additional cache.

The installed 0.3.0 build 6 was also checked through TextEdit: the exact middle selection was captured with its surrounding lines excluded, Alba started automatically, and the live sentence/word highlights followed playback. The user confirmed the physical ⌘⇧S shortcut opened Spokn and read that selection. The Accessibility entry was refreshed for this ad-hoc signed build, and the scratch documents were discarded afterward.

Build 7 adds formatted Copy before the Accessibility fallback, preserving browser paragraph/list boundaries, emphasis, and safe links. Language/voice routing tests cover all six Pocket languages plus Japanese system voices, including an English passage mentioning Jürgen. The measured initial model preparation decreased from 22.2 seconds to 9.3 seconds after changing the timing encoder placement; a newly loaded German pack took 1.6 seconds. Returning to either resident pack took under 1 ms (model lookup only, excluding synthesis). Real voice, pause/rate, and sustained 2× tests pass with this placement. A generation with no recognized speech is retried once before playback, then reported as an error if it still fails.

Build 7's installed UI was checked with formatted English and German clipboard passages: headings, lists, bold/italic text, links, and paragraphs remained distinct; English selected Alba and German selected Jürgen. The user confirmed the physical shortcut preserved the formatted TextEdit selection. The scratch document was then discarded.

## Attribution

Pocket TTS is by Kyutai; Core ML conversion and inference are by Fluid Inference. Model weights are CC BY 4.0. FluidAudio is Apache 2.0. Parakeet is by NVIDIA; its Core ML conversion is by Fluid Inference. Alba's source recordings are by Alba MacKenna (CC BY 4.0). Other voice provenance is documented by [Kyutai's voice catalog](https://huggingface.co/kyutai/tts-voices). Notices travel inside the application bundle as `ThirdPartyNotices.txt`.
