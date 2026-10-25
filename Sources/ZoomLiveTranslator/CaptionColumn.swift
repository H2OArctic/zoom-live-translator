import SwiftUI
import TranslatorCore

struct CaptionColumn: View {
    let direction: Direction
    let languagePair: LanguagePair
    let captions: [Caption]
    let draft: String
    let isEnabled: Bool
    let onRetry: (UUID) -> Void
    let onReplay: (UUID) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(direction == .incoming ? "Перевод собеседника" : "Перевод твоей речи")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(languagePair.title).font(.system(size: 10, weight: .semibold)).monospaced()
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(AppTheme.inset, in: Capsule())
            }.padding(16)
            ScrollViewReader { proxy in
                GeometryReader { geometry in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            if captions.isEmpty && draft.isEmpty {
                                emptyState.frame(minHeight: max(0, geometry.size.height - 30))
                            }
                            ForEach(captions) { caption in
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        Text(caption.languagePair.title).font(.system(size: 10, weight: .medium)).monospaced()
                                        Spacer()
                                        Text(caption.backend == .ollama ? "TranslateGemma" : "Apple")
                                            .font(.system(size: 10))
                                    }.foregroundStyle(.secondary)
                                    if caption.speakerTracking {
                                        Label(caption.speakerName.map { "≈ " + $0 } ?? "Говорящий не определён", systemImage: "person.wave.2")
                                            .font(.system(size: 12, weight: .semibold))
                                            .help("Имя прочитано из окна Zoom; сопоставление с речью приблизительное")
                                            .foregroundStyle(caption.speakerName == nil ? Color.secondary : AppTheme.accent)
                                    }
                                    Text(caption.original).font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(3)
                                    Text(caption.translated).font(.system(size: 17, weight: .medium)).lineSpacing(4)
                                        .foregroundStyle(caption.elapsedSeconds == nil && !caption.canRetry ? Color.secondary : Color.primary)
                                    ForEach(caption.qualityWarnings, id: \.self) { warning in
                                        Label(warning, systemImage: "exclamationmark.triangle")
                                            .font(.system(size: 11)).foregroundStyle(.orange)
                                    }
                                    HStack {
                                        if let elapsed = caption.elapsedSeconds {
                                            Label("\(elapsed, format: .number.precision(.fractionLength(1))) с", systemImage: "clock")
                                                .font(.system(size: 10)).monospacedDigit().foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        if caption.canRetry {
                                            Button("Повторить перевод") { onRetry(caption.id) }.controlSize(.small)
                                        } else if caption.elapsedSeconds != nil && !caption.isTranslating {
                                            Button { onReplay(caption.id) } label: { Label("Озвучить", systemImage: "speaker.wave.2") }
                                                .controlSize(.small)
                                        }
                                    }
                                }
                                .textSelection(.enabled)
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(AppTheme.inset, in: RoundedRectangle(cornerRadius: 12))
                            }
                            if !draft.isEmpty {
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: "waveform").foregroundStyle(AppTheme.accent)
                                    Text(draft).font(.system(size: 13)).foregroundStyle(.secondary).textSelection(.enabled)
                                }.padding(14)
                            }
                            Color.clear.frame(height: 1).id("bottom")
                        }
                        .padding(.horizontal, 14).padding(.bottom, 14)
                    }
                    .onChange(of: captions.count) { proxy.scrollTo("bottom", anchor: .bottom) }
                    .onChange(of: captions.last?.translated) { proxy.scrollTo("bottom", anchor: .bottom) }
                    .onChange(of: draft) { proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 180, maxHeight: .infinity)
        .modifier(PanelSurface())
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            HStack(alignment: .center, spacing: 5) {
                ForEach(Array([12, 24, 38, 22, 32, 16, 10].enumerated()), id: \.offset) { _, height in
                    Capsule().fill(Color.secondary.opacity(isEnabled ? 0.25 : 0.12))
                        .frame(width: 4, height: CGFloat(height))
                }
            }.frame(height: 44).accessibilityHidden(true)
            Text(isEnabled ? "Здесь появится перевод" : "Поток выключен")
                .font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
            Text(isEnabled ? "Оригинал и перевод — рядом, фраза за фразой." : "Включи его в карточке выше, когда понадобится.")
                .font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(.vertical, 36)
        .frame(maxWidth: .infinity)
    }
}
