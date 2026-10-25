# Development

## Project layout

| Path | Responsibility |
| --- | --- |
| `Sources/ZoomLiveTranslator/` | SwiftUI interface, capture pipelines, device routing, playback, and application state |
| `Sources/TranslatorCore/` | Translation client, queues, phrase grouping, quality checks, journal/audio recording, and speaker evidence |
| `Sources/LocalRecognition/` | FluidAudio and WhisperKit adapters |
| `Tests/TranslatorCoreTests/` | Swift Testing checks for core behavior |
| `Tools/RecognitionDiagnostics/` | Model preparation and synthetic recognition diagnostics |
| `Tools/OllamaDiagnostics/` | Local translation-client diagnostics |
| `Tools/AudioChecks/` | Audio-conversion probe |
| `Tools/Design/` | App-icon generator |
| `Resources/` | App metadata, entitlements, icons, and bundled licenses |
| `scripts/` | Signed app build and local client-check scripts |
| `postman/` | Existing Ollama contract, mock, and local simulation configuration |

The package pins WhisperKit through `argmax-oss-swift` 1.1.1 and FluidAudio 0.17.7. Keep `Package.resolved` under version control for reproducible dependency resolution. This is a native Swift package; no JavaScript package installation is required.

## Build and core checks

From the project root:

```sh
swift test
swift build -c release
bash scripts/build.sh
```

The first command runs core tests. The second builds package products without constructing a signed app bundle. The final command requires signing credentials, packages resources and licenses, and verifies the signature. See [setup](setup.md) for `SIGNING_IDENTITY`, the optional signing selector; it defaults to the first available Apple Development identity. No new environment variables are required by this documentation.

Core tests cover queues and channel independence, text/Unicode handling, language selection, journaling and audio recording, source selection, number and terminology normalization, phrase commits, and speaker evidence. They do not establish live-call quality.

## Existing local client simulation

The existing simulation exercises the real `OllamaClient` against a local test server. It requires the Postman CLI, `curl`, `rg`, and the release `OllamaDiagnostics` executable. Build the release products first, then run the simulation in one terminal:

```sh
postman simulation run postman/simulations/ollama-local.sim.yaml --port 4917 --output ndjson
```

In another terminal, from the project root:

```sh
bash scripts/check-ollama-client.sh
```

The script tests both language directions plus HTTP/HTML errors, timeout, a missing model, empty or truncated output, and redirect refusal. This configuration uses a local mock; no cloud workspace publication is part of these instructions.

## Recognition diagnostics

After building release products, the following commands explicitly download/prepare models and run synthetic-file checks. They synthesize audio to files rather than playing it through hardware:

```sh
.build/release/RecognitionDiagnostics .build/fluid-models --fluid --synthetic
.build/release/RecognitionDiagnostics .build/fluid-models --fluid --synthetic --realtime --long
.build/release/RecognitionDiagnostics .build/whisper-models --synthetic
```

Use `--no-vocab` on the FluidAudio path to compare without recognition vocabulary. Real-time pacing measures recognition progress, not translation-and-playback latency. See [validation history](validation.md) for historical results and remaining checks.

## App icon and licensing

Regenerate the icon from its Swift source when changing artwork:

```sh
swift Tools/Design/GenerateIcon.swift
iconutil -c icns Resources/AppIcon.iconset -o Resources/AppIcon.icns
```

Rebuild the app afterward. The build includes FluidAudio's SwiftPM resource bundle, the license files in `Resources/Licenses/`, and FluidAudio's third-party notices. Preserve those resources when changing packaging.
