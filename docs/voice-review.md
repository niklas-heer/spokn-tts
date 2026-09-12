# Pronunciation review — September 12, 2026

Generated **56 audio chunks (6 minutes 33 seconds)** with the current Pocket TTS pipeline: Alba/English and Jürgen/German, seven categories, two trials per input. Where relevant, raw input was compared with a manually written-out alternative. Both trials use ordinary stochastic generation; this is a diagnostic sample, not a statistical benchmark.

The self-contained [playable comparison](../build/voice-review/index.html) includes every WAV, the exact model input, Parakeet's transcript, and signal measurements. `build/voice-review/results.json` contains the raw results. Reproduce generation with `mise run review-voices`.

## Findings

| Input | Observed result | Interpretation |
|---|---|---|
| English `⌘⇧S`, `⌘V`, `Esc` | Both raw trials dropped the modifiers and mangled the paste instruction. Both written-out trials retained “Command Shift S”, “Command V”, and “Escape”. | Strong evidence for expanding shortcut notation before synthesis. |
| English `2×` and `1.75×` | Both raw transcripts omitted “times”; both written-out trials restored it and the intended decimal reading. | Expand speed notation using the detected language. |
| German `2×` and `1,75×` | Both raw trials corrupted the speed phrase and yielded `1,5`; written-out input recovered the speed values, but the opening name remained inconsistent. | Normalization helps substantially but does not fix every word. |
| Bullet/tab layout | Raw input introduced omissions or repetitions. Removing the layout markers and simplifying whitespace retained the expected words in both trials, in both languages. | Keep visual formatting, but remove layout-only characters from speech input. |
| German versions, acronyms, and storage units | Raw versions/storage amounts were corrupted. Written-out alternatives improved the storage phrase but still lost words or introduced an extra version digit. | The small German model also has reliability limitations beyond formatting. |
| Proper names | Recognizer spellings varied, including `Spokn`/`spoken`, `Kyutai`/`Qtai`, and `Alba`/`Albert`. | Do not infer exact pronunciation from ASR spelling alone or automatically rewrite names from this evidence. |
| Long sentence split across chunks | English retained the words. One German trial added “vorbei” at a chunk boundary; the other did not. | Chunk boundaries warrant listening review; this sample does not isolate them as the cause. |

The English ordinary-prose baseline retained all expected words in both trials. One German baseline trial omitted the opening “Nimm” in recognition; the other retained it.

All 56 chunks produced audio and word timings. Language detection matched the intended language throughout. The largest full-scale sample fraction was approximately **0.0037%**, so these measurements do not point to pervasive clipping as the primary issue. Low clipping does not establish good voice quality.

## Limits and resulting implementation direction

This review used local recognition and signal analysis, **not direct listening**. Recognition can miss words, normalize numbers, or respell a correctly spoken name; timbre, accent quality, and naturalness remain listening judgments. The HTML speed controls use browser playback processing, which can differ from `AVAudioPlayer` in Spokn.

The evidence supports a speech-only normalization layer for list markers, shortcuts, multipliers, and units. It must preserve a mapping to the original UTF-16 text: otherwise expanding `⌘⇧S` into several words would break highlighting. The manually expanded samples are experiments, not an installed normalization implementation. German technical speech also needs model/voice comparisons after normalization; speed alone was insufficient evidence for recommending the current small model as the best fit.
