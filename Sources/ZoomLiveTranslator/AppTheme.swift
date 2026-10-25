import SwiftUI

enum AppTheme {
    static let brandMint = Color(red: 0.24, green: 0.82, blue: 0.67)
    static let accent = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.24, green: 0.82, blue: 0.67, alpha: 1)
            : NSColor(red: 0.02, green: 0.42, blue: 0.36, alpha: 1)
    })
    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let surface = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.14, green: 0.15, blue: 0.16, alpha: 1)
            : .white
    })
    static let inset = Color.primary.opacity(0.04)
    static let border = Color.primary.opacity(0.08)
    static let corner: CGFloat = 18
}

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: "Как в macOS"
        case .light: "Светлая"
        case .dark: "Тёмная"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

struct PanelSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: AppTheme.corner))
            .overlay(RoundedRectangle(cornerRadius: AppTheme.corner).strokeBorder(AppTheme.border, lineWidth: 1))
    }
}
