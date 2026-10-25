import SwiftUI

struct BrandMark: View {
    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.25)
                    .fill(LinearGradient(colors: [AppTheme.brandMint, Color(red: 0.10, green: 0.65, blue: 0.62)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                BubbleShape().fill(.white)
                    .frame(width: size * 0.57, height: size * 0.39)
                    .position(x: size * 0.40, y: size * 0.37)
                BubbleShape().fill(Color(red: 0.05, green: 0.19, blue: 0.19))
                    .rotationEffect(.degrees(180))
                    .frame(width: size * 0.54, height: size * 0.38)
                    .position(x: size * 0.62, y: size * 0.64)
                waveform(size: size, color: Color(red: 0.05, green: 0.19, blue: 0.19))
                    .position(x: size * 0.39, y: size * 0.32)
                waveform(size: size, color: AppTheme.brandMint)
                    .position(x: size * 0.63, y: size * 0.69)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private func waveform(size: CGFloat, color: Color) -> some View {
        HStack(spacing: size * 0.038) {
            ForEach(Array([0.09, 0.18, 0.12].enumerated()), id: \.offset) { _, height in
                Capsule().fill(color).frame(width: size * 0.04, height: size * CGFloat(height))
            }
        }
        .frame(width: size * 0.25, height: size * 0.2)
    }
}

private struct BubbleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path(roundedRect: CGRect(x: 0, y: 0, width: rect.width, height: rect.height * 0.82), cornerRadius: rect.width * 0.16)
        path.move(to: CGPoint(x: rect.width * 0.15, y: rect.height * 0.7))
        path.addLine(to: CGPoint(x: rect.width * 0.15, y: rect.height))
        path.addLine(to: CGPoint(x: rect.width * 0.39, y: rect.height * 0.77))
        path.closeSubpath()
        return path
    }
}
