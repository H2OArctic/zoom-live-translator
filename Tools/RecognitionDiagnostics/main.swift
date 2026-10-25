import Foundation
import AVFoundation
import LocalRecognition
import TranslatorCore

private final class RenderSink: @unchecked Sendable {
    private let lock = NSLock()
    private var file: AVAudioFile?
    private var failure: Error?
    private var finished = false
    let url: URL
    let done: @Sendable (Result<Void, Error>) -> Void
    init(url: URL, done: @escaping @Sendable (Result<Void, Error>) -> Void) { self.url = url; self.done = done }
    func receive(_ buffer: AVAudioBuffer) {
        lock.lock()
        defer { lock.unlock() }
        guard !finished, let pcm = buffer as? AVAudioPCMBuffer else { return }
        if pcm.frameLength == 0 {
            finished = true
            file = nil
            done(failure.map { .failure($0) } ?? .success(()))
            return
        }
        do {
            if file == nil { file = try AVAudioFile(forWriting: url, settings: pcm.format.settings) }
            try file?.write(from: pcm)
        } catch { failure = error }
    }
}

@main
struct RecognitionDiagnostics {
    @MainActor static func synthesize(_ text: String, language: String, url: URL) async throws {
        let synth = AVSpeechSynthesizer()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: language)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let sink = RenderSink(url: url) { continuation.resume(with: $0) }
            synth.write(utterance) { sink.receive($0) }
        }
        _ = synth
    }

    static func main() async {
        do {
            let directory = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".build/whisper-models")
            if CommandLine.arguments.contains("--fluid") {
                let engine = FluidEngine(directory: directory)
                let started = Date()
                try await engine.prepare(download: true)
                print("FluidAudio prepared in \(Date().timeIntervalSince(started)) seconds")
                if CommandLine.arguments.contains("--synthetic") {
                    for (language, reference) in [
                        ("en-US", "We don't use Ansible. Bob reviewed three pull requests. Alice will deploy the FIX engine to UAT."),
                        ("ru-RU", "Алиса проверила три запроса на изменение. Боб подготовит новую версию сервиса.")
                    ] {
                        let source = directory.appendingPathComponent("synthetic-\(language).caf")
                        try await synthesize(reference, language: language, url: source)
                        let file: URL
                        if CommandLine.arguments.contains("--long") {
                            let input = try AVAudioFile(forReading: source)
                            guard let buffer = AVAudioPCMBuffer(pcmFormat: input.processingFormat, frameCapacity: AVAudioFrameCount(input.length)) else {
                                throw RecognitionError("Нет памяти для синтетического теста")
                            }
                            try input.read(into: buffer)
                            file = directory.appendingPathComponent("synthetic-repeated-\(language).caf")
                            let output = try AVAudioFile(forWriting: file, settings: input.processingFormat.settings)
                            for _ in 0..<4 { try output.write(from: buffer) }
                        } else { file = source }
                        let result = try await engine.transcribeFile(file.path, language: String(language.prefix(2)),
                            vocabulary: CommandLine.arguments.contains("--no-vocab") ? [] : RecognitionVocabulary.parse(TranslationQuality.recognitionHints),
                            realtime: CommandLine.arguments.contains("--realtime"))
                        let row: [String: String] = ["language": language, "text": result.text,
                            "audioSeconds": String(result.audioSeconds), "processingSeconds": String(result.processingSeconds),
                            "ctcWindows": String(result.ctcWindows), "appliedTerms": result.appliedTerms.joined(separator: ", "),
                            "firstTextSeconds": result.firstTextSeconds.map(String.init(describing:)) ?? "none"]
                        print(String(decoding: try JSONEncoder().encode(row), as: UTF8.self))
                    }
                }
                return
            }
            let engine = WhisperEngine(directory: directory)
            let started = Date()
            try await engine.prepare(download: true)
            print("Whisper prepared in \(Date().timeIntervalSince(started)) seconds")
            if CommandLine.arguments.contains("--synthetic") {
                for (language, text) in [
                    ("en-US", "We don't use Ansible. Bob reviewed three pull requests. Alice will deploy the FIX engine to UAT."),
                    ("ru-RU", "Алиса проверила три запроса на изменение. Боб подготовит новую версию сервиса.")
                ] {
                    let file = directory.appendingPathComponent("synthetic-\(language).caf")
                    try await synthesize(text, language: language, url: file)
                    let start = Date()
                    let result = try await engine.transcribeFile(file.path, language: String(language.prefix(2)), vocabulary: "Ansible, Bob, Alice, FIX engine, UAT, pull requests.")
                    print("\(language) \(Date().timeIntervalSince(start)) seconds: \(result)")
                }
            }
        } catch {
            FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
            exit(1)
        }
    }
}
