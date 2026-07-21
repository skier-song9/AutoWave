import SwiftUI

/// App-wide neon-space design tokens.
enum AppTheme {
    static let background = Color(hex: 0x05060F)
    static let backgroundElevated = Color(hex: 0x0A0A18)
    static let panel = Color(hex: 0x12121F)
    static let panelSoft = Color(hex: 0x17172A)
    static let line = Color(hex: 0x2A2A45)
    static let muted = Color(hex: 0x8A8AA8)
    static let mutedBright = Color(hex: 0xB9B9D6)
    static let text = Color(hex: 0xF4F4FF)
    static let accentPurple = Color(hex: 0xA855F7)
    static let accentBlue = Color(hex: 0x3B82F6)
    static let accentCyan = Color(hex: 0x38BDF8)
    static let notePink = Color(hex: 0xF048C6)
    static let green = Color(hex: 0x34D399)
    static let orange = Color(hex: 0xF97316)
    static let red = Color(hex: 0xEF4444)

    static let accent = accentPurple
    static let accentSecondary = accentBlue
    static let good = green
    static let danger = red
    static let panelSecondary = panelSoft

    static var accentGradient: LinearGradient {
        LinearGradient(
            colors: [accentPurple, Color(hex: 0x6D5CF6), accentBlue],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    /// Destructive fill — styleguide `.button.danger`.
    static var dangerGradient: LinearGradient {
        LinearGradient(
            colors: [Color(hex: 0xF87171), red, Color(hex: 0xC22B2B)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Danger border — styleguide DeleteConfirmDialog red↔purple edge.
    static var dangerBorderGradient: LinearGradient {
        LinearGradient(
            colors: [red, Color(hex: 0xCF4C95), accentPurple],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
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
            .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(AppTheme.line, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
    }
}

struct GradientCTAButtonStyle: ButtonStyle {
    var secondary = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .heavy, design: .rounded))
            .foregroundStyle(secondary ? AppTheme.text : .white)
            .padding(.horizontal, 20)
            .frame(minHeight: 44)
            .background {
                Capsule(style: .continuous)
                    .fill(secondary ? AppTheme.backgroundElevated : AppTheme.accentPurple)
                    .overlay {
                        if secondary {
                            Capsule(style: .continuous)
                                .strokeBorder(AppTheme.accentGradient, lineWidth: 1.5)
                        } else {
                            Capsule(style: .continuous)
                                .fill(AppTheme.accentGradient)
                        }
                    }
            }
            .shadow(
                color: secondary ? .clear : AppTheme.accentPurple.opacity(0.45),
                radius: secondary ? 0 : 22
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Destructive red pill CTA — styleguide `.button.danger`
/// (red gradient fill, white heavy label, red glow).
struct DangerCTAButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .frame(minHeight: 44)
            .background {
                Capsule(style: .continuous)
                    .fill(AppTheme.dangerGradient)
            }
            .shadow(color: AppTheme.red.opacity(0.5), radius: 22)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct CircleIconButton: View {
    let systemName: String
    let compact: Bool
    let action: () -> Void

    init(
        systemName: String,
        compact: Bool = false,
        action: @escaping () -> Void
    ) {
        self.systemName = systemName
        self.compact = compact
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: compact ? 18 : 25, weight: .semibold))
                .foregroundStyle(AppTheme.text)
                .frame(width: compact ? 42 : 56, height: compact ? 42 : 56)
                .background(AppTheme.backgroundElevated, in: Circle())
                .overlay {
                    Circle()
                        .strokeBorder(AppTheme.accentGradient, lineWidth: 2)
                }
                .shadow(color: AppTheme.accentPurple.opacity(0.45), radius: 12)
                .shadow(color: AppTheme.accentBlue.opacity(0.42), radius: 12)
        }
        .buttonStyle(.plain)
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
