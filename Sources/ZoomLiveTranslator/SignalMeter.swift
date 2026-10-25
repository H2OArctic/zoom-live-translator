import SwiftUI

struct SignalMeter: View {
    let level: Double

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<12) { index in
                Capsule().fill(Double(index) / 12 < level ? AppTheme.accent : Color.secondary.opacity(0.18))
                    .frame(width: 3, height: 5 + CGFloat(index % 4) * 3)
            }
        }
        .frame(height: 16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Сигнал микрофона")
        .accessibilityValue("\(Int(level * 100)) процентов")
    }
}
