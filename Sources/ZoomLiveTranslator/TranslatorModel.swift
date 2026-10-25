import AVFoundation
import AppKit
import Observation
import ScreenCaptureKit
import Speech
import Translation
import TranslatorCore
import UniformTypeIdentifiers
import LocalRecognition

struct Caption: Identifiable {
    let id: UUID
    let direction: Direction
    let languagePair: LanguagePair
    let original: String
    let backend: TranslationBackend
    var translated: String
    var speakerName: String? = nil
    var speakerTracking = false
    var qualityWarnings: [String] = []
    var elapsedSeconds: Double?
    var canRetry = false
    var isTranslating = true
}

@MainActor @Observable
final class TranslatorModel {
    var devices: [AudioDevice] = AudioDevices.list()
    var applications: [SCRunningApplication] = []
    private(set) var selectedApplication: Int32 = 0
    var applicationSelection = UserDefaults.standard.string(forKey: "applicationSource") ?? ApplicationSourcePolicy.automatic {
        didSet {
            UserDefaults.standard.set(applicationSelection, forKey: "applicationSource")
            resolveApplicationSelection()
        }
    }
    private var sourceCandidates: [ApplicationSource] = []
    private var refreshingApplications = false
    var automaticApplicationTitle: String {
        ApplicationSourcePolicy.resolve(ApplicationSourcePolicy.automatic, in: sourceCandidates).map { "Автоматически · " + $0.name } ?? "Автоматически · ожидаю Zoom или браузер"
    }
    var unavailableApplicationTitle: String? {
        guard applicationSelection != ApplicationSourcePolicy.automatic,
              !applications.contains(where: { $0.bundleIdentifier == applicationSelection }) else { return nil }
        return (UserDefaults.standard.string(forKey: "applicationSourceName") ?? "Выбранное приложение") + " · не запущено"
    }
    var microphoneID: AudioDeviceID = 0
    var listeningOutputID: AudioDeviceID = 0
    var meetingOutputID: AudioDeviceID = 0
    var incomingEnabled = true
    var outgoingEnabled = false
    var accurateTranslation = UserDefaults.standard.object(forKey: "accurateTranslation") as? Bool ?? true {
        didSet { UserDefaults.standard.set(accurateTranslation, forKey: "accurateTranslation") }
    }
    var recognitionBackend = RecognitionBackend(rawValue: UserDefaults.standard.string(forKey: "recognitionBackend") ?? (FluidEngine.modelsAvailable ? "fluid" : "apple")) ?? .apple {
        didSet { UserDefaults.standard.set(recognitionBackend.rawValue, forKey: "recognitionBackend") }
    }
    var technicalGlossary = UserDefaults.standard.string(forKey: "technicalGlossary") ?? TranslationQuality.defaultGlossary {
        didSet { UserDefaults.standard.set(String(technicalGlossary.prefix(3000)), forKey: "technicalGlossary") }
    }
    var recognitionVocabulary = UserDefaults.standard.string(forKey: "recognitionVocabulary") ?? TranslationQuality.recognitionHints {
        didSet { UserDefaults.standard.set(String(recognitionVocabulary.prefix(3000)), forKey: "recognitionVocabulary") }
    }
    var fluidStatus = FluidEngine.modelsAvailable ? "Модели FluidAudio установлены" : "FluidAudio ещё не подготовлен"
    var whisperStatus = "Whisper не проверен · Apple остаётся доступным"
    private var phraseBuffers: [Direction: PhraseBuffer] = [:]
    private var phraseTasks: [Direction: Task<Void, Never>] = [:]
    var incomingBackend = TranslationBackend.ollama
    var outgoingBackend = TranslationBackend.ollama
    var incomingLanguagePair = LanguagePair.englishToRussian
    var outgoingLanguagePair = LanguagePair.russianToEnglish
    var speakerTrackingEnabled = false {
        didSet {
            if !isRunning {
                speakerStatus = speakerTrackingEnabled ? "Обнови список и выбери окно встречи Zoom" : "Определение говорящего выключено"
            }
        }
    }
    var announceSpeakerNames = true
    var distinctSpeakerVoices = true
    var speakerWindowID: CGWindowID = 0
    var speakerWindows: [SCWindow] = []
    var speakerStatus = "Определение говорящего выключено"
    var detectedSpeaker: String?
    private let speakerMonitor = ZoomSpeakerMonitor()
    private var speakerEvidence = SpeakerEvidence()
    private var incomingUtteranceStart: Date?
    private var speakerVoiceIDs: [String: String] = [:]
    private var lastSpokenSpeaker: String?
    var incomingVoice = true { didSet { if !incomingVoice { incomingSpeaker.stop() } } }
    var outgoingVoice = true { didSet { if !outgoingVoice { outgoingSpeaker.stop() } } }
    var isRunning = false
    var isBusy = false
    var status = "Сначала подготовь локальные языки и выбери аудиоустройства."
    var errorMessage: String? {
        didSet { if let errorMessage { log("error", data: ["message": errorMessage]) } }
    }
    var journalEnabled = true {
        didSet {
            if journalEnabled {
                if journalFailed {
                    let previous = journal
                    journal = nil
                    journalFailed = false
                    Task { try? await previous?.close() }
                }
                ensureJournal()
                log("logging_enabled")
            }
            else { journal?.record("logging_disabled") }
        }
    }
    var journalError: String?
    var journalURL: URL? { journal?.fileURL }
    var audioRecordingEnabled = UserDefaults.standard.object(forKey: "audioRecordingEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(audioRecordingEnabled, forKey: "audioRecordingEnabled") }
    }
    var isRecordingAudio: Bool { isRunning && audioRecorders.keys.contains { !failedAudioRecordings.contains($0) } }
    private var audioRecorders: [Direction: SessionAudioRecorder] = [:]
    private var failedAudioRecordings: Set<Direction> = []
    var captions: [Caption] = []
    var incomingDraft = ""
    var outgoingDraft = ""
    var microphoneLevel = 0.0
    var preparation: TranslationSession.Configuration?
    var preparationProgress: Progress?
    var isPreparing: Bool { preparationToken != nil }
    var manualText = ""
    var manualLanguagePair = LanguagePair.russianToEnglish
    var speechRate: Float = 0.52 {
        didSet { incomingSpeaker.preferredRate = speechRate; outgoingSpeaker.preferredRate = speechRate }
    }
    var hasPendingWork: Bool { phraseBuffers.values.contains(where: { $0.phrase != nil }) || incomingLane.hasWork || outgoingLane.hasWork || incomingSpeaker.hasWork || outgoingSpeaker.hasWork }
    var speechPaused: Bool { incomingSpeaker.isPaused || outgoingSpeaker.isPaused }
    var backlogDescription: String {
        let incomingAge = incomingLane.waitingSince.map { max(0, Int(Date().timeIntervalSince($0))) } ?? 0
        return "Приложение: \(incomingLane.count) фраз, ожидание \(incomingAge) с · озвучка ≈\(Int(ceil(incomingSpeaker.estimatedSeconds))) с | Микрофон: \(outgoingLane.count) фраз · озвучка ≈\(Int(ceil(outgoingSpeaker.estimatedSeconds))) с"
    }

    private let microphone = MicrophoneCapture()
    private let meeting = MeetingCapture()
    private let incomingSpeech = SpeechPipeline()
    private let outgoingSpeech = SpeechPipeline()
    private let incomingSpeaker = SpeechOutput()
    private let outgoingSpeaker = SpeechOutput()
    private let incomingLane = TranslationLane()
    private let outgoingLane = TranslationLane()
    private let ollama = OllamaClient(timeout: 15)
    private var pauseTask: Task<Void, Never>?
    private var failureTask: Task<Void, Never>?
    private var generation = UUID()
    private var preparationToken: UUID?
    private var preparationWatchdog: Task<Void, Never>?
    private var journal: SessionJournal?
    private var journalFailed = false
    private var lastPartialLog: [Direction: Date] = [:]

    init() {
        selectDefaultDevices()
        incomingSpeaker.onError = { [weak self] message in
            self?.log("speech_error", channel: .incoming, data: ["message": message])
            self?.errorMessage = message
        }
        outgoingSpeaker.onError = { [weak self] message in
            self?.log("speech_error", channel: .outgoing, data: ["message": message])
            self?.errorMessage = message
        }
        incomingSpeaker.onOverload = { [weak self] in self?.pauseForBacklog() }
        outgoingSpeaker.onOverload = { [weak self] in self?.pauseForBacklog() }
    }

    func refreshDevices() {
        devices = AudioDevices.list()
        selectDefaultDevices()
    }

    private func selectDefaultDevices() {
        if !devices.contains(where: { $0.id == microphoneID && $0.isInput && !$0.isVirtual }) {
            let preferred = AudioDevices.defaultDevice(input: true)
            microphoneID = devices.first(where: { $0.id == preferred && $0.isInput && !$0.isVirtual })?.id
                ?? devices.first(where: { $0.isInput && !$0.isVirtual })?.id ?? 0
        }
        if !devices.contains(where: { $0.id == listeningOutputID && $0.isOutput && !$0.isVirtual }) {
            let preferred = AudioDevices.defaultDevice(input: false)
            listeningOutputID = devices.first(where: { $0.id == preferred && $0.isOutput && !$0.isVirtual })?.id
                ?? devices.first(where: { $0.isOutput && !$0.isVirtual })?.id ?? 0
        }
        if !devices.contains(where: { $0.id == meetingOutputID && $0.isOutput && $0.isInput && $0.isVirtual }) {
            meetingOutputID = devices.first(where: { $0.isOutput && $0.isInput && $0.isVirtual })?.id ?? 0
        }
    }

    func refreshSpeakerWindows() async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            speakerWindows = content.windows.filter {
                $0.owningApplication?.bundleIdentifier == "us.zoom.xos" && $0.frame.width >= 90 && $0.frame.height >= 60
            }.sorted { $0.frame.width * $0.frame.height > $1.frame.width * $1.frame.height }
            if !speakerWindows.contains(where: { $0.windowID == speakerWindowID }) {
                speakerWindowID = speakerWindows.first?.windowID ?? 0
            }
            speakerStatus = speakerWindows.isEmpty ? "Открой встречу в нативном Zoom и обнови окна" : "Окно выбрано · проверка начнётся вместе с переводом"
        } catch { speakerStatus = "Нет доступа к окну Zoom: \(error.localizedDescription)" }
    }

    func inspectSpeakerWindow() async {
        guard !isBusy, !isRunning else { return }
        guard let window = speakerWindows.first(where: { $0.windowID == speakerWindowID }),
              let processID = window.owningApplication?.processID else {
            speakerStatus = "Сначала обнови список и выбери окно встречи Zoom"
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            let reader = ZoomSpeakerReader()
            let name = try await reader.read(windowID: speakerWindowID, processID: processID)
            detectedSpeaker = name
            speakerStatus = name.map { "В кадре: \($0) · проверка без звука" } ?? "Имя не найдено. Нужна одна зелёная рамка с видимым именем."
        } catch { speakerStatus = "Не удалось проверить окно: \(error.localizedDescription)" }
    }

    private func startSpeakerMonitor(application: SCRunningApplication, token: UUID) {
        guard speakerTrackingEnabled else { return }
        guard recognitionBackend == .apple else {
            speakerStatus = "Подписи имён пока доступны с распознаванием Apple"
            return
        }
        speakerEvidence = SpeakerEvidence()
        incomingUtteranceStart = nil
        guard application.bundleIdentifier == "us.zoom.xos", speakerWindowID != 0 else {
            speakerStatus = "Выбери нативный Zoom и окно встречи в настройках"
            return
        }
        speakerStatus = "Ищу зелёную рамку и имя говорящего…"
        speakerMonitor.start(windowID: speakerWindowID, processID: application.processID) { [weak self] name, error in
            guard let self, self.generation == token, self.isRunning else { return }
            self.speakerEvidence.observe(name)
            let previous = self.detectedSpeaker
            let previousStatus = self.speakerStatus
            self.detectedSpeaker = name
            self.speakerStatus = error ?? name.map { "В кадре: \($0) · имя определяется по окну" } ?? "Говорящий не определён · нужна одна зелёная рамка с видимым именем"
            if let error, error != previousStatus {
                self.log("speaker_detection_failed", channel: .incoming, data: ["message": error])
            }
            if previous != name {
                self.log("speaker_observed", channel: .incoming, data: ["speaker": name ?? "unknown", "source": "zoom_window_ocr"])
            }
        }
    }

    func watchApplications() async {
        while !Task.isCancelled {
            if !isRunning && !isBusy && !hasPendingWork { await refreshApplications() }
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
        }
    }

    private func resolveApplicationSelection() {
        guard !isRunning else { return }
        selectedApplication = ApplicationSourcePolicy.resolve(applicationSelection, in: sourceCandidates)?.processID ?? 0
        if applicationSelection != ApplicationSourcePolicy.automatic,
           let application = applications.first(where: { $0.bundleIdentifier == applicationSelection }) {
            UserDefaults.standard.set(application.applicationName, forKey: "applicationSourceName")
        }
    }

    func refreshApplications() async {
        while refreshingApplications {
            do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
        }
        guard !Task.isCancelled, !isRunning else { return }
        refreshingApplications = true
        defer { refreshingApplications = false }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            guard !Task.isCancelled, !isRunning else { return }
            let candidates = content.applications.compactMap { application -> ApplicationSource? in
                guard let running = NSRunningApplication(processIdentifier: application.processID) else { return nil }
                return ApplicationSource(processID: application.processID, bundleID: application.bundleIdentifier,
                    name: application.applicationName,
                    isUserApplication: running.activationPolicy == .regular && running.bundleURL?.pathExtension == "app")
            }.sorted { $0.processID < $1.processID }
            let visibleCandidates = ApplicationSourcePolicy.visible(candidates)
            guard visibleCandidates != sourceCandidates else { return }
            sourceCandidates = visibleCandidates
            applications = sourceCandidates.compactMap { candidate in
                content.applications.first { $0.processID == candidate.processID }
            }
            resolveApplicationSelection()
        } catch {
            errorMessage = "Нет доступа к звуку приложений. Разреши запись экрана и системного аудио в настройках macOS. \(error.localizedDescription)"
        }
    }

    func prepareLanguages() {
        guard !isBusy, !isRunning else { return }
        isBusy = true
        errorMessage = nil
        preparationProgress = nil
        let token = UUID()
        preparationToken = token
        status = "Запуск подготовки языков…"
        if preparation == nil {
            preparation = .init(source: .init(identifier: "en"), target: .init(identifier: "ru"))
        } else {
            preparation?.invalidate()
        }
        watchPreparation(token: token, seconds: 15,
                         message: "macOS не запустила подготовку языков. Повтори подготовку; если ошибка повторится, перезапусти приложение.")
    }

    func prepare(using session: sending TranslationSession, version: Int?) async {
        guard let token = preparationToken, preparation?.version == version else { return }
        watchPreparation(token: token, seconds: 900,
                         message: "Подготовка языков не завершилась за 15 минут. Проверь интернет и повтори. Захват звука не запускался.")
        defer {
            if preparationToken == token {
                preparationToken = nil
                preparationWatchdog?.cancel()
                preparationWatchdog = nil
                preparationProgress = nil
                isBusy = false
            }
        }
        do {
            status = "Проверка установленных языков перевода EN ↔ RU…"
            let needsApple = incomingBackend == .apple || outgoingBackend == .apple
            if needsApple {
                let availability = LanguageAvailability()
                let translationStatus = await availability.status(from: .init(identifier: "en"), to: .init(identifier: "ru"))
                guard preparationToken == token else { return }
                guard translationStatus != .unsupported else { throw AppError("Перевод EN ↔ RU недоступен на этом Mac.") }
                if translationStatus != .installed {
                    status = "Загрузка языков перевода EN ↔ RU. Подтверди загрузку в окне macOS; нужен интернет."
                    try await session.prepareTranslation()
                }
            }
            guard preparationToken == token else { return }
            for locale in ["en-US", "ru-RU"] {
                status = "Подготовка локального распознавания \(locale)…"
                preparationProgress = nil
                try await SpeechPipeline.prepare(locale: locale) { [weak self] progress in
                    guard let self, self.preparationToken == token else { return }
                    self.preparationProgress = progress
                }
                guard preparationToken == token else { return }
                try Task.checkCancellation()
            }
            if needsApple {
                try await checkTranslation(.englishToRussian)
                guard preparationToken == token else { return }
                try await checkTranslation(.russianToEnglish)
            }
            guard preparationToken == token else { return }
            status = "Локальные модели готовы. Выбери Zoom и нажми «Начать»."
        } catch {
            guard preparationToken == token else { return }
            errorMessage = error.localizedDescription
            status = "Подготовка не завершена. Можно повторить."
        }
    }

    func cancelPreparation(message: String? = nil) {
        guard preparationToken != nil else { return }
        preparationToken = nil
        preparationWatchdog?.cancel()
        preparationWatchdog = nil
        preparationProgress?.cancel()
        preparationProgress = nil
        isBusy = false
        preparation?.invalidate()
        status = "Подготовка остановлена. Можно повторить; уже загруженные языки сохраняются."
        if let message { errorMessage = message }
    }

    private func watchPreparation(token: UUID, seconds: Int, message: String) {
        preparationWatchdog?.cancel()
        preparationWatchdog = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(seconds)) }
            catch { return }
            guard let self, self.preparationToken == token else { return }
            self.cancelPreparation(message: message)
        }
    }

    private func checkTranslation(_ languagePair: LanguagePair) async throws {
        let availability = LanguageAvailability()
        guard await availability.status(from: .init(identifier: languagePair.source), to: .init(identifier: languagePair.target)) == .installed else {
            throw AppError("Локальный перевод \(languagePair.title) не установлен. Нажми «Подготовить языки».")
        }
    }

    func start() async {
        guard !isBusy, !isRunning else { return }
        guard !hasPendingWork else { errorMessage = "Дождись очереди перевода и озвучки или останови её кнопкой сверху."; return }
        isBusy = true
        await stop()
        errorMessage = nil
        generation = UUID()
        let token = generation
        ensureJournal()
        log("capture_starting", data: journalSettings())
        defer { isBusy = false }
        do {
            guard incomingEnabled || outgoingEnabled else { throw AppError("Включи хотя бы одно направление.") }
            refreshDevices()
            if incomingEnabled { await refreshApplications() }
            let incomingPair = incomingLanguagePair
            let outgoingPair = outgoingLanguagePair
            if recognitionBackend == .fluid {
                status = "Подготовка локального FluidAudio…"
                try await FluidEngine.shared.prepare()
            }
            if recognitionBackend == .whisper {
                status = "Загрузка локального Whisper…"
                try await WhisperEngine.shared.prepare()
            }
            if incomingEnabled && incomingBackend == .apple { try await checkTranslation(incomingPair) }
            if outgoingEnabled && outgoingBackend == .apple { try await checkTranslation(outgoingPair) }
            if (incomingEnabled && incomingBackend == .ollama) || (outgoingEnabled && outgoingBackend == .ollama) {
                status = "Прогрев локальной TranslateGemma перед захватом…"
                try await ollama.warmUp()
            }
            if incomingEnabled && incomingVoice {
                guard listeningOutputID != 0 else { throw AppError("Выбери наушники для русской озвучки.") }
            }
            if outgoingEnabled && outgoingVoice {
                guard devices.contains(where: { $0.id == meetingOutputID && $0.isVirtual && $0.isInput && $0.isOutput }) else {
                    throw AppError("Для озвучки \(outgoingPair.title) в Zoom нужен виртуальный вход, например BlackHole 2ch. Установи его или отключи озвучку микрофона.")
                }
            }
            if outgoingEnabled {
                guard microphoneID != 0 else { throw AppError("На Mac mini нужен внешний микрофон или гарнитура. Выбери устройство ввода.") }
                let permission = await AVCaptureDevice.requestAccess(for: .audio)
                guard permission else { throw AppError("Разреши доступ к микрофону в настройках macOS.") }
            }
            isRunning = true
            if incomingEnabled {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                guard let application = content.applications.first(where: { $0.processID == selectedApplication }),
                      let display = content.displays.first else { throw AppError("Открой Zoom и выбери его в списке приложений.") }
                startSpeakerMonitor(application: application, token: token)
                let ingress = try await incomingSpeech.start(locale: incomingPair.locale, backend: recognitionBackend, vocabulary: effectiveRecognitionVocabulary,
                    onText: { [weak self] text, final in self?.receive(text, final: final, direction: .incoming, languagePair: incomingPair, token: token) },
                    onRevision: { [weak self] old, new, uncertain in self?.recordRevision(old, new, uncertain: uncertain, direction: .incoming, token: token) },
                    onError: { [weak self] in self?.fail($0, token: token) })
                guard generation == token else { throw CancellationError() }
                beginAudioRecording(ingress: ingress, direction: .incoming, token: token)
                log("recognizer_started", channel: .incoming, data: ["recognizer": incomingSpeech.recognizerName, "locale": incomingPair.locale])
                try await meeting.start(application: application, display: display, ingress: ingress,
                                        onError: { [weak self] in self?.fail($0, token: token) })
                guard generation == token else { throw CancellationError() }
            }
            if outgoingEnabled {
                let ingress = try await outgoingSpeech.start(locale: outgoingPair.locale, backend: recognitionBackend, vocabulary: effectiveRecognitionVocabulary,
                    onText: { [weak self] text, final in self?.receive(text, final: final, direction: .outgoing, languagePair: outgoingPair, token: token) },
                    onLevel: { [weak self] level in
                        guard let self, self.generation == token, self.isRunning else { return }
                        self.microphoneLevel = level
                    },
                    onRevision: { [weak self] old, new, uncertain in self?.recordRevision(old, new, uncertain: uncertain, direction: .outgoing, token: token) },
                    onError: { [weak self] in self?.fail($0, token: token) })
                guard generation == token else { throw CancellationError() }
                beginAudioRecording(ingress: ingress, direction: .outgoing, token: token)
                log("recognizer_started", channel: .outgoing, data: ["recognizer": outgoingSpeech.recognizerName, "locale": outgoingPair.locale])
                try await microphone.start(device: microphoneID, ingress: ingress) { [weak self] message in
                    Task { @MainActor in self?.fail(message, token: token) }
                }
                guard generation == token else { throw CancellationError() }
            }
            status = "Перевод включён · \(recognitionBackend.title) · обработка на Mac"
            log("capture_started", data: journalSettings())
        } catch {
            await stop()
            errorMessage = error.localizedDescription
        }
    }

    func stop() async {
        cancelPreparation()
        let wasBusy = isBusy
        if isRunning || hasPendingWork { log("capture_stopped", data: ["reason": "stop_or_reset"]) }
        isBusy = true
        defer { isBusy = wasBusy }
        generation = UUID()
        for (direction, buffer) in phraseBuffers {
            if let phrase = buffer.phrase { log("recognition_group_cancelled", channel: direction, data: ["original": phrase.text]) }
        }
        phraseTasks.values.forEach { $0.cancel() }
        phraseTasks.removeAll(); phraseBuffers.removeAll()
        isRunning = false
        microphoneLevel = 0
        speakerMonitor.stop()
        detectedSpeaker = nil
        incomingUtteranceStart = nil
        lastSpokenSpeaker = nil
        speakerStatus = speakerTrackingEnabled ? "Определение говорящего остановлено" : "Определение говорящего выключено"
        await microphone.stop()
        incomingSpeaker.stop()
        outgoingSpeaker.stop()
        incomingLane.cancel()
        outgoingLane.cancel()
        pauseTask?.cancel()
        pauseTask = nil
        for index in captions.indices where captions[index].isTranslating {
            log("translation_cancelled", channel: captions[index].direction, jobID: captions[index].id,
                data: ["original": captions[index].original, "translated": captions[index].translated])
            captions[index].translated = captions[index].elapsedSeconds == nil ? "Перевод отменён" : captions[index].translated + "\nПеревод остановлен до завершения."
            captions[index].canRetry = true
            captions[index].isTranslating = false
        }
        await meeting.stop()
        await incomingSpeech.stop()
        await outgoingSpeech.stop()
        await finishAudioRecordings()
        incomingDraft = ""
        outgoingDraft = ""
        status = journalEnabled ? "Перевод остановлен. Журнал сохранён локально." : "Перевод остановлен. Запись журнала выключена."
    }

    private func fail(_ message: String, token: UUID) {
        guard generation == token, isRunning, failureTask == nil else { return }
        failureTask = Task { [weak self] in
            guard let self else { return }
            await self.stop()
            self.errorMessage = message
            self.failureTask = nil
        }
    }

    private func recordRevision(_ old: String, _ new: String, uncertain: Bool, direction: Direction, token: UUID) {
        guard generation == token, isRunning else { return }
        if uncertain { errorMessage = "Распознаватель сильно пересмотрел фразу. Неоднозначный участок пропущен; подробности в журнале. Перевод продолжается." }
        log("recognition_revision", channel: direction, data: ["previous": String(old.suffix(2000)), "revised": String(new.suffix(2000)),
            "alignment": uncertain ? "uncertain_skipped" : "reconciled", "alreadyTranslatedTextUnchanged": "true"])
    }

    private func receive(_ text: String, final: Bool, direction: Direction, languagePair: LanguagePair, token: UUID) {
        guard generation == token, isRunning else { return }
        if !final, Date().timeIntervalSince(lastPartialLog[direction] ?? .distantPast) >= 0.5 {
            lastPartialLog[direction] = Date()
            log("recognition_partial", channel: direction, data: ["original": text, "sourceLanguage": languagePair.source])
        }
        let pending = phraseBuffers[direction]?.phrase?.text ?? ""
        let draft = [pending, final ? "" : text].filter { !$0.isEmpty }.joined(separator: " ")
        if direction == .incoming { incomingDraft = draft }
        else { outgoingDraft = draft }
        if !final, accurateTranslation {
            phraseBuffers[direction]?.touch()
            schedulePhraseFlush(direction, token: token)
        }
        if direction == .incoming, speakerTrackingEnabled, recognitionBackend == .apple {
            let now = Date()
            if incomingUtteranceStart == nil { incomingUtteranceStart = now }
            if final {
                let speaker = recognitionBackend == .apple ? speakerEvidence.speaker(from: incomingUtteranceStart ?? now, through: now) : nil
                incomingUtteranceStart = nil
                acceptPhrase(RecognizedPhrase(text: text, speaker: speaker, tracking: true, pair: languagePair), direction: direction, token: token)
            }
        } else if final { acceptPhrase(RecognizedPhrase(text: text, pair: languagePair), direction: direction, token: token) }
    }

    private func acceptPhrase(_ phrase: RecognizedPhrase, direction: Direction, token: UUID) {
        if !accurateTranslation { submitPhrase(phrase, direction: direction); return }
        var buffer = phraseBuffers[direction] ?? PhraseBuffer()
        let ready = buffer.append(phrase)
        phraseBuffers[direction] = buffer
        if let ready { submitPhrase(ready, direction: direction) }
        if direction == .incoming { incomingDraft = buffer.phrase?.text ?? "" }
        else { outgoingDraft = buffer.phrase?.text ?? "" }
        log("recognition_final_fragment", channel: direction, data: ["original": phrase.text])
        schedulePhraseFlush(direction, token: token)
    }

    private func schedulePhraseFlush(_ direction: Direction, token: UUID) {
        phraseTasks[direction]?.cancel()
        guard let deadline = phraseBuffers[direction]?.deadline else { return }
        phraseTasks[direction] = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(max(0, deadline.timeIntervalSinceNow))) } catch { return }
            guard let self, self.generation == token, self.isRunning else { return }
            if let phrase = self.phraseBuffers[direction]?.take() { self.submitPhrase(phrase, direction: direction) }
            self.phraseTasks[direction] = nil
            if direction == .incoming { self.incomingDraft = "" } else { self.outgoingDraft = "" }
        }
    }

    private func submitPhrase(_ phrase: RecognizedPhrase, direction: Direction) {
        enqueue(phrase.text, direction: direction, languagePair: phrase.pair, speakerName: phrase.speaker, speakerTracking: phrase.tracking)
    }

    func prepareFluidAudio() async {
        guard !isBusy, !isRunning, !hasPendingWork else { return }
        isBusy = true
        fluidStatus = "Подготовка Parakeet v3, CTC-словаря и Silero VAD…"
        defer { isBusy = false }
        do {
            try await FluidEngine.shared.prepare(download: true)
            fluidStatus = "FluidAudio готов · обработка на Mac"
            recognitionBackend = .fluid
        } catch { fluidStatus = "FluidAudio не готов: \(error.localizedDescription)" }
    }

    func prepareWhisper() async {
        guard !isBusy, !isRunning, !hasPendingWork else { return }
        isBusy = true
        whisperStatus = "Загрузка модели Whisper Turbo и подготовка Core ML…"
        defer { isBusy = false }
        do {
            try await WhisperEngine.shared.prepare(download: true)
            whisperStatus = "Whisper готов · модель локальная, звук не запускался"
        } catch { whisperStatus = "Whisper не готов: \(error.localizedDescription)" }
    }

    func translateManual() {
        guard !isBusy, !manualText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let direction: Direction = manualLanguagePair == .englishToRussian ? .incoming : .outgoing
        enqueue(manualText, direction: direction, languagePair: manualLanguagePair, inputKind: "manual")
        manualText = ""
    }

    private func enqueue(_ text: String, direction: Direction, languagePair: LanguagePair, inputKind: String = "speech", speakerName: String? = nil, speakerTracking: Bool = false) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        ensureJournal()
        guard text.count <= 4000 else {
            log("input_rejected", channel: direction, data: ["original": text, "reason": "length_limit"])
            errorMessage = "Фраза слишком длинная. Раздели её на части до 4000 символов."
            return
        }
        let backend = direction == .incoming ? incomingBackend : outgoingBackend
        let job = TranslationJob(direction: direction, text: text, languagePair: languagePair, backend: backend,
                                 glossary: accurateTranslation ? technicalGlossary : "")
        let verifyQuality = accurateTranslation
        log("utterance", channel: direction, jobID: job.id, data: [
            "original": text, "input": inputKind, "speaker": speakerName ?? "unknown",
            "speakerSource": speakerTracking ? "zoom_window_ocr" : "none", "sourceLanguage": languagePair.source,
            "targetLanguage": languagePair.target, "backend": backend.rawValue,
            "model": backend == .ollama ? OllamaClient.model : "Apple Translation",
            "recognizer": direction == .incoming ? incomingSpeech.recognizerName : outgoingSpeech.recognizerName,
            "queuedAhead": String(direction == .incoming ? incomingLane.count : outgoingLane.count)
        ])
        captions.append(Caption(id: job.id, direction: direction, languagePair: languagePair, original: text, backend: backend, translated: "Переводится…", speakerName: speakerName, speakerTracking: speakerTracking))
        if captions.count > 100 { captions.removeFirst(captions.count - 100) }
        let lane = direction == .incoming ? incomingLane : outgoingLane
        let token = generation
        let accepted = lane.enqueue(job) { [weak self] job in
            guard let self else { return }
            let started = Date()
            self.log("translation_started", channel: job.direction, jobID: job.id,
                     data: ["queueWaitSeconds": String(started.timeIntervalSince(job.createdAt))])
            do {
                var translated: [String] = []
                for chunk in TextChunks.split(job.text, limit: 600) {
                    let result: String
                    if job.backend == .ollama {
                        let normalized = job.languagePair.source == "ru" ? TranslationNumbers.russianInput(chunk) : TechnicalTranslation.englishInput(chunk)
                        if normalized != chunk {
                            self.log("translation_normalized_input", channel: job.direction, jobID: job.id,
                                data: ["original": chunk, "modelInput": normalized])
                        }
                        result = try await self.ollama.translate(chunk, pair: job.languagePair, context: job.context, glossary: job.glossary)
                    } else {
                        try await self.checkTranslation(job.languagePair)
                        let session = TranslationSession(installedSource: .init(identifier: job.languagePair.source), target: .init(identifier: job.languagePair.target))
                        result = try await session.translate(chunk).targetText
                    }
                    guard !Task.isCancelled, self.generation == token else { return }
                    translated.append(result)
                    self.log("translation_chunk_completed", channel: job.direction, jobID: job.id, data: [
                        "originalChunk": chunk, "translatedChunk": result,
                        "translated": translated.joined(separator: " "),
                        "processingSeconds": String(Date().timeIntervalSince(started))
                    ])
                    if let index = self.captions.firstIndex(where: { $0.id == job.id }) {
                        self.captions[index].translated = translated.joined(separator: " ")
                        self.captions[index].elapsedSeconds = Date().timeIntervalSince(started)
                    }
                    if !verifyQuality { self.speak(result, direction: job.direction, languagePair: job.languagePair, jobID: job.id, speakerName: speakerName) }
                }
                let complete = translated.joined(separator: " ")
                let warnings = verifyQuality ? TranslationQuality.warnings(original: job.text, translated: complete, pair: job.languagePair) : []
                if let index = self.captions.firstIndex(where: { $0.id == job.id }) { self.captions[index].qualityWarnings = warnings }
                if verifyQuality { self.speak(complete, direction: job.direction, languagePair: job.languagePair, jobID: job.id, speakerName: speakerName) }
                if !warnings.isEmpty {
                    self.log("translation_quality_warning", channel: job.direction, jobID: job.id,
                             data: ["warnings": warnings.joined(separator: "; "), "original": job.text, "translated": complete, "autoSpeech": "normal_voice_settings"])
                }
                self.log("translation_completed", channel: job.direction, jobID: job.id, data: [
                    "original": job.text, "translated": translated.joined(separator: " "),
                    "processingSeconds": String(Date().timeIntervalSince(started)),
                    "elapsedSinceQueuedSeconds": String(Date().timeIntervalSince(job.createdAt))
                ])
                if let index = self.captions.firstIndex(where: { $0.id == job.id }) {
                    self.captions[index].isTranslating = false
                }
            } catch {
                guard !Task.isCancelled, self.generation == token else { return }
                self.log("translation_failed", channel: job.direction, jobID: job.id,
                         data: ["original": job.text, "message": error.localizedDescription])
                if let index = self.captions.firstIndex(where: { $0.id == job.id }) {
                    let partial = self.captions[index].elapsedSeconds == nil ? "" : self.captions[index].translated + "\n"
                    self.captions[index].translated = partial + "Не удалось завершить перевод. Оригинал сохранён."
                    self.captions[index].canRetry = true
                    self.captions[index].isTranslating = false
                }
                self.errorMessage = error.localizedDescription
            }
        }
        if !accepted {
            log("queue_rejected", channel: direction, jobID: job.id, data: ["original": text])
            if let index = captions.firstIndex(where: { $0.id == job.id }) {
                captions[index].translated = "Очередь переполнена. Нажми «Повторить перевод»."
                captions[index].canRetry = true
                captions[index].isTranslating = false
            }
            pauseForBacklog()
        } else {
            if lane.count >= 24 { pauseForBacklog() }
        }
    }

    func retryCaption(_ id: UUID) {
        guard let caption = captions.first(where: { $0.id == id }), !isBusy else { return }
        log("translation_retry", channel: caption.direction, jobID: id)
        enqueue(caption.original, direction: caption.direction, languagePair: caption.languagePair, inputKind: "retry", speakerName: caption.speakerName, speakerTracking: caption.speakerTracking)
    }

    func replayCaption(_ id: UUID) {
        guard let caption = captions.first(where: { $0.id == id }), caption.elapsedSeconds != nil,
              !caption.canRetry, !caption.isTranslating else { return }
        log("speech_replay", channel: caption.direction, jobID: id)
        speak(caption.translated, direction: caption.direction, languagePair: caption.languagePair, jobID: id, speakerName: caption.speakerName)
    }

    func resumeSpeech() { incomingSpeaker.resume(); outgoingSpeaker.resume() }

    func prepareOllama() async {
        guard !isBusy, !isRunning else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            status = "Прогрев локальной TranslateGemma…"
            try await ollama.warmUp()
            status = "TranslateGemma 4B готова. Захват звука не запускался."
        } catch { errorMessage = error.localizedDescription; status = "Ollama не готова." }
    }

    private func pauseForBacklog() {
        guard isRunning, pauseTask == nil else { return }
        isRunning = false
        for direction in Direction.allCases {
            phraseTasks[direction]?.cancel()
            if let phrase = phraseBuffers[direction]?.take() { submitPhrase(phrase, direction: direction) }
        }
        phraseTasks.removeAll()
        speakerMonitor.stop()
        detectedSpeaker = nil
        incomingUtteranceStart = nil
        microphoneLevel = 0
        log("capture_paused", data: ["reason": "backlog", "backlog": backlogDescription])
        isBusy = true
        let token = generation
        status = "Вход приостановлен из-за отставания. Принятые фразы продолжают переводиться и звучать; после очереди нажми «Начать»."
        pauseTask = Task { [weak self] in
            guard let self else { return }
            await self.microphone.stop()
            await self.meeting.stop()
            await self.incomingSpeech.stop()
            await self.outgoingSpeech.stop()
            await self.finishAudioRecordings()
            guard self.generation == token else { return }
            self.pauseTask = nil
            self.isBusy = false
        }
    }

    private func speak(_ text: String, direction: Direction, languagePair: LanguagePair, jobID: UUID? = nil, speakerName: String? = nil) {
        if direction == .incoming, incomingVoice, listeningOutputID != 0 {
            let spokenText: String
            if announceSpeakerNames, let speakerName, speakerName != lastSpokenSpeaker {
                spokenText = "\(speakerName). \(text)"
            } else { spokenText = text }
            let voiceID = distinctSpeakerVoices ? voiceID(for: speakerName, language: languagePair.voiceLocale) : nil
            let accepted = incomingSpeaker.speak(spokenText, language: languagePair.voiceLocale, device: listeningOutputID, voiceID: voiceID)
            if accepted { lastSpokenSpeaker = speakerName }
            log(accepted ? "speech_queued" : "speech_rejected", channel: direction, jobID: jobID,
                data: ["text": spokenText, "speaker": speakerName ?? "unknown", "voiceID": voiceID ?? "system", "locale": languagePair.voiceLocale, "output": devices.first(where: { $0.id == listeningOutputID })?.name ?? "unknown"])
        }
        if direction == .outgoing, outgoingVoice,
           devices.contains(where: { $0.id == meetingOutputID && $0.isVirtual && $0.isInput && $0.isOutput }) {
            let accepted = outgoingSpeaker.speak(text, language: languagePair.voiceLocale, device: meetingOutputID)
            log(accepted ? "speech_queued" : "speech_rejected", channel: direction, jobID: jobID,
                data: ["text": text, "locale": languagePair.voiceLocale, "output": devices.first(where: { $0.id == meetingOutputID })?.name ?? "unknown"])
        }
    }

    private func voiceID(for speaker: String?, language: String) -> String? {
        guard let speaker else { return nil }
        let key = language + ":" + speaker
        if let voice = speakerVoiceIDs[key] { return voice }
        let voices = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(String(language.prefix(2))) }
            .sorted { $0.identifier < $1.identifier }
        var seen = Set<String>()
        let unique = voices.filter { seen.insert($0.name).inserted }
        guard !unique.isEmpty else { return nil }
        let used = speakerVoiceIDs.filter { $0.key.hasPrefix(language + ":") }.count
        let selected = unique[used % unique.count].identifier
        speakerVoiceIDs[key] = selected
        return selected
    }

    func clearHistory() { log("history_cleared"); captions.removeAll() }

    func showJournal() {
        if let journalURL {
            NSWorkspace.shared.activateFileViewerSelecting([journalURL])
            return
        }
        do {
            let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                     appropriateFor: nil, create: true)
            let directory = support.appendingPathComponent("ZoomLiveTranslator/Sessions")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            NSWorkspace.shared.open(directory)
        } catch { journalError = "Не удалось открыть папку журналов: \(error.localizedDescription)" }
    }

    func exportJournal() {
        guard let journal else { return }
        let panel = NSSavePanel()
        panel.title = "Сохранить журнал распознавания и перевода"
        panel.nameFieldStringValue = journal.fileURL.deletingPathExtension().lastPathComponent
        panel.allowedContentTypes = [UTType(exportedAs: "local.zoom-live-translator.jsonl", conformingTo: .plainText)]
        panel.isExtensionHidden = false
        panel.canCreateDirectories = true
        panel.begin { [weak self] response in
            guard response == .OK, let destination = panel.url else { return }
            Task { @MainActor [weak self] in
                let scoped = destination.startAccessingSecurityScopedResource()
                defer { if scoped { destination.stopAccessingSecurityScopedResource() } }
                do {
                    try await journal.export(to: destination)
                    self?.status = "Снимок журнала сохранён: \(destination.lastPathComponent)"
                } catch { self?.journalError = "Не удалось сохранить журнал: \(error.localizedDescription)" }
            }
        }
    }

    func shutdown() async {
        await stop()
        log("session_closed")
        do { try await journal?.close() }
        catch { journalError = "Не удалось завершить запись журнала: \(error.localizedDescription)" }
    }

    private func ensureJournal() {
        guard journalEnabled, journal == nil else { return }
        do {
            let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                     appropriateFor: nil, create: true)
            journal = try SessionJournal(directory: support.appendingPathComponent("ZoomLiveTranslator/Sessions")) { [weak self] message in
                Task { @MainActor in
                    self?.journalFailed = true
                    self?.journalEnabled = false
                    self?.journalError = "Ошибка записи журнала: \(message). Запись отключена; после устранения ошибки включи её снова."
                }
            }
            log("session_started", data: ["os": ProcessInfo.processInfo.operatingSystemVersionString,
                                          "timezone": TimeZone.current.identifier,
                                          "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"])
        } catch {
            journalFailed = true
            journalEnabled = false
            journalError = "Не удалось создать журнал: \(error.localizedDescription)"
        }
    }

    private var effectiveRecognitionVocabulary: String {
        RecognitionVocabulary.parse(recognitionVocabulary + ", SQLite, WAN, LAN, NOC, IPC, iceoryx, loopback, drawdown, L3")
            .joined(separator: ", ")
    }

    private func finishAudioRecordings() async {
        let recordings = audioRecorders
        audioRecorders.removeAll()
        failedAudioRecordings.removeAll()
        for recorder in recordings.values { await recorder.finish() }
    }

    private func beginAudioRecording(ingress: AudioIngress, direction: Direction, token: UUID) {
        guard audioRecordingEnabled else { return }
        do {
            let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                     appropriateFor: nil, create: true)
            let directory = support.appendingPathComponent("ZoomLiveTranslator/Sessions", isDirectory: true)
            let prefix = journal?.fileURL.deletingPathExtension().lastPathComponent ?? "audio-\(UUID().uuidString)"
            let url = directory.appendingPathComponent("\(prefix)-\(token.uuidString.prefix(8))-\(direction.rawValue).caf")
            let recorder = try SessionAudioRecorder(fileURL: url) { [weak self] event, data in
                Task { @MainActor in
                    guard let self else { return }
                    self.log(event, channel: direction, data: data)
                    if event == "audio_recording_failed" {
                        self.errorMessage = data["message"]
                        if self.generation == token { self.failedAudioRecordings.insert(direction) }
                    }
                }
            }
            audioRecorders[direction] = recorder
            ingress.record(to: recorder)
        } catch { errorMessage = "Не удалось включить запись аудио: \(error.localizedDescription). Перевод продолжается." }
    }

    private func log(_ event: String, channel: Direction? = nil, jobID: UUID? = nil, data: [String: String] = [:]) {
        guard journalEnabled else { return }
        journal?.record(event, channel: channel?.rawValue, jobID: jobID, data: data)
    }

    private func journalSettings() -> [String: String] {
        ["application": applications.first(where: { $0.processID == selectedApplication })?.applicationName ?? "unselected",
         "microphone": devices.first(where: { $0.id == microphoneID })?.name ?? "unselected",
         "listeningOutput": devices.first(where: { $0.id == listeningOutputID })?.name ?? "unselected",
         "meetingOutput": devices.first(where: { $0.id == meetingOutputID })?.name ?? "unselected",
         "incomingEnabled": String(incomingEnabled), "outgoingEnabled": String(outgoingEnabled),
         "recognitionBackend": recognitionBackend.rawValue, "accurateTranslation": String(accurateTranslation),
         "recognitionVocabulary": effectiveRecognitionVocabulary,
         "audioRecordingEnabled": String(audioRecordingEnabled),
         "translationGlossary": String(technicalGlossary.prefix(3000)),
         "incomingPair": incomingLanguagePair.title, "outgoingPair": outgoingLanguagePair.title,
         "incomingBackend": incomingBackend.rawValue, "outgoingBackend": outgoingBackend.rawValue,
         "speakerTracking": String(speakerTrackingEnabled), "speakerWindowID": String(speakerWindowID),
         "announceSpeakerNames": String(announceSpeakerNames), "distinctSpeakerVoices": String(distinctSpeakerVoices),
         "incomingVoice": String(incomingVoice), "outgoingVoice": String(outgoingVoice), "speechRate": String(speechRate)]
    }
}
