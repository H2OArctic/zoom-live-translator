# Recognition and translation

Recognition converts audio into source text. Translation then converts that text into the selected target language. Improving the translation model does not reliably repair an incorrect transcript.

## Recognition engines

| Engine | Implementation | Main limitations |
| --- | --- | --- |
| Apple | SpeechAnalyzer with prepared system language resources | Does not use the custom recognition vocabulary. |
| FluidAudio | FluidAudio 0.17.7, Parakeet TDT v3 int8 for English/Russian, Silero VAD, English CTC vocabulary | Windowed recognition adds delay; speaker names are not matched to utterances. |
| Whisper | WhisperKit 1.1.1 with `large-v3-v20240930_626MB` | Experimental segmented recognition; both channels share serialized inference; no speaker-name matching. |

The saved engine choice takes precedence. Without a saved choice, prepared FluidAudio models are preferred; otherwise Apple is selected.

### FluidAudio

Recognition uses overlapping windows with a 3-second center, 2-second left context, and 0.5-second right context. These are window sizes, not a guarantee of total latency. Silero identifies speech activity. The last three words are held while boundaries settle; short sentences and comma-separated fragments can be held for grouping. Long unpunctuated speech can be committed in portions starting at 30 words. The remaining tail is submitted when speech ends.

When recognition revises already committed words, the cursor aligns old and new text and submits only the remaining tail. Existing translations are not replaced or spoken again. `recognition_revision` records both versions. Alignment is limited to 256 changed words; a larger ambiguous region is skipped with a warning. Empty intermediate snapshots do not reset the cursor.

The input queue is limited to 12 seconds of samples at 16 kHz. Overflow or stalled SDK progress produces an explicit error. The adapter also places the tokenizer in FluidAudio's standard cache because this SDK version expects it there. The package disables the optional Rust normalization trait and does not prepare TTS models.

### Whisper

Whisper receives 16 kHz mono Float32 audio. Energy-based segmentation retains 0.3 seconds of preceding audio, waits roughly 0.7 seconds for silence, and limits segments to 10 seconds. Forced boundaries in long speech can introduce errors; segments do not currently overlap or reconcile words across boundaries. Input queues are bounded and overflow stops the stream with an error.

The configured model was previously measured at approximately 606 MiB, excluding tokenizer and compilation caches. Preparation downloads weights from Hugging Face; subsequent recognition runs locally.

## Vocabulary and quality mode

Recognition vocabulary and the translation glossary are separate settings. Recognition vocabulary accepts up to 64 unique terms, each up to 64 characters, within a 3,000-character input. It is used for English FluidAudio CTC and as context for Whisper. Apple recognition does not use it. FluidAudio's Russian CTC path is disabled.

English CTC uses a conservative similarity threshold of 0.85, weight 0.5, and acoustic rescue disabled. More aggressive settings lost negation or inserted English terms into Russian synthetic speech in prior checks. Vocabulary hints do not guarantee recognition of a term.

Accurate translation mode is enabled by default. Completed phrases longer than two words wait 0.85 seconds for grouping; short or incomplete fragments wait 3.2 seconds. Total grouping time is capped at 6 seconds after the first final fragment. A language change, a known speaker change, or a 600-character limit separates groups. Stopping cancels a pending group and records the cancellation.

## Translation engines

Ollama uses `translategemma:4b` on loopback port 11434. Requests specify source and target languages, temperature 0, a 4,096-token context, and a 10-minute model keep-alive. The app warms the model before capture. Long source text is split into chunks of up to 600 characters so translation and speech can begin before the whole passage completes.

Accurate mode supplies the current phrase and a terminology glossary of up to 3,000 characters. Earlier dialogue is not included because it previously caused repetition on short fragments. Apple Translation does not support this additional prompt.

Input normalization handles explicit issue numbers, protocol versions, server identifiers, and selected Russian number constructions. It keeps the original transcript and records transformed inputs in `translation_normalized_input` or `translation_numeric_input`. Ambiguous wording is not automatically expanded into guessed identifiers.

Quality warnings check selected number changes, English negation, and the synthetic example name Alice. These are heuristics rather than semantic verification; they appear in captions and journals without stopping playback. They do not cover every number construction or translation error. Diagnostic examples use fictional names and generic test scenarios.
