import Foundation
@preconcurrency import AVFoundation
@preconcurrency import FluidAudio
import TranslatorCore

public actor FluidEngine {
    public static let shared = FluidEngine()
    public static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ZoomLiveTranslator/FluidAudio", isDirectory: true)
    }
    public static var modelsAvailable: Bool {
        FileManager.default.fileExists(atPath: defaultDirectory.appendingPathComponent("prepared.txt").path)
    }
    private let directory: URL
    private var models: AsrModels?
    private var ctc: CtcModels?
    private var vad: VadManager?
    private var preparing = false

    public init(directory: URL? = nil) { self.directory = directory ?? Self.defaultDirectory }

    public func prepare(download: Bool = false) async throws {
        while preparing { try await Task.sleep(for: .milliseconds(100)) }
        if models != nil && ctc != nil && vad != nil { return }
        preparing = true
        defer { preparing = false }
        let root = directory.appendingPathComponent("Models", isDirectory: true)
        let asrPath = root.appendingPathComponent(AsrModels.defaultCacheDirectory(for: .v3).lastPathComponent)
        let ctcPath = root.appendingPathComponent(CtcModels.defaultCacheDirectory().lastPathComponent)
        let vadPath = root.appendingPathComponent(Repo.vad.folderName).appendingPathComponent(ModelNames.VAD.sileroVadFile)
        if !download {
            guard FileManager.default.fileExists(atPath: directory.appendingPathComponent("prepared.txt").path),
                  AsrModels.modelsExist(at: asrPath, version: .v3), CtcModels.modelsExist(at: ctcPath),
                  FileManager.default.fileExists(atPath: ctcPath.appendingPathComponent("tokenizer.json").path),
                  FileManager.default.fileExists(atPath: vadPath.path) else {
                throw RecognitionError("Сначала нажми «Подготовить FluidAudio» в настройках распознавания.")
            }
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let loaded: AsrModels
        let loadedCTC: CtcModels
        if download {
            loaded = try await AsrModels.downloadAndLoad(to: asrPath, version: .v3)
            loadedCTC = try await CtcModels.downloadAndLoad(to: ctcPath)
        } else {
            loaded = try await AsrModels.load(from: asrPath, version: .v3)
            loadedCTC = try await CtcModels.load(from: ctcPath)
        }
        let loadedVAD = try await VadManager(modelDirectory: directory)
        // FluidAudio 0.17.7 resolves the CTC tokenizer from its default cache even with custom model paths.
        let tokenizerDirectory = CtcModels.defaultCacheDirectory()
        try FileManager.default.createDirectory(at: tokenizerDirectory, withIntermediateDirectories: true)
        let tokenizer = try Data(contentsOf: ctcPath.appendingPathComponent("tokenizer.json"))
        let cachedTokenizer = tokenizerDirectory.appendingPathComponent("tokenizer.json")
        if (try? Data(contentsOf: cachedTokenizer)) != tokenizer { try tokenizer.write(to: cachedTokenizer, options: .atomic) }
        try Task.checkCancellation()
        models = loaded; ctc = loadedCTC; vad = loadedVAD
        try "Parakeet v3 + CTC + Silero VAD".write(to: directory.appendingPathComponent("prepared.txt"), atomically: true, encoding: .utf8)
    }

    public func transcribeFile(_ path: String, language: String, vocabulary: [String], realtime: Bool = false) async throws -> FluidProbeResult {
        let samples = try AudioConverter().resampleAudioFile(URL(fileURLWithPath: path))
        let probe = FluidProbe()
        let session = try makeSession(language: language, vocabulary: vocabulary,
            onText: { text, final in probe.receive(text, final: final) })
        do {
            let playbackStarted = Date()
            for offset in stride(from: 0, to: samples.count, by: 4096) {
                let end = min(samples.count, offset + 4096)
                if realtime {
                    let wait = Double(end) / 16000 - Date().timeIntervalSince(playbackStarted)
                    if wait > 0 { try await Task.sleep(for: .seconds(wait)) }
                }
                try await session.feed(Array(samples[offset..<end]))
            }
            try await session.finish()
            await session.cancel()
        } catch { await session.cancel(); throw error }
        return probe.result(audioSeconds: Double(samples.count) / 16000,
            ctcWindows: await session.ctcWindows, appliedTerms: await session.appliedTerms.sorted())
    }

    public func makeSession(language: String, vocabulary: [String],
                            onText: @escaping @Sendable (String, Bool) -> Void,
                            onRevision: @escaping @Sendable (String, String, Bool) -> Void = { _, _, _ in }) throws -> FluidRecognitionSession {
        guard let models, let ctc, let vad else { throw RecognitionError("FluidAudio не подготовлен.") }
        return FluidRecognitionSession(models: models, ctc: ctc, vad: vad, language: language,
            vocabulary: vocabulary, onText: onText, onRevision: onRevision)
    }
}

public actor FluidRecognitionSession {
    private let models: AsrModels
    private let ctc: CtcModels
    private let vad: VadManager
    private let language: String
    private let vocabulary: [String]
    private let onText: @Sendable (String, Bool) -> Void
    private let onRevision: @Sendable (String, String, Bool) -> Void
    private var previousSnapshot = ""
    private var vadState = VadStreamState.initial()
    private var pending: [Float] = []
    private var preRoll: [Float] = []
    private var manager: SlidingWindowAsrManager?
    private var updates: Task<Void, Never>?
    private var cursor = TranscriptCommitter()
    private var token = UUID()
    private var cancelled = false
    private var sentSamples = 0
    private var receivedWindows = 0
    private static let chunkSeconds: Double = 3
    public private(set) var ctcWindows = 0
    public private(set) var appliedTerms = Set<String>()

    init(models: AsrModels, ctc: CtcModels, vad: VadManager, language: String, vocabulary: [String],
         onText: @escaping @Sendable (String, Bool) -> Void,
         onRevision: @escaping @Sendable (String, String, Bool) -> Void) {
        self.models = models; self.ctc = ctc; self.vad = vad; self.language = language
        self.vocabulary = Array(vocabulary.prefix(64)); self.onText = onText; self.onRevision = onRevision
    }

    public func feed(_ samples: [Float]) async throws {
        guard !cancelled else { throw CancellationError() }
        pending.append(contentsOf: samples)
        while pending.count >= VadManager.chunkSize {
            let block = Array(pending.prefix(VadManager.chunkSize))
            pending.removeFirst(VadManager.chunkSize)
            let result = try await vad.processStreamingChunk(block, state: vadState)
            try Task.checkCancellation()
            guard !cancelled else { throw CancellationError() }
            vadState = result.state
            if manager == nil && result.state.triggered { try await startUtterance() }
            if let manager {
                if sentSamples - receivedWindows * Int(Self.chunkSeconds * 16000) > 16000 * 12 {
                    throw RecognitionError("FluidAudio накопил слишком большую очередь распознавания. Поток остановлен; выбери Apple или отключи второе направление.")
                }
                let buffer = Self.buffer(block)
                await manager.streamAudio(buffer)
                sentSamples += block.count
                if result.event?.isEnd == true { try await finishUtterance() }
            } else {
                preRoll.append(contentsOf: block)
                if preRoll.count > 8192 { preRoll.removeFirst(preRoll.count - 8192) }
            }
        }
    }

    private func startUtterance() async throws {
        token = UUID()
        cursor = TranscriptCommitter(); sentSamples = 0; receivedWindows = 0
        let current = token
        let config = SlidingWindowAsrConfig(chunkSeconds: Self.chunkSeconds, hypothesisChunkSeconds: 1,
            leftContextSeconds: 2, rightContextSeconds: 0.5, minContextForConfirmation: 3,
            confirmationThreshold: 0.7, language: Language(rawValue: language))
        let manager = SlidingWindowAsrManager(config: config)
        try await manager.loadModels(models)
        if language == "en" && !vocabulary.isEmpty {
            let terms = vocabulary.map { CustomVocabularyTerm(text: String($0.prefix(64)), minSimilarity: 0.85) }
            let context = CustomVocabularyContext(terms: terms, alpha: 0.5, minSimilarity: 0.85)
            let config = VocabularyRescorer.Config(useAdaptiveThresholds: false, shortTermCbwTaperPivot: 5,
                spotterRescueMinSimilarity: 0.85, spotterRescueMultiWordMinSimilarity: 0.85, spotterRescueEnabled: false)
            try await manager.configureVocabularyBoosting(vocabulary: context, ctcModels: ctc, config: config)
        }
        try Task.checkCancellation()
        guard !cancelled else { throw CancellationError() }
        let stream = await manager.transcriptionUpdates
        self.manager = manager
        updates = Task { [weak self] in
            for await update in stream {
                guard !Task.isCancelled else { return }
                await self?.receive(update, manager: manager, token: current)
            }
        }
        try await manager.startStreaming(source: .system)
        if Task.isCancelled || cancelled { await manager.cancel(); throw CancellationError() }
        if !preRoll.isEmpty {
            await manager.streamAudio(Self.buffer(preRoll))
            sentSamples += preRoll.count
            preRoll.removeAll(keepingCapacity: true)
        }
    }

    private func receive(_ update: SlidingWindowTranscriptionUpdate, manager: SlidingWindowAsrManager, token: UUID) async {
        guard token == self.token, !cancelled else { return }
        receivedWindows += 1
        if update.ctcDetectedTerms != nil { ctcWindows += 1 }
        appliedTerms.formUnion(update.ctcAppliedTerms ?? [])
        let snapshot = await manager.translatorSnapshot()
        guard token == self.token, !cancelled else { return }
        emit(snapshot)
    }

    private func finishUtterance() async throws {
        guard let manager else { return }
        let current = token
        let text = try await manager.finish()
        guard current == token, !cancelled else { throw CancellationError() }
        token = UUID()
        updates?.cancel(); updates = nil
        await manager.cancel()
        self.manager = nil
        emit(text, final: true)
        cursor = TranscriptCommitter()
        previousSnapshot = ""
    }

    private func emit(_ snapshot: String, final: Bool = false) {
        let delta = cursor.advance(snapshot, final: final, preferPhrases: true)
        if delta.revised { onRevision(previousSnapshot, snapshot, delta.uncertain) }
        previousSnapshot = snapshot
        if !delta.text.isEmpty { onText(delta.text, true) }
        onText(delta.draft, false)
    }

    public func finish() async throws {
        if !pending.isEmpty && manager != nil {
            var last = pending
            pending.removeAll()
            last.append(contentsOf: repeatElement(0, count: VadManager.chunkSize - last.count))
            try await feed(last)
        }
        try await finishUtterance()
    }

    public func cancel() async {
        cancelled = true; token = UUID()
        updates?.cancel(); updates = nil
        let manager = self.manager; self.manager = nil
        await manager?.cancel()
        pending.removeAll(); preRoll.removeAll()
    }

    private static func buffer(_ samples: [Float]) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in buffer.floatChannelData![0].update(from: source.baseAddress!, count: samples.count) }
        return buffer
    }
}

public struct FluidProbeResult: Sendable {
    public let text: String
    public let firstTextSeconds: Double?
    public let processingSeconds: Double
    public let audioSeconds: Double
    public let ctcWindows: Int
    public let appliedTerms: [String]
}

private final class FluidProbe: @unchecked Sendable {
    private let lock = NSLock()
    private let started = Date()
    private var texts: [String] = []
    private var first: Double?
    func receive(_ text: String, final: Bool) {
        lock.lock(); defer { lock.unlock() }
        if final && !text.isEmpty {
            if first == nil { first = Date().timeIntervalSince(started) }
            texts.append(text)
        }
    }
    func result(audioSeconds: Double, ctcWindows: Int, appliedTerms: [String]) -> FluidProbeResult {
        lock.lock(); defer { lock.unlock() }
        return FluidProbeResult(text: texts.joined(separator: " "), firstTextSeconds: first,
            processingSeconds: Date().timeIntervalSince(started), audioSeconds: audioSeconds,
            ctcWindows: ctcWindows, appliedTerms: appliedTerms)
    }
}

private extension SlidingWindowAsrManager {
    func translatorSnapshot() -> String {
        [confirmedTranscript, volatileTranscript].filter { !$0.isEmpty }.joined(separator: " ")
    }
}
