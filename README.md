# Zoom Live Translator

A native macOS app for local English ↔ Russian speech translation during Zoom calls and conversations in other apps. It captures audio from a selected application or microphone, displays original and translated captions, and reads translations aloud using macOS voices.

Built with SwiftUI, Apple SpeechAnalyzer, FluidAudio, WhisperKit, Apple Translation, and Ollama. The interface currently uses Russian labels; this documentation is in English.

## Features

- Independent incoming application-audio and outgoing microphone channels, each with its own language direction and translation engine.
- Apple, FluidAudio / Parakeet v3, and experimental Whisper speech recognition.
- Translation through Apple Translation or local Ollama with `translategemma:4b`.
- Headphone playback for incoming translations and virtual audio output for sending your translated speech into Zoom.
- Recognition vocabulary, an Ollama terminology glossary, translation retries, and speech replay.
- Local JSONL session journals and optional source-audio recording.
- Experimental speaker-name detection from a visible native Zoom window.

## Requirements

- macOS 26 or later. Development and recorded checks used a Mac mini M4; other hardware has not been established as supported by those checks.
- Xcode with Swift 6.2 or later and the macOS 26 SDK to build from source.
- An Apple Development signing identity with its private key available in Keychain.
- Headphones; a microphone if you want to translate your own speech.
- Ollama with `translategemma:4b` when using the Ollama translation engine.
- A virtual audio device such as BlackHole 2ch only if you want to send translated speech into a call.

Initial dependency and model downloads require internet access. Prepare the selected recognition engine and, when applicable, Apple translation languages before starting.

## Build and start

Run from the project root:

```sh
bash scripts/build.sh
open "dist/Zoom Live Translator.app"
```

The script creates and verifies a signed app bundle. It requires a signing identity and does not provide an ad-hoc fallback. The app is not notarized. See [setup](docs/setup.md) for signing, model preparation, and permissions.

For a first listening session:

1. Start Zoom or the browser hosting your call.
2. Select that app in the incoming channel and choose English → Russian or Russian → English.
3. Select headphones for translated speech in Settings and prepare your recognition engine.
4. Start Ollama with the required model, or select Apple Translation and prepare its languages.
5. Review the recording settings, leave the microphone channel disabled, and start translation.

**Text journaling and source-audio recording are enabled by default.** Recordings remain on disk until you delete them. See [privacy and recording](docs/privacy-and-recording.md) before using the app for a conversation.

## Documentation

Start with the [documentation index](docs/README.md).

| Guide | Contents |
| --- | --- |
| [Setup](docs/setup.md) | Building, signing, model preparation, and permissions |
| [Usage](docs/usage.md) | Audio routing, Zoom setup, queues, and troubleshooting |
| [Recognition and translation](docs/recognition.md) | Engines, vocabulary, quality mode, and limitations |
| [Privacy and recording](docs/privacy-and-recording.md) | Journals, audio files, exports, and network behavior |
| [Development](docs/development.md) | Project structure, checks, diagnostics, and app resources |
| [Validation history](docs/validation.md) | Previously recorded results and unverified scenarios |

## Current limitations

Translation adds recognition, phrase-grouping, model-processing, and playback delay. Queue estimates are not measurements of total call latency. If processing falls behind enough to pause capture, speech during the pause is not recorded or translated.

Browser capture can include audio from other tabs. Speaker names are approximate visual observations and are not matched to FluidAudio or Whisper utterances. Long calls, accents, interruptions, hardware disconnects, and the complete live Zoom audio path still need validation; synthetic checks do not establish real-call quality.
