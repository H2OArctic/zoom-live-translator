import AVFoundation
import LocalRecognition
import TranslatorCore

private struct FluidTextUpdate: Sendable {
    let text: String
    let final: Bool
}

@MainActor
final class FluidPipeline {
    private var input: BufferedPCM?
    private var ingress: AudioIngress?
    private var session: FluidRecognitionSession?
    private var feedTask: Task<Void, Never>?
    private var resultTask: Task<Void, Never>?

    func start(language: String, vocabulary: String,
               onText: @escaping @MainActor (String, Bool) -> Void,
               onLevel: (@MainActor @Sendable (Double) -> Void)?,
               onRevision: @escaping @MainActor (String, String, Bool) -> Void = { _, _, _ in },
               onError: @escaping @MainActor (String) -> Void) async throws -> AudioIngress {
        try await FluidEngine.shared.prepare()
        let input = BufferedPCM()
        let (results, output) = AsyncStream<FluidTextUpdate>.makeStream(bufferingPolicy: .bufferingOldest(128))
        let terms = RecognitionVocabulary.parse(vocabulary)
        let session = try await FluidEngine.shared.makeSession(language: language, vocabulary: terms,
            onText: { text, final in
                if case .dropped = output.yield(FluidTextUpdate(text: text, final: final)) {
                    output.finish()
                    Task { @MainActor in onError("Переполнена очередь результатов FluidAudio. Перевод остановлен.") }
                }
            }, onRevision: { old, new, uncertain in Task { @MainActor in onRevision(old, new, uncertain) } })
        self.input = input; self.session = session
        resultTask = Task {
            for await result in results {
                guard !Task.isCancelled else { return }
                onText(result.text, result.final)
            }
        }
        feedTask = Task {
            do {
                for await samples in input.stream {
                    input.consumed(samples)
                    try Task.checkCancellation()
                    try await session.feed(samples)
                }
                try Task.checkCancellation()
                try await session.finish()
            } catch { if !Task.isCancelled { onError(error.localizedDescription) } }
            output.finish()
        }
        let levelCallback: (@Sendable (Double) -> Void)?
        if let onLevel { levelCallback = { value in Task { @MainActor in onLevel(value) } } }
        else { levelCallback = nil }
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
        let ingress = AudioIngress(format: format, onSamples: { samples in
            if case .overflow = input.append(samples) {
                Task { @MainActor in onError("FluidAudio не успевает за аудио. Вход остановлен; очередь ограничена 12 секундами.") }
            }
        }, onFinish: { input.finish() }, onLevel: levelCallback,
           onError: { message in Task { @MainActor in onError(message) } })
        self.ingress = ingress
        return ingress
    }

    func stop() async {
        feedTask?.cancel(); feedTask = nil
        resultTask?.cancel(); resultTask = nil
        input?.finish(); input = nil
        ingress?.finish(); ingress = nil
        let previous = session; session = nil
        await previous?.cancel()
    }
}
