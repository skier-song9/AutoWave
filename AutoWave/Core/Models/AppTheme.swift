import SwiftUI

/// App-wide design tokens ported from tools/notegen-playground.html (dark panel language).
enum AppTheme {
    static let background = Color(hex: 0x0A0D14)
    static let panel = Color(hex: 0x111722)
    static let panelSecondary = Color(hex: 0x171E2C)
    static let line = Color(hex: 0x283247)
    static let muted = Color(hex: 0x8994A8)
    static let text = Color(hex: 0xEDF2FF)
    static let accent = Color(hex: 0x6DDCFF)
    static let accentSecondary = Color(hex: 0xA98CFF)
    static let good = Color(hex: 0x63E6AE)
    static let danger = Color(hex: 0xFF7188)

    static var accentGradient: LinearGradient {
        LinearGradient(
            colors: [accent, accentSecondary],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

private struct PanelCardModifier: ViewModifier {
    var padding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(AppTheme.line, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
    }
}

extension View {
    func panelCard(padding: CGFloat = 16) -> some View {
        modifier(PanelCardModifier(padding: padding))
    }

    /// Full-screen app background used outside the gameplay scene.
    func appScreenBackground() -> some View {
        frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppTheme.background.ignoresSafeArea())
    }
}
