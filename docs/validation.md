# Validation history

These results were recorded in the previous project README on October 20–21, 2026. They are historical observations, not checks rerun for this documentation update or guarantees for another machine. Local diagnostic reports are excluded from version control and are not required to read these guides.

## October 20, 2026

The previous notes reported a release build with strict code-signature verification and 13 passing Swift Testing tests. Coverage included queues, channel independence under a delayed translation, Unicode, language/engine selection, journal export while writing continued, and synthetic speaker-border/OCR cases.

The real Ollama client was exercised against the local Postman simulation for both language directions, HTTP and HTML errors, timeout, missing model, empty/truncated responses, and redirect refusal. Two short synthetic texts were also translated by local TranslateGemma: the first English → Russian request took 3.46 seconds and the next Russian → English request 0.72 seconds. These are individual requests, not a quality benchmark or live-call latency measurement.

The signed app completed an Ollama warm-up and text-journal export through the interface without starting audio capture. An offline probe converted synthetic 48 kHz stereo audio to 16 kHz mono Int16, producing 15,781 frames and a nonzero signal. A separate speech-synthesis harness produced 82,457 PCM frames without hardware output. A microphone format mismatch prompted the move to device-specific AVCaptureSession input; a non-capture device check identified the selected USB microphone's native 48 kHz stereo format.

## October 21, 2026: Whisper

The notes reported 21 Swift Testing tests, eight local Ollama text probes, model preparation, and recognition of two synthetic files without microphone capture or hardware playback. The English example matched the reference; Russian retained the meaning but rendered the example personal names in Latin characters.

File inference took 2.15 seconds for English and 1.23 seconds for Russian after loading. Initial setup took 142 seconds; a subsequent process launch took 78 seconds. Those numbers exclude live segmentation delay and do not compare engines on a recorded call.

## October 21, 2026: FluidAudio

The notes reported 27 Swift Testing tests. Initial download/preparation took approximately 96 seconds; preparation in a subsequent process took approximately 25 seconds. Model weights used approximately 571 MiB in addition to system compilation caches.

| Synthetic file | Audio duration | Processing with conservative vocabulary | Processing without vocabulary |
| --- | --- | --- | --- |
| English | 6.65 s | 0.69 s | 0.22 s |
| Russian | 5.36 s | 0.12 s | 0.13 s |

These measurements process existing files; they do not measure live-call latency.

A separate check fed each short synthetic recording four times at real-time speed:

| Language | Total audio | Completion time | First committed text |
| --- | --- | --- | --- |
| English | 26.56 s | 26.93 s | 3.96 s |
| Russian | 21.36 s | 21.52 s | 6.78 s |

The English check retained all four instances of negation, names, and the main technical terms, with one `pull requests` → `pool requests` substitution. Russian retained the four semantic repetitions with punctuation artifacts. Translation and speech playback were not included.

## Remaining validation

The historical checks do not establish the complete live Zoom path, long-call stability, recognition quality with accents and interruptions, simultaneous recognition/Ollama load, physical device-disconnect recovery, updated hardware playback, or live native Zoom speaker-name matching. Some interface checks were blocked by unavailable UI automation at the time.

Use a known reference recording when assessing recognition quality. Measure capture, recognition, grouping, translation, queueing, and playback separately before making an end-to-end latency claim. Existing quality warnings are heuristic and cannot certify a correct translation.
