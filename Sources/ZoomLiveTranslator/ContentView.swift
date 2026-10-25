import SwiftUI
import Translation
import TranslatorCore

struct ContentView: View {
    @Bindable var model: TranslatorModel
    @AppStorage("appearance") private var appearance = AppAppearance.system.rawValue
    @State private var showingSettings = false
    @State private var showingTextCheck = false
    @State private var showingQueues = false

    var body: some View {
        let configuration = model.preparation
        VStack(alignment: .leading, spacing: 18) {
            header
            HStack(alignment: .top, spacing: 16) {
                ChannelCard(model: model, direction: .incoming) { showingSettings = true }
                ChannelCard(model: model, direction: .outgoing) { showingSettings = true }
            }
            if model.speakerTrackingEnabled {
                Label(model.speakerStatus, systemImage: "person.wave.2")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let error = model.journalError ?? model.errorMessage { errorBanner(error) }
            HStack(alignment: .top, spacing: 16) {
                CaptionColumn(direction: .incoming, languagePair: model.incomingLanguagePair,
                              captions: model.captions.filter { $0.direction == .incoming }, draft: model.incomingDraft,
                              isEnabled: model.incomingEnabled, onRetry: model.retryCaption, onReplay: model.replayCaption)
                CaptionColumn(direction: .outgoing, languagePair: model.outgoingLanguagePair,
                              captions: model.captions.filter { $0.direction == .outgoing }, draft: model.outgoingDraft,
                              isEnabled: model.outgoingEnabled, onRetry: model.retryCaption, onReplay: model.replayCaption)
            }.frame(maxHeight: .infinity)
            DisclosureGroup(isExpanded: $showingTextCheck) {
                HStack(spacing: 12) {
                    Picker("Направление", selection: $model.manualLanguagePair) {
                        ForEach(LanguagePair.allCases) { pair in Text(pair.title).tag(pair) }
                    }.labelsHidden().frame(width: 120).accessibilityLabel("Направление ручного перевода")
                    TextField("Введи фразу для проверки перевода", text: $model.manualText)
                        .textFieldStyle(.roundedBorder).onSubmit { model.translateManual() }
                    Button("Перевести") { model.translateManual() }
                        .disabled(model.manualText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isBusy)
                }.padding(.top, 10)
            } label: {
                Label("Проверка текста", systemImage: "text.cursor").font(.system(size: 12, weight: .medium))
            }
            footer
        }
        .padding(24)
        .padding(.top, 16)
        .background(AppTheme.canvas)
        .background(InitialFocusReset(settingsPresented: showingSettings).frame(width: 0, height: 0))
        .tint(AppTheme.accent)
        .preferredColorScheme((AppAppearance(rawValue: appearance) ?? .system).colorScheme)
        .sheet(isPresented: $showingSettings) { SettingsView(model: model, appearance: $appearance) }
        .task { await model.watchApplications() }
        .translationTask(configuration) { session in
            await model.prepare(using: session, version: configuration?.version)
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            BrandMark().frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text("Live Translator").font(.system(size: 23, weight: .bold, design: .rounded))
                Text("Zoom · Английский ↔ русский").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            HStack(spacing: 6) {
                if model.isRecordingAudio {
                    Label("Запись аудио", systemImage: "record.circle.fill")
                        .foregroundStyle(.red)
                        .font(.system(size: 11, weight: .medium))
                }
                Circle().fill(model.isRunning ? AppTheme.accent : Color.secondary.opacity(0.6)).frame(width: 6, height: 6)
                Text(model.isRunning ? "В эфире" : (model.isBusy ? "Подготовка" : (model.hasPendingWork ? "Обработка" : "Ожидание")))
                    .font(.system(size: 11, weight: .medium))
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(AppTheme.inset, in: Capsule())
            Button { showingSettings = true } label: { Label("Настройки", systemImage: "slider.horizontal.3") }
                .controlSize(.large).keyboardShortcut(",", modifiers: .command)
            Menu {
                if model.isPreparing {
                    Button("Отменить подготовку") { model.cancelPreparation() }
                } else {
                    Button("Подготовить языки") { model.prepareLanguages() }.disabled(model.isBusy || model.isRunning)
                }
                Button("Проверить / прогреть Ollama") { Task { await model.prepareOllama() } }
                    .disabled(model.isBusy || model.isRunning || model.hasPendingWork)
                Divider()
                Toggle("Журнал в файл", isOn: $model.journalEnabled)
                Button("Сохранить журнал…") { model.exportJournal() }.disabled(model.journalURL == nil)
                Button("Показать журналы") { model.showJournal() }
                Divider()
                Button("Очистить историю", role: .destructive) { model.clearHistory() }
            } label: { Image(systemName: "ellipsis").foregroundStyle(.primary).frame(width: 28, height: 28) }
            .menuStyle(.borderlessButton).menuIndicator(.hidden)
            .frame(width: 28).help("Модели, журнал и история").accessibilityLabel("Модели, журнал и история")
            Button {
                Task {
                    if model.isRunning || model.hasPendingWork { await model.stop() }
                    else { await model.start() }
                }
            } label: {
                Label(model.isRunning ? "Остановить" : (model.hasPendingWork ? "Сбросить" : "Начать перевод"),
                      systemImage: model.isRunning || model.hasPendingWork ? "stop.fill" : "play.fill")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(PrimaryActionStyle())
            .disabled(model.isBusy).keyboardShortcut(.return, modifiers: .command)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Rectangle().fill(AppTheme.border).frame(height: 1)
            HStack(alignment: .center, spacing: 14) {
                if model.isBusy { ProgressView().controlSize(.small) }
                VStack(alignment: .leading, spacing: 5) {
                    Text(model.status).font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    if let progress = model.preparationProgress {
                        TimelineView(.periodic(from: .now, by: 1)) { _ in
                            ProgressView(value: progress.fractionCompleted).frame(maxWidth: 300)
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                if model.isPreparing {
                    Button("Отменить") { model.cancelPreparation() }
                }
                if model.outgoingEnabled {
                    HStack(spacing: 6) {
                        Image(systemName: "mic").foregroundStyle(.secondary)
                        SignalMeter(level: model.microphoneLevel)
                    }
                }
                if model.speechPaused { Button("Продолжить озвучку") { model.resumeSpeech() } }
                Button { showingQueues.toggle() } label: { Image(systemName: "waveform.path").frame(width: 20, height: 20) }
                    .buttonStyle(.borderless).help("Очереди перевода и озвучки").accessibilityLabel("Очереди перевода и озвучки")
                    .popover(isPresented: $showingQueues) {
                        TimelineView(.periodic(from: .now, by: 1)) { _ in
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Очереди перевода").font(.headline)
                                Text(model.backlogDescription).font(.callout).monospacedDigit().textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                            }.padding(20).frame(width: 360)
                        }
                    }
                Image(systemName: model.journalEnabled ? "doc.text" : "doc")
                    .foregroundStyle(.secondary).help(model.journalEnabled ? "Текстовый журнал включён" : "Журнал выключен")
                Button("Сохранить журнал…") { model.exportJournal() }.disabled(model.journalURL == nil)
                    .controlSize(.small)
            }
        }
    }

    private func errorBanner(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(text).font(.callout).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            Button {
                model.errorMessage = nil
                model.journalError = nil
            } label: { Image(systemName: "xmark") }
            .buttonStyle(.borderless).help("Закрыть сообщение").accessibilityLabel("Закрыть сообщение")
        }
        .padding(14)
        .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
    }
}
