import Foundation
@preconcurrency import WhisperKit

public actor WhisperEngine {
    public static let shared = WhisperEngine()
    public static let model = "large-v3-v20240930_626MB"
    private var pipe: WhisperKit?
    private var busy = false
    private let directory: URL?
    public init(directory: URL? = nil) { self.directory = directory }

    private func acquire() async throws {
        while busy { try await Task.sleep(for: .milliseconds(50)) }
        try Task.checkCancellation()
        busy = true
    }

    public func prepare(download: Bool = false) async throws {
        try await acquire()
        defer { busy = false }
        if pipe != nil { return }
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let base = directory ?? support.appendingPathComponent("ZoomLiveTranslator/Whisper", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let marker = base.appendingPathComponent("model-folder.txt")
        let folder: URL
        if let path = try? String(contentsOf: marker, encoding: .utf8), FileManager.default.fileExists(atPath: path) {
            folder = URL(fileURLWithPath: path)
        } else if download {
            folder = try await WhisperKit.download(variant: Self.model, downloadBase: base)
            try folder.path.write(to: marker, atomically: true, encoding: .utf8)
        } else { throw RecognitionError("Сначала нажми «Подготовить Whisper» в настройках распознавания.") }
        try Task.checkCancellation()
        pipe = try await WhisperKit(WhisperKitConfig(modelFolder: folder.path, tokenizerFolder: base,
            verbose: false, prewarm: true, load: true, download: false))
    }

    public func transcribeFile(_ path: String, language: String, vocabulary: String) async throws -> String {
        let buffer = try AudioProcessor.loadAudio(fromPath: path)
        let samples = AudioProcessor.convertBufferToArray(buffer: buffer)
        return try await transcribe(samples, language: language, vocabulary: vocabulary)
    }

    public func transcribe(_ samples: [Float], language: String, vocabulary: String) async throws -> String {
        try await acquire()
        defer { busy = false }
        guard let pipe else { throw RecognitionError("Whisper не подготовлен.") }
        let prompt = pipe.tokenizer.map { Array($0.encode(text: String(vocabulary.prefix(800))).suffix(180)) }
        let options = DecodingOptions(language: language, temperatureFallbackCount: 1, detectLanguage: false,
            skipSpecialTokens: true, withoutTimestamps: false, promptTokens: prompt, concurrentWorkerCount: 1)
        let results = try await pipe.transcribe(audioArray: samples, decodeOptions: options)
        try Task.checkCancellation()
        return results.flatMap(\.segments).filter { $0.noSpeechProb < 0.65 && $0.avgLogprob > -1.1 }
            .map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct RecognitionError: LocalizedError {
    public let message: String
    public var errorDescription: String? { message }
    public init(_ message: String) { self.message = message }
}
