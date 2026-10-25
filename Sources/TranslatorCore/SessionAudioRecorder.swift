import Foundation
import AVFoundation

public final class SessionAudioRecorder: @unchecked Sendable {
    public let fileURL: URL
    public let indexURL: URL
    private let queue = DispatchQueue(label: "translator.audio-recording", qos: .utility)
    private let lock = NSLock()
    private let capacity: Int
    private let onEvent: @Sendable (String, [String: String]) -> Void
    private var accepting = true
    private var failed = false
    private var pendingBytes = 0
    private var file: AVAudioFile?
    private var index: FileHandle?
    private var format: AVAudioFormat?
    private var frames: AVAudioFramePosition = 0
    private var finished = false

    public init(fileURL: URL, capacity: Int = 8 * 1024 * 1024,
                onEvent: @escaping @Sendable (String, [String: String]) -> Void = { _, _ in }) throws {
        self.fileURL = fileURL
        self.indexURL = fileURL.deletingPathExtension().appendingPathExtension("timing.jsonl")
        self.capacity = capacity
        self.onEvent = onEvent
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        guard FileManager.default.createFile(atPath: indexURL.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        index = try FileHandle(forWritingTo: indexURL)
    }

    public func append(_ input: AVAudioPCMBuffer, receivedAt: Date = Date(), presentationSeconds: Double? = nil) {
        guard input.frameLength > 0 else { return }
        lock.lock()
        defer { lock.unlock() }
        guard accepting else { return }
        let source = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input.audioBufferList))
        let bytes = source.reduce(0) { $0 + Int($1.mDataByteSize) }
        guard bytes <= capacity - pendingBytes else {
            accepting = false
            queue.async { self.fail("Переполнена очередь записи аудио. Запись остановлена; перевод продолжается.") }
            return
        }
        guard let copy = AVAudioPCMBuffer(pcmFormat: input.format, frameCapacity: input.frameLength) else {
            accepting = false
            queue.async { self.fail("Не удалось скопировать аудио для записи.") }
            return
        }
        copy.frameLength = input.frameLength
        let destination = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
        guard source.count == destination.count,
              zip(source, destination).allSatisfy({ $0.mDataByteSize <= $1.mDataByteSize && $0.mData != nil && $1.mData != nil }) else {
            accepting = false
            queue.async { self.fail("Некорректный аудиобуфер для записи.") }
            return
        }
        for (from, to) in zip(source, destination) {
            if let fromData = from.mData, let toData = to.mData { memcpy(toData, fromData, Int(from.mDataByteSize)) }
        }
        let packet = Packet(buffer: copy, receivedAt: receivedAt, presentationSeconds: presentationSeconds)
        pendingBytes += bytes
        queue.async {
            defer { self.lock.withLock { self.pendingBytes -= bytes } }
            guard !self.failed else { return }
            do { try self.write(packet) }
            catch { self.fail("Ошибка записи аудио: \(error.localizedDescription). Перевод продолжается.") }
        }
    }

    public func finish() async {
        await withCheckedContinuation { continuation in
            lock.withLock {
                accepting = false
                queue.async {
                    if !self.finished {
                        self.file = nil
                        var data = ["file": self.fileURL.lastPathComponent, "frames": String(self.frames),
                                    "sampleRate": String(self.format?.sampleRate ?? 0),
                                    "status": self.failed ? "incomplete" : "complete"]
                        do {
                            try self.writeIndex(data.merging(["event": "finished"]) { _, new in new })
                            try self.index?.synchronize()
                            try self.index?.close()
                        } catch {
                            self.fail("Не удалось завершить индекс аудио: \(error.localizedDescription)")
                            data["status"] = "incomplete"
                        }
                        self.index = nil
                        self.finished = true
                        self.onEvent("audio_recording_finished", data)
                    }
                    continuation.resume()
                }
            }
        }
    }

    private func write(_ packet: Packet) throws {
        if file == nil {
            let format = packet.buffer.format
            var settings = format.settings
            settings[AVLinearPCMIsNonInterleaved] = false
            file = try AVAudioFile(forWriting: fileURL, settings: settings,
                                   commonFormat: format.commonFormat, interleaved: format.isInterleaved)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
            self.format = format
            let data = ["file": fileURL.lastPathComponent, "index": indexURL.lastPathComponent,
                        "sampleRate": String(format.sampleRate), "channels": String(format.channelCount),
                        "receivedAt": packet.receivedAt.ISO8601Format(.init(includingFractionalSeconds: true))]
            try writeIndex(data.merging(["event": "started"]) { _, new in new })
            onEvent("audio_recording_started", data)
        }
        guard packet.buffer.format == format else {
            throw NSError(domain: "SessionAudioRecorder", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Входной формат аудио изменился во время записи"])
        }
        try file?.write(from: packet.buffer)
        let start = frames
        frames += AVAudioFramePosition(packet.buffer.frameLength)
        var data = ["event": "packet", "startFrame": String(start), "frames": String(packet.buffer.frameLength),
                    "receivedAt": packet.receivedAt.ISO8601Format(.init(includingFractionalSeconds: true))]
        if let seconds = packet.presentationSeconds, seconds.isFinite { data["presentationSeconds"] = String(seconds) }
        try writeIndex(data)
    }

    private func writeIndex(_ value: [String: String]) throws {
        var data = try JSONEncoder().encode(value)
        data.append(0x0a)
        try index?.write(contentsOf: data)
    }

    private func fail(_ message: String) {
        guard !failed else { return }
        failed = true
        lock.withLock { accepting = false }
        try? writeIndex(["event": "failed", "message": message, "frames": String(frames)])
        onEvent("audio_recording_failed", ["file": fileURL.lastPathComponent, "message": message])
    }

    private struct Packet: @unchecked Sendable {
        let buffer: AVAudioPCMBuffer
        let receivedAt: Date
        let presentationSeconds: Double?
    }
}
