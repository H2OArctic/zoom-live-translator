import AVFoundation
import Speech
import TranslatorCore

@MainActor
final class SpeechPipeline {
    private(set) var recognizerName = ""
    private let whisper = WhisperPipeline()
    private let fluid = FluidPipeline()
    private var analyzer: SpeechAnalyzer?
    private var resultsTask: Task<Void, Never>?
    private var analysisTask: Task<Void, Never>?
    private(set) var ingress: AudioIngress?

    static func module(locale: String) async throws -> any SpeechModule {
        let desired = Locale(identifier: locale)
        if SpeechTranscriber.isAvailable,
           let supported = await SpeechTranscriber.supportedLocale(equivalentTo: desired) {
            return SpeechTranscriber(locale: supported, preset: .progressiveTranscription)
        }
        if let supported = await DictationTranscriber.supportedLocale(equivalentTo: desired) {
            return DictationTranscriber(locale: supported,
                                       contentHints: [], transcriptionOptions: [.punctuation],
                                       reportingOptions: [.volatileResults, .frequentFinalization], attributeOptions: [])
        }
        throw AppError("Локальное распознавание \(locale) недоступно на этом Mac.")
    }

    static func prepare(locale: String, onProgress: (Progress) -> Void) async throws {
        let module = try await module(locale: locale)
        try Task.checkCancellation()
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
            try Task.checkCancellation()
            onProgress(request.progress)
            try await request.downloadAndInstall()
        }
        try Task.checkCancellation()
        guard await AssetInventory.status(forModules: [module]) == .installed else {
            throw AppError("Модель \(locale) ещё не установлена.")
        }
    }

    func start(locale: String, backend: RecognitionBackend = .apple, vocabulary: String = "",
               onText: @escaping @MainActor (String, Bool) -> Void,
               onLevel: (@MainActor @Sendable (Double) -> Void)? = nil,
               onRevision: @escaping @MainActor (String, String, Bool) -> Void = { _, _, _ in },
               onError: @escaping @MainActor (String) -> Void) async throws -> AudioIngress {
        if backend == .fluid {
            recognizerName = locale.hasPrefix("en") ? "FluidAudio Parakeet v3 + Silero + CTC (conservative)" : "FluidAudio Parakeet v3 + Silero"
            return try await fluid.start(language: String(locale.prefix(2)), vocabulary: vocabulary,
                                         onText: onText, onLevel: onLevel, onRevision: onRevision, onError: onError)
        }
        if backend == .whisper {
            recognizerName = "Whisper Large v3 Turbo"
            return try await whisper.start(language: String(locale.prefix(2)), vocabulary: vocabulary,
                                           onText: onText, onLevel: onLevel, onError: onError)
        }
        let module = try await Self.module(locale: locale)
        recognizerName = String(describing: type(of: module))
        guard await AssetInventory.status(forModules: [module]) == .installed else {
            throw AppError("Сначала нажми «Подготовить языки»: нужна локальная модель \(locale).")
        }
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module]) else {
            throw AppError("Нет совместимого формата распознавания.")
        }
        let analyzer = SpeechAnalyzer(modules: [module])
        self.analyzer = analyzer
        try await analyzer.prepareToAnalyze(in: format)
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream(bufferingPolicy: .bufferingOldest(64))
        let levelCallback: (@Sendable (Double) -> Void)?
        if let onLevel {
            levelCallback = { level in
                Task { @MainActor in onLevel(level) }
            }
        } else {
            levelCallback = nil
        }
        let ingress = AudioIngress(format: format, continuation: continuation, onLevel: levelCallback) { message in
            Task { @MainActor in onError(message) }
        }
        self.ingress = ingress
        resultsTask = Task {
            do {
                if let transcriber = module as? SpeechTranscriber {
                    for try await result in transcriber.results {
                        guard !Task.isCancelled else { return }
                        onText(String(result.text.characters), result.isFinal)
                    }
                } else if let transcriber = module as? DictationTranscriber {
                    for try await result in transcriber.results {
                        guard !Task.isCancelled else { return }
                        onText(String(result.text.characters), result.isFinal)
                    }
                }
            } catch {
                if !Task.isCancelled { onError(error.localizedDescription) }
            }
        }
        analysisTask = Task {
            do {
                try await analyzer.start(inputSequence: stream)
            } catch {
                if !Task.isCancelled { onError(error.localizedDescription) }
            }
        }
        return ingress
    }

    func stop() async {
        whisper.stop()
        await fluid.stop()
        ingress?.finish()
        ingress = nil
        resultsTask?.cancel()
        analysisTask?.cancel()
        await analyzer?.cancelAndFinishNow()
        resultsTask = nil
        analysisTask = nil
        analyzer = nil
    }
}
