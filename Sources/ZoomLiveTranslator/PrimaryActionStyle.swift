import SwiftUI

struct PrimaryActionStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isEnabled ? Color.black.opacity(0.9) : Color.secondary)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(isEnabled ? AppTheme.brandMint : AppTheme.inset, in: RoundedRectangle(cornerRadius: 10))
            .contentShape(RoundedRectangle(cornerRadius: 10))
            .scaleEffect(configuration.isPressed && isEnabled && !reduceMotion ? 0.96 : 1)
            .opacity(configuration.isPressed && isEnabled ? 0.85 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
