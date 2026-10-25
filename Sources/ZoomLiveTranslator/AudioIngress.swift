import AVFoundation
import Speech
import TranslatorCore

final class AudioIngress: @unchecked Sendable {
    private let lock = NSLock()
    private let format: AVAudioFormat
    private let continuation: AsyncStream<AnalyzerInput>.Continuation?
    private let onSamples: (@Sendable ([Float]) -> Void)?
    private let onFinish: (@Sendable () -> Void)?
    private var converter: AVAudioConverter?
    private var stopped = false
    private let onError: @Sendable (String) -> Void
    private let onLevel: (@Sendable (Double) -> Void)?
    private var lastLevelAt = Date.distantPast
    private var recorder: SessionAudioRecorder?

    func record(to recorder: SessionAudioRecorder) {
        lock.withLock { self.recorder = recorder }
    }

    init(format: AVAudioFormat, continuation: AsyncStream<AnalyzerInput>.Continuation,
         onLevel: (@Sendable (Double) -> Void)? = nil,
         onError: @escaping @Sendable (String) -> Void) {
        self.onSamples = nil
        self.onFinish = nil
        self.format = format
        self.continuation = continuation
        self.onError = onError
        self.onLevel = onLevel
    }

    init(format: AVAudioFormat, onSamples: @escaping @Sendable ([Float]) -> Void,
         onFinish: @escaping @Sendable () -> Void, onLevel: (@Sendable (Double) -> Void)? = nil,
         onError: @escaping @Sendable (String) -> Void) {
        self.format = format; self.continuation = nil; self.onSamples = onSamples
        self.onFinish = onFinish; self.onLevel = onLevel; self.onError = onError
    }

    func append(_ input: AVAudioPCMBuffer, presentationSeconds: Double? = nil) {
        lock.lock()
        defer { lock.unlock() }
        guard !stopped, input.frameLength > 0, input.format.sampleRate > 0 else { return }
        recorder?.append(input, presentationSeconds: presentationSeconds)
        if converter?.inputFormat != input.format {
            converter = AVAudioConverter(from: input.format, to: format)
        }
        guard let converter else { fail("Невозможно преобразовать формат аудио."); return }
        let capacity = AVAudioFrameCount(ceil(Double(input.frameLength) * format.sampleRate / input.format.sampleRate)) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
            fail("Не удалось выделить аудиобуфер."); return
        }
        var supplied = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, state in
            guard !supplied else { state.pointee = .noDataNow; return nil }
            supplied = true
            state.pointee = .haveData
            return input
        }
        guard status != .error else { fail(error?.localizedDescription ?? "Ошибка преобразования аудио."); return }
        guard output.frameLength > 0 else { return }
        reportLevel(output)
        if let onSamples, let samples = output.floatChannelData?[0] {
            onSamples(Array(UnsafeBufferPointer(start: samples, count: Int(output.frameLength))))
        }
        if let continuation, case .dropped = continuation.yield(AnalyzerInput(buffer: output)) {
            fail("Распознавание не успевает за звуком. Поток остановлен; отключи одно направление и повтори.")
        }
    }

    func finish() {
        lock.lock()
        stopped = true
        continuation?.finish()
        onFinish?()
        lock.unlock()
    }

    private func fail(_ message: String) {
        stopped = true
        continuation?.finish()
        onFinish?()
        onError(message)
    }

    private func reportLevel(_ buffer: AVAudioPCMBuffer) {
        guard let onLevel, Date().timeIntervalSince(lastLevelAt) >= 0.1 else { return }
        lastLevelAt = Date()
        var sum = 0.0
        var count = 0
        for audio in UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: buffer.audioBufferList)) {
            guard let data = audio.mData else { continue }
            let samples = Int(buffer.frameLength) * Int(audio.mNumberChannels)
            if buffer.format.commonFormat == .pcmFormatFloat32 {
                let values = data.assumingMemoryBound(to: Float.self)
                for index in 0..<samples { let value = Double(values[index]); sum += value * value }
                count += samples
            } else if buffer.format.commonFormat == .pcmFormatInt16 {
                let values = data.assumingMemoryBound(to: Int16.self)
                for index in 0..<samples { let value = Double(values[index]) / 32768; sum += value * value }
                count += samples
            }
        }
        let rms = count > 0 ? sqrt(sum / Double(count)) : 0
        let decibels = 20 * log10(max(rms, 0.000001))
        onLevel(min(1, max(0, (decibels + 60) / 60)))
    }
}
