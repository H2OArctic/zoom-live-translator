import SwiftUI
import TranslatorCore

struct ChannelCard: View {
    @Bindable var model: TranslatorModel
    let direction: Direction
    let onSettings: () -> Void

    private var incoming: Bool { direction == .incoming }
    private var enabled: Binding<Bool> { incoming ? $model.incomingEnabled : $model.outgoingEnabled }
    private var pair: Binding<LanguagePair> { incoming ? $model.incomingLanguagePair : $model.outgoingLanguagePair }
    private var voice: Binding<Bool> { incoming ? $model.incomingVoice : $model.outgoingVoice }
    private var backend: TranslationBackend { incoming ? model.incomingBackend : model.outgoingBackend }
    private var output: String {
        let id = incoming ? model.listeningOutputID : model.meetingOutputID
        return model.devices.first(where: { $0.id == id })?.name ?? (incoming ? "Выбери наушники" : "Нужен виртуальный вход")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: incoming ? "macwindow" : "mic")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(enabled.wrappedValue ? AppTheme.accent : .secondary)
                    .frame(width: 34, height: 34)
                    .background(AppTheme.inset, in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 3) {
                    Text(incoming ? "Собеседник" : "Твоя речь").font(.system(size: 15, weight: .semibold))
                    Text(incoming ? "Звук Zoom или браузера" : "Микрофон → перевод → Zoom")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Toggle(incoming ? "Переводить собеседника" : "Переводить мой микрофон", isOn: enabled)
                    .toggleStyle(.switch).controlSize(.small).labelsHidden()
                    .accessibilityLabel(incoming ? "Переводить собеседника" : "Переводить мой микрофон")
            }
            HStack(spacing: 10) {
                if incoming {
                    Picker("Приложение", selection: $model.applicationSelection) {
                        Text(model.automaticApplicationTitle).tag(ApplicationSourcePolicy.automatic)
                        if let unavailable = model.unavailableApplicationTitle {
                            Text(unavailable).tag(model.applicationSelection)
                        }
                        Divider()
                        ForEach(model.applications, id: \.bundleIdentifier) { app in
                            Text(app.applicationName).tag(app.bundleIdentifier)
                        }
                    }.labelsHidden().frame(maxWidth: .infinity, alignment: .leading).accessibilityLabel("Источник звука собеседника")
                    Button { Task { await model.refreshApplications() } } label: { Image(systemName: "arrow.clockwise") }
                        .help("Обновить приложения").accessibilityLabel("Обновить приложения")
                } else {
                    Picker("Микрофон", selection: $model.microphoneID) {
                        Text("Выбери микрофон").tag(UInt32(0))
                        ForEach(model.devices.filter { $0.isInput && !$0.isVirtual }) { device in Text(device.name).tag(device.id) }
                    }.labelsHidden().frame(maxWidth: .infinity, alignment: .leading).accessibilityLabel("Физический микрофон")
                    Button { model.refreshDevices() } label: { Image(systemName: "arrow.clockwise") }
                        .help("Обновить устройства").accessibilityLabel("Обновить устройства")
                }
            }
            Picker("Направление", selection: pair) {
                ForEach(LanguagePair.allCases) { pair in Text(pair.title).tag(pair) }
            }.pickerStyle(.segmented).accessibilityLabel(incoming ? "Направление перевода собеседника" : "Направление перевода микрофона")
            HStack {
                Label(backend == .ollama ? "TranslateGemma 4B" : "Apple Translation", systemImage: "cpu")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Toggle("Озвучка \(pair.wrappedValue.target.uppercased())", isOn: voice)
                    .toggleStyle(.checkbox).font(.system(size: 11))
            }
            HStack(spacing: 6) {
                Image(systemName: incoming ? "headphones" : "arrow.up.forward.app")
                Text(output).lineLimit(1).help(output)
                Spacer(minLength: 0)
                Button("Настроить", action: onSettings).buttonStyle(.borderless)
            }
            .font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(PanelSurface())
        .disabled(model.isRunning || model.isBusy)
    }
}
