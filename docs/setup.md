# Setup

## Build prerequisites

Use macOS 26 or later, Xcode with Swift 6.2 or later, and the macOS 26 SDK. The project's recorded development environment is a Mac mini M4. Initial Swift package resolution and model preparation require internet access.

Add your developer account in Xcode and ensure an Apple Development certificate and its private key are available in Keychain. Run from the project root:

```sh
bash scripts/build.sh
open "dist/Zoom Live Translator.app"
```

The build script resolves Swift packages, builds the release executable, copies resources and licenses, signs the bundle with Hardened Runtime, and runs strict signature verification. It produces `dist/Zoom Live Translator.app`. The build is not notarized.

`SIGNING_IDENTITY` is optional. If unset, the script selects the first available Apple Development identity. To select a specific identity, pass its name or hash:

```sh
SIGNING_IDENTITY="Apple Development: Your Name (TEAMID)" bash scripts/build.sh
```

The selected identity must have an available private key. Missing identities and the ad-hoc identity `-` cause the build to fail. Keep private signing material out of the repository.

## Prepare recognition

Open Settings and select an engine:

| Engine | Preparation |
| --- | --- |
| Apple | Use the language preparation action in the More menu to download required recognition assets. |
| FluidAudio | Use Prepare FluidAudio to download and prepare Parakeet, Silero, and vocabulary resources. Successful preparation selects FluidAudio. |
| Whisper | Use Prepare Whisper to download and prepare the configured WhisperKit model. Initial setup can take several minutes. |

The app restores an explicitly saved recognition choice. Without one, it selects FluidAudio when its models are available, otherwise Apple. An incomplete FluidAudio cache requires explicit preparation before capture.

## Prepare translation

Both channels initially use Ollama. The app expects `translategemma:4b` at `http://127.0.0.1:11434`; it does not start the server or download that model for you. Start your installed Ollama service, install the required model, then use Check / Warm Up Ollama in the app. Warm-up does not capture or play audio.

You can instead choose Apple Translation independently for either channel. Use Prepare Languages before starting to obtain the required Apple translation resources. An Ollama-only configuration does not require Apple translation models, but the selected recognition engine still needs its own assets.

## Permissions and audio devices

Allow screen/system-audio recording for application capture. Allow microphone access for the outgoing channel and speech recognition access when requested by macOS.

Use headphones to keep translated speech out of the microphone. A Mac mini needs an external microphone or headset for outgoing speech. Refresh the device list after attaching hardware or installing a virtual device.

Start with incoming translation only. Follow [usage](usage.md) to add translated microphone output through BlackHole.
