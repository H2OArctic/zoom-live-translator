import AVFoundation
import Observation
import TranslatorCore

private enum SpeechEvent: @unchecked Sendable {
    case buffer(AVAudioPCMBuffer)
    case finished
    case failed
}

private struct SpeechItem {
    let id = UUID()
    let text: String
    let language: String
    let device: AudioDeviceID
    let voiceID: String?
}

@MainActor @Observable
final class SpeechOutput {
    var preferredRate: Float = 0.52
    private(set) var isPaused = false
    private let synthesizer = AVSpeechSynthesizer()
    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var outputDevice: AudioDeviceID?
    private var outputFormat: AVAudioFormat?
    private var pending: [SpeechItem] = []
    private var current: SpeechItem?
    private var renderTask: Task<Void, Never>?
    private var progressWatchdog: Task<Void, Never>?
    private var lastProgressAt = Date()
    private var generation = UUID()
    private var renderingFinished = false
    private var buffersPlaying = 0
    private var queuedSeconds = 0.0
    var onError: ((String) -> Void)?
    var onOverload: (() -> Void)?

    var hasWork: Bool { current != nil || !pending.isEmpty }
    var estimatedSeconds: Double {
        let speed = Double(max(preferredRate, 0.5) / 0.5)
        let waiting = pending.reduce(0) { $0 + Double($1.text.count) / (16 * speed) }
        let active = renderingFinished ? queuedSeconds : max(queuedSeconds, Double(current?.text.count ?? 0) / (16 * speed))
        return waiting + active
    }

    @discardableResult
    func speak(_ text: String, language: String, device: AudioDeviceID, voiceID: String? = nil) -> Bool {
        let totalCharacters = pending.reduce(current?.text.count ?? 0) { $0 + $1.text.count }
        guard totalCharacters + text.count <= 24000 else {
            onError?("Очередь озвучки переполнена. Перевод сохранён в субтитрах; его можно озвучить повторно.")
            onOverload?()
            return false
        }
        pending.append(contentsOf: TextChunks.split(text, limit: 180).map { SpeechItem(text: $0, language: language, device: device, voiceID: voiceID) })
        if estimatedSeconds > 120 { onOverload?() }
        playNext()
        return true
    }

    func resume() { isPaused = false; playNext() }

    func stop() {
        generation = UUID()
        renderTask?.cancel()
        renderTask = nil
        progressWatchdog?.cancel()
        progressWatchdog = nil
        current = nil
        pending.removeAll()
        synthesizer.stopSpeaking(at: .immediate)
        resetEngine()
        isPaused = false
        buffersPlaying = 0
        queuedSeconds = 0
    }

    private func playNext() {
        guard current == nil, !isPaused, !pending.isEmpty else { return }
        let item = pending.removeFirst()
        current = item
        guard let voice = item.voiceID.flatMap({ AVSpeechSynthesisVoice(identifier: $0) }) ?? AVSpeechSynthesisVoice(language: item.language) else {
            failCurrent("Нет локального голоса \(item.language). Добавь его в настройках macOS; очередь сохранена.")
            return
        }
        renderingFinished = false
        buffersPlaying = 0
        queuedSeconds = 0
        let token = generation
        lastProgressAt = Date()
        progressWatchdog = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
                guard let self, self.generation == token, self.current?.id == item.id else { return }
                if Date().timeIntervalSince(self.lastProgressAt) > 15 {
                    self.failCurrent("Озвучка перестала продвигаться. Проверь аудиовыход и нажми «Продолжить озвучку»; очередь сохранена.")
                    return
                }
            }
        }
        let utterance = AVSpeechUtterance(string: item.text)
        utterance.voice = voice
        utterance.rate = estimatedSeconds > 5 ? min(0.65, max(preferredRate, 0.60)) : preferredRate
        let (events, continuation) = AsyncStream<SpeechEvent>.makeStream()
        renderTask = Task { [weak self] in
            for await event in events {
                guard let self, !Task.isCancelled, self.generation == token, self.current?.id == item.id else { return }
                do {
                    switch event {
                    case .buffer(let buffer): try self.receive(buffer, item: item, token: token)
                    case .finished: self.renderingFinished = true; self.finishIfPlayed()
                    case .failed: throw AppError("Не удалось скопировать звук синтеза; очередь сохранена.")
                    }
                } catch { self.failCurrent(error.localizedDescription); return }
            }
        }
        synthesizer.write(utterance) { buffer in
            guard let pcm = buffer as? AVAudioPCMBuffer else {
                continuation.yield(.failed); continuation.finish(); return
            }
            guard pcm.frameLength > 0 else {
                continuation.yield(.finished); continuation.finish(); return
            }
            guard let copy = Self.copyBuffer(pcm) else {
                continuation.yield(.failed); continuation.finish(); return
            }
            continuation.yield(.buffer(copy))
        }
    }

    nonisolated private static func copyBuffer(_ source: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: source.format, frameCapacity: source.frameLength) else { return nil }
        copy.frameLength = source.frameLength
        let sourceBuffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: source.audioBufferList))
        let targetBuffers = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
        guard sourceBuffers.count == targetBuffers.count else { return nil }
        for index in sourceBuffers.indices {
            guard let sourceData = sourceBuffers[index].mData, let targetData = targetBuffers[index].mData,
                  targetBuffers[index].mDataByteSize >= sourceBuffers[index].mDataByteSize else { return nil }
            memcpy(targetData, sourceData, Int(sourceBuffers[index].mDataByteSize))
        }
        return copy
    }

    private func receive(_ buffer: AVAudioPCMBuffer, item: SpeechItem, token: UUID) throws {
        lastProgressAt = Date()
        if engine == nil || outputDevice != item.device || outputFormat != buffer.format {
            resetEngine()
            let engine = AVAudioEngine()
            let player = AVAudioPlayerNode()
            engine.attach(player)
            guard let unit = engine.outputNode.audioUnit else { throw AppError("Аудиовыход недоступен. Очередь сохранена.") }
            var selected = item.device
            guard AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global,
                                       0, &selected, UInt32(MemoryLayout.size(ofValue: selected))) == noErr else {
                throw AppError("Не удалось выбрать аудиовыход. Очередь сохранена.")
            }
            engine.connect(player, to: engine.mainMixerNode, format: buffer.format)
            self.engine = engine
            self.player = player
            outputDevice = item.device
            outputFormat = buffer.format
            try engine.start()
            player.play()
        }
        let seconds = Double(buffer.frameLength) / buffer.format.sampleRate
        queuedSeconds += seconds
        buffersPlaying += 1
        player?.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.generation == token, self.current?.id == item.id else { return }
                self.buffersPlaying -= 1
                self.lastProgressAt = Date()
                self.queuedSeconds = max(0, self.queuedSeconds - seconds)
                self.finishIfPlayed()
            }
        }
    }

    private func finishIfPlayed() {
        guard renderingFinished, buffersPlaying == 0 else { return }
        current = nil
        progressWatchdog?.cancel()
        progressWatchdog = nil
        renderTask = nil
        playNext()
    }

    private func failCurrent(_ message: String) {
        generation = UUID()
        renderTask?.cancel()
        renderTask = nil
        progressWatchdog?.cancel()
        progressWatchdog = nil
        synthesizer.stopSpeaking(at: .immediate)
        if let current { pending.insert(current, at: 0) }
        current = nil
        resetEngine()
        buffersPlaying = 0
        queuedSeconds = 0
        isPaused = true
        onError?(message)
    }

    private func resetEngine() {
        player?.stop()
        engine?.stop()
        engine = nil
        player = nil
        outputDevice = nil
        outputFormat = nil
    }
}
