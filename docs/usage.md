# Usage

## Listen to a conversation

Select Zoom or the browser hosting your call in the incoming channel. Choose the language direction, then select a translation engine and headphone output in Settings. Prepare the required models as described in [setup](setup.md), review [recording settings](privacy-and-recording.md), and start translation.

The incoming channel is enabled by default; the microphone channel is disabled. Each channel supports English → Russian and Russian → English independently. Captions retain the language pair and engine used for the translation, along with text-processing time. The window retains up to 100 phrases; the separate journal is not subject to that limit.

A failed translation keeps the original text and offers a retry. Retrying after changing the engine translates the original with the newly selected engine. Completed translations can be spoken again. The manual text check lets you test translation without capturing a call.

Settings also provide speech speed and system, light, or dark appearance. Appearance is saved locally. Source and model configuration should be changed while capture is stopped; some controls also remain disabled until pending work finishes. Closing the last window exits the app.

## Choose an application

Automatic selection prefers native Zoom, then the first available browser in this order: Chrome, Safari, Edge, Brave, Arc, Firefox, Opera. It selects an application process; it does not detect a meeting or browser tab. Use a dedicated browser for a call if other tabs may produce audio.

Manual selection is saved by application identity. If the selected app closes, another source is not substituted automatically. The source list refreshes at startup, every three seconds while idle, and before capture. Sources do not switch automatically during capture or queue processing.

## Send translated microphone speech into Zoom

Install a virtual audio device such as BlackHole 2ch, restart the Mac if needed, and refresh devices in the translator. Configure the route as follows:

| Setting | Device |
| --- | --- |
| Translator microphone source | Your physical microphone |
| Translator outgoing speech output | BlackHole 2ch |
| Zoom microphone | BlackHole 2ch |
| Zoom speaker | Your headphones |
| Translator incoming speech output | Your headphones |

Enable the outgoing channel and choose its language direction. Keep Zoom's speaker on headphones: selecting BlackHole as its speaker can feed the other participant's audio back into the call.

The app does not change system audio defaults, Zoom settings, or the original call volume. If you only need incoming translation, leave the outgoing channel off. If a virtual output is unavailable, disable outgoing speech playback and use microphone captions.

## Queues and recovery

The two channels have independent translation queues, although the local model server may serialize computation. Long text is translated in chunks of up to 600 characters; speech playback uses chunks of up to 180 characters. Playback speed increases moderately when speech accumulates.

The UI shows phrase counts, translation waiting time, and an approximate speech backlog. These values do not measure complete speech-to-translation latency.

Each source allows 32 pending translations; queued speech is limited to 24,000 characters. At 24 queued phrases in one channel or an estimated speech backlog above 120 seconds, capture pauses while accepted work continues. **New speech during this pause is not captured.** Overflow is shown in captions and affected phrases can be retried.

If an audio device or speech synthesis stops responding, playback pauses and preserves its queue. After fixing the device, resume speech; the current chunk may repeat. A lack of progress for 15 seconds produces a message. Stop and Reset Queue explicitly cancel capture and accumulated work; unfinished translations remain available for retry.

## Experimental speaker names

In Settings, enable speaker-name detection, refresh Zoom windows, and select a native Zoom meeting window. The incoming audio source must also be native Zoom. Inspect Window Without Audio takes one frame for local OCR without microphone capture or playback.

The detector needs one visible, closed green speaker border with a readable name near its bottom. Keep the window visible and unminimized. It uses Apple Vision rather than Accessibility inspection; frames are not saved or uploaded.

Names marked with `≈` are approximate. Layout changes, overlapping speakers, delayed borders, duplicate names, and OCR errors can cause mistakes. Ambiguous or changing observations leave the phrase unnamed. Names are not currently matched to FluidAudio or Whisper utterances.

Optional name announcements and different installed system voices help distinguish observed speakers. Voices may repeat when too few are available; this is not voice cloning. Live native Zoom speaker matching has not yet been validated.

## Troubleshooting

| Symptom | Check |
| --- | --- |
| No incoming audio | Confirm the selected app is running and screen/system-audio permission is granted. |
| Microphone meter stays flat | Confirm microphone permission and the physical input selection. The problem is before translation or virtual output routing. |
| Ollama unavailable or model missing | Start the local service, install `translategemma:4b`, and run the app's warm-up action. |
| Other browser tabs appear in captions | Use a dedicated browser or switch to native Zoom. |
| Echo or translated speech returns to the call | Use headphones and recheck the routing table above. |
| Recognition cache is incomplete | Stop capture and explicitly prepare the selected engine. |
| Playback stops advancing | Restore the output device and resume speech, or stop and clear pending work. |
