import SwiftUI
import TranslatorCore

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: TranslatorModel
    @Binding var appearance: String

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Настройки").font(.title2.bold())
                    Text("Источники, голос и локальные модели").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Готово") { dismiss() }.keyboardShortcut(.defaultAction)
            }.padding(24)
            Form {
                Section("Качество речи и перевода") {
                    Toggle("Точный перевод · фразы и проверка", isOn: $model.accurateTranslation)
                    Text("Объединяет связанные фрагменты с ожиданием до 6 секунд. Ollama получает текущую фразу и словарь терминов. Возможные изменения чисел, отрицания и имени Alice подсвечиваются в тексте; озвучка продолжается. Проверки не гарантируют точность.")
                        .font(.callout).foregroundStyle(.secondary)
                    Picker("Распознавание", selection: $model.recognitionBackend) {
                        ForEach(RecognitionBackend.allCases) { backend in Text(backend.title).tag(backend) }
                    }
                    Button("Подготовить FluidAudio") { Task { await model.prepareFluidAudio() } }
                    Text(model.fluidStatus).font(.callout).foregroundStyle(.secondary)
                    Text("Parakeet v3 распознаёт EN/RU, Silero определяет паузы. CTC-словарь проверяет английские термины по звуку; для русского он отключён. Используются перекрывающиеся окна около 3 секунд; итоговая задержка зависит от фразы и нагрузки. Имена с репликами FluidAudio пока не сопоставляются.")
                        .font(.callout).foregroundStyle(.secondary)
                    DisclosureGroup("Термины распознавания") {
                        Text("Короткие слова и названия через запятую, до 64 терминов. SQLite, WAN, LAN, NOC и другие технические термины дополняют список в пределах лимита. Для английского FluidAudio и для Whisper; Apple этот список не использует.")
                            .font(.callout).foregroundStyle(.secondary)
                        TextEditor(text: $model.recognitionVocabulary).frame(minHeight: 90)
                    }
                    Button("Подготовить Whisper") { Task { await model.prepareWhisper() } }
                    Text(model.whisperStatus).font(.callout).foregroundStyle(.secondary)
                    Text("Whisper загружает модель при подготовке. Затем распознаёт на Mac. Он пока не сравнивался на твоём звонке; добавляет ожидание пауз и обработку фрагментов до 10 секунд. Имена говорящих с его репликами пока не сопоставляются.")
                        .font(.callout).foregroundStyle(.secondary)
                    DisclosureGroup("Технический словарь для Ollama") {
                        TextEditor(text: $model.technicalGlossary).frame(minHeight: 120)
                        Button("Вернуть исходный словарь") { model.technicalGlossary = TranslationQuality.defaultGlossary }
                    }
                }.disabled(model.isRunning || model.isBusy || model.hasPendingWork)
                Section("Собеседник") {
                    Picker("Переводчик", selection: $model.incomingBackend) {
                        ForEach(TranslationBackend.allCases) { backend in Text(backend.title).tag(backend) }
                    }
                    Picker("Выход озвучки", selection: $model.listeningOutputID) {
                        Text("Выбери наушники").tag(UInt32(0))
                        ForEach(model.devices.filter { $0.isOutput && !$0.isVirtual }) { device in Text(device.name).tag(device.id) }
                    }
                }.disabled(model.isRunning || model.isBusy)
                Section("Кто говорит · экспериментально") {
                    Toggle("Определять имя по окну Zoom", isOn: $model.speakerTrackingEnabled)
                        .disabled(model.isRunning || model.isBusy)
                    if model.speakerTrackingEnabled {
                        Picker("Окно встречи", selection: $model.speakerWindowID) {
                            Text("Выбери окно Zoom").tag(UInt32(0))
                            ForEach(model.speakerWindows, id: \.windowID) { window in
                                Text(window.title.flatMap { $0.isEmpty ? nil : $0 } ?? "Окно Zoom без названия").tag(window.windowID)
                            }
                        }.disabled(model.isRunning || model.isBusy)
                        Button("Обновить окна Zoom") { Task { await model.refreshSpeakerWindows() } }
                            .disabled(model.isRunning || model.isBusy)
                        Button("Проверить окно без звука") { Task { await model.inspectSpeakerWindow() } }
                            .disabled(model.isRunning || model.isBusy || model.speakerWindowID == 0)
                        Toggle("Произносить имя при смене собеседника", isOn: $model.announceSpeakerNames)
                        Toggle("Разные системные голоса для собеседников", isOn: $model.distinctSpeakerVoices)
                        Text("Нужен нативный Zoom: одно видимое имя внутри зелёной рамки говорящего. Кадры обрабатываются локально и не сохраняются. При смене говорящего внутри фразы имя не назначается. Разные голоса доступны, если они установлены в macOS; голоса могут повторяться.")
                            .font(.callout).foregroundStyle(.secondary)
                        Text(model.speakerStatus).font(.callout).foregroundStyle(.secondary)
                    }
                }
                Section("Твоя речь") {
                    Picker("Переводчик", selection: $model.outgoingBackend) {
                        ForEach(TranslationBackend.allCases) { backend in Text(backend.title).tag(backend) }
                    }
                    Picker("Выход в Zoom", selection: $model.meetingOutputID) {
                        Text("Нужен BlackHole 2ch или аналог").tag(UInt32(0))
                        ForEach(model.devices.filter { $0.isInput && $0.isOutput && $0.isVirtual }) { device in Text(device.name).tag(device.id) }
                    }
                    Label("В Zoom этот же виртуальный вход нужно выбрать как микрофон. Динамиком Zoom должны оставаться наушники.", systemImage: "info.circle")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.disabled(model.isRunning || model.isBusy)
                Section("Голос") {
                    HStack {
                        Text("Скорость")
                        Slider(value: $model.speechRate, in: 0.45...0.65).accessibilityLabel("Скорость озвучки")
                        Text("\(Double(model.speechRate / 0.5), format: .number.precision(.fractionLength(1)))×")
                            .monospacedDigit().frame(width: 44)
                    }
                    Text("При накоплении очереди голос автоматически немного ускоряется.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Section("Приложение") {
                    Picker("Оформление", selection: $appearance) {
                        ForEach(AppAppearance.allCases) { appearance in Text(appearance.title).tag(appearance.rawValue) }
                    }
                    Toggle("Сохранять текстовый журнал", isOn: $model.journalEnabled)
                    Toggle("Записывать исходное аудио", isOn: $model.audioRecordingEnabled)
                        .disabled(model.isRunning || model.isBusy)
                    Text("Запись начинается вместе с переводом. Звук приложения и включённого микрофона сохраняется локально отдельными файлами рядом с журналом. Файлы не удаляются автоматически.")
                        .font(.callout).foregroundStyle(.secondary)
                    Button("Показать журналы и аудио") { model.showJournal() }
                    Button("Обновить аудиоустройства") { model.refreshDevices() }
                        .disabled(model.isRunning || model.isBusy)
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 640, height: 650)
        .background(InitialFocusReset().frame(width: 0, height: 0))
        .tint(AppTheme.accent)
    }
}
