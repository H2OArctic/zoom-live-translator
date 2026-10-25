import AVFoundation
import LocalRecognition

@MainActor
final class WhisperPipeline {
    private var task: Task<Void, Never>?
    private var ingress: AudioIngress?

    func start(language: String, vocabulary: String,
               onText: @escaping @MainActor (String, Bool) -> Void,
               onLevel: (@MainActor @Sendable (Double) -> Void)?,
               onError: @escaping @MainActor (String) -> Void) async throws -> AudioIngress {
        try await WhisperEngine.shared.prepare()
        let (stream, continuation) = AsyncStream<[Float]>.makeStream(bufferingPolicy: .bufferingOldest(1000))
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
        let levelCallback: (@Sendable (Double) -> Void)?
        if let onLevel {
            levelCallback = { value in Task { @MainActor in onLevel(value) } }
        } else { levelCallback = nil }
        let ingress = AudioIngress(format: format, onSamples: { samples in
            if case .dropped = continuation.yield(samples) {
                continuation.finish()
                Task { @MainActor in onError("Whisper не успевает за звуком. Поток остановлен; выбери Apple или отключи второе направление.") }
            }
        }, onFinish: { continuation.finish() }, onLevel: levelCallback, onError: { message in Task { @MainActor in onError(message) } })
        self.ingress = ingress
        task = Task {
            var audio: [Float] = []
            var preRoll: [Float] = []
            var silence = 0
            var voiced = 0
            do {
                for await samples in stream {
                    try Task.checkCancellation()
                    let energy = samples.reduce(0.0) { $0 + Double($1 * $1) } / Double(max(1, samples.count))
                    let isVoice = energy > 0.000015
                    if audio.isEmpty && !isVoice {
                        preRoll.append(contentsOf: samples)
                        if preRoll.count > 4800 { preRoll.removeFirst(preRoll.count - 4800) }
                        continue
                    }
                    if audio.isEmpty { audio = preRoll; preRoll.removeAll(keepingCapacity: true) }
                    audio.append(contentsOf: samples)
                    if isVoice { silence = 0; voiced += samples.count }
                    else { silence += samples.count }
                    if silence >= 11200 || audio.count >= 160000 {
                        if voiced >= 3200 {
                            let text = try await WhisperEngine.shared.transcribe(audio, language: language, vocabulary: vocabulary)
                            try Task.checkCancellation()
                            if !text.isEmpty { onText(text, true) }
                        }
                        audio.removeAll(keepingCapacity: true)
                        silence = 0; voiced = 0
                    }
                }
            } catch {
                if !Task.isCancelled { onError(error.localizedDescription) }
            }
        }
        return ingress
    }

    func stop() {
        task?.cancel(); task = nil
        ingress?.finish(); ingress = nil
    }
}
