# Privacy and recording

## Defaults and retention

Text journaling and source-audio recording are enabled by default. Audio recording starts only when translation capture starts. The audio-recording preference is saved locally; text journaling starts enabled for each app session.

Both features store conversation content. Review them in Settings before starting a call. Clearing visible captions does not delete session files. Files are not automatically rotated or deleted.

Use Show Journals and Audio to open `Application Support/ZoomLiveTranslator/Sessions` inside the app's sandbox container. This location remains accessible through the app after a restart. Directories are created with mode `0700` and session files with mode `0600`.

## Text journals

The first translation or manual text check creates a `session-<UTC-time>-<ID>.jsonl` file. Later capture starts and stops in the same app session append to that journal. Background serial writes keep file operations off the audio callback.

Each UTF-8 line is one event with `schemaVersion: 1`, `sessionID`, `sequence`, `timestamp`, `event`, optional `channel` and `jobID`, and a `data` object. Timestamps use UTC with milliseconds. Channels are `incoming` for application audio and `outgoing` for the microphone; `jobID` links events for one phrase.

Journals include partial recognition at up to two entries per second per source, final originals, translations and chunks, language pairs, engine/model information, device and application names, queue and processing times, retries, cancellations, and errors. API keys, tokens, and raw audio-buffer contents are not deliberately recorded by the journal; recognized conversation text is sensitive regardless.

Useful events include `session_started`, `capture_starting`, `recognizer_started`, `capture_started`, `recognition_partial`, `utterance`, `translation_started`, `translation_chunk_completed`, `translation_completed`, `translation_failed`, `speech_queued`, `speech_error`, `capture_paused`, `capture_stopped`, and `session_closed`. Speaker observations use `speaker_observed`; assigned names appear in `utterance` data as `speaker` and `speakerSource`.

Save Journal exports a snapshot. Capture can continue appending to the working file, so export again for a newer snapshot. A manual text check can legitimately have no recognizer value. If a disk error disables journaling, fix the cause and enable it again to start a new file.

## Source audio

Each capture run creates separate `*-incoming.caf` and, when enabled, `*-outgoing.caf` files. They store PCM before recognition conversion at the source sample rate and channel count. The app does not mix its synthesized translations into these files, but browser tabs or sound picked up by the microphone may still be present.

Each CAF has a `*.timing.jsonl` index containing buffer arrival time, capture timestamp, starting sample, and frame count. Gaps in capture are not filled with continuous audio; use the index to align recordings with journal events. Timing indexes are written even when text journaling is off.

Recording ends on stop, a queue-induced capture pause, or app shutdown. A later capture start creates new files. At 48 kHz stereo Float32, one source needs approximately 1.4 GB per hour. Pending recording buffers are limited to 8 MiB per source. Disk errors, overflow, or format changes stop recording with a visible message and mark the timing index incomplete; translation continues.

Journal export includes text only. For quality analysis, provide the relevant CAF, matching timing index, and session journal after reviewing their contents.

## Network behavior and Git exclusions

The app's Ollama client uses loopback, bypasses system proxies, and refuses redirects. It does not implement a cloud translation fallback. The sandbox grants outbound network access; loopback restrictions are enforced by the client rather than by that entitlement. Initial model downloads and Apple's model preparation or maintenance can use network services.

Speaker-window frames are processed locally and are not saved or uploaded. Local storage and local inference do not remove the sensitivity of conversation data.

The repository's `.gitignore` excludes local agent reports, environment files, common credentials and private keys, build output, JSONL/NDJSON exports, recording/transcript folders, common audio/video and subtitle formats, archives, local databases, backups, and logs. Example environment templates remain eligible for version control. Ignore rules do not remove already tracked files or detect every possible secret; review files before publishing.
