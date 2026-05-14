import SwiftUI

enum Theme {
    // Core palette
    static let bg = Color(red: 0.04, green: 0.045, blue: 0.055)        // deep graphite
    static let bgElevated = Color(red: 0.07, green: 0.078, blue: 0.092)
    static let surface = Color(red: 0.11, green: 0.12, blue: 0.14)      // dark titanium
    static let surfaceHi = Color(red: 0.16, green: 0.175, blue: 0.20)
    static let line = Color.white.opacity(0.06)
    static let lineStrong = Color.white.opacity(0.12)

    // Text
    static let textPrimary = Color(red: 0.96, green: 0.97, blue: 0.99)
    static let textSecondary = Color(red: 0.66, green: 0.70, blue: 0.76)
    static let textTertiary = Color(red: 0.44, green: 0.48, blue: 0.54)

    // Accent — muted steel blue
    static let accent = Color(red: 0.45, green: 0.62, blue: 0.82)
    static let accentDim = Color(red: 0.30, green: 0.44, blue: 0.62)
    static let accentGlow = Color(red: 0.55, green: 0.74, blue: 0.94)

    // Semantic
    static let good = Color(red: 0.50, green: 0.78, blue: 0.62)
    static let warn = Color(red: 0.92, green: 0.74, blue: 0.42)
    static let bad  = Color(red: 0.88, green: 0.46, blue: 0.46)

    // Tier metallics
    static let bronze = Color(red: 0.72, green: 0.49, blue: 0.30)
    static let silver = Color(red: 0.78, green: 0.82, blue: 0.86)
    static let gold   = Color(red: 0.92, green: 0.78, blue: 0.40)
    static let elite  = Color(red: 0.58, green: 0.78, blue: 0.94)
    static let greek  = Color(red: 0.96, green: 0.92, blue: 0.78)

    // Gradients
    static let bgGradient = LinearGradient(
        colors: [
            Color(red: 0.03, green: 0.04, blue: 0.06),
            Color(red: 0.06, green: 0.07, blue: 0.09),
            Color(red: 0.04, green: 0.05, blue: 0.07)
        ],
        startPoint: .top, endPoint: .bottom
    )

    static let metallicShine = LinearGradient(
        colors: [
            Color.white.opacity(0.18),
            Color.white.opacity(0.03),
            Color.white.opacity(0.0),
            Color.white.opacity(0.06)
        ],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
}

// MARK: - Typography

extension Font {
    static let aetherDisplay = Font.system(size: 44, weight: .semibold, design: .default).width(.condensed)
    static let aetherTitle = Font.system(size: 28, weight: .semibold, design: .default)
    static let aetherTitle2 = Font.system(size: 22, weight: .semibold, design: .default)
    static let aetherHeadline = Font.system(size: 17, weight: .semibold, design: .default)
    static let aetherBody = Font.system(size: 15, weight: .regular, design: .default)
    static let aetherCaption = Font.system(size: 12, weight: .medium, design: .default)
    static let aetherMono = Font.system(size: 14, weight: .medium, design: .monospaced)
    static let aetherNumber = Font.system(size: 56, weight: .semibold, design: .rounded).monospacedDigit()
}

// MARK: - Glass card

struct GlassCard: ViewModifier {
    var radius: CGFloat = 22
    var stroke: Bool = true
    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(Theme.surface.opacity(0.55))
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .opacity(0.4)
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(Theme.metallicShine)
                        .opacity(0.4)
                        .blendMode(.plusLighter)
                }
            }
            .overlay {
                if stroke {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(Theme.lineStrong, lineWidth: 0.6)
                }
            }
            .clipShape(.rect(cornerRadius: radius))
    }
}

extension View {
    func glassCard(radius: CGFloat = 22, stroke: Bool = true) -> some View {
        modifier(GlassCard(radius: radius, stroke: stroke))
    }

    func softShadow() -> some View {
        shadow(color: .black.opacity(0.35), radius: 18, x: 0, y: 10)
    }
}

// MARK: - Ambient animated background

struct AmbientBackground: View {
    @State private var phase: CGFloat = 0
    var intensity: CGFloat = 1.0

    var body: some View {
        ZStack {
            Theme.bgGradient.ignoresSafeArea()
            // Soft drifting accent glow
            RadialGradient(
                colors: [Theme.accent.opacity(0.22 * intensity), .clear],
                center: .init(x: 0.2 + 0.15 * sin(phase), y: 0.15 + 0.08 * cos(phase * 0.7)),
                startRadius: 10, endRadius: 480
            )
            .blendMode(.plusLighter)
            .ignoresSafeArea()

            RadialGradient(
                colors: [Theme.accentDim.opacity(0.18 * intensity), .clear],
                center: .init(x: 0.8 + 0.12 * cos(phase * 0.6), y: 0.85 + 0.06 * sin(phase * 0.8)),
                startRadius: 10, endRadius: 520
            )
            .blendMode(.plusLighter)
            .ignoresSafeArea()

            // Fine noise / vignette
            LinearGradient(
                colors: [.clear, Color.black.opacity(0.55)],
                startPoint: .center, endPoint: .bottom
            )
            .ignoresSafeArea()
        }
        .onAppear {
            withAnimation(.linear(duration: 26).repeatForever(autoreverses: true)) {
                phase = .pi * 2
            }
        }
    }
}
