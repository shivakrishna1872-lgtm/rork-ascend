import SwiftUI

// MARK: - Counting number

struct CountingNumber: View, Animatable {
    var value: Double
    var format: (Double) -> String = { String(Int($0.rounded())) }
    var font: Font = .aetherNumber
    var color: Color = Theme.textPrimary

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text(format(value))
            .font(font)
            .foregroundStyle(color)
            .contentTransition(.numericText(value: value))
            .monospacedDigit()
    }
}

// MARK: - Radial score

struct RadialScore: View {
    var score: Double      // 0..100
    var label: String
    var size: CGFloat = 160
    var color: Color = Theme.accent
    @State private var animated: Double = 0

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.line, style: .init(lineWidth: 10))

            Circle()
                .trim(from: 0, to: animated / 100)
                .stroke(
                    AngularGradient(
                        colors: [color.opacity(0.4), color, Theme.accentGlow, color.opacity(0.7)],
                        center: .center
                    ),
                    style: .init(lineWidth: 10, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: color.opacity(0.45), radius: 14)

            VStack(spacing: 2) {
                CountingNumber(value: animated, font: .system(size: size * 0.32, weight: .semibold, design: .rounded))
                Text(label.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(2)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.84)) { animated = score }
        }
        .onChange(of: score) { _, new in
            withAnimation(.spring(response: 0.55, dampingFraction: 0.86)) { animated = new }
        }
    }
}

// MARK: - Thin ring

struct ThinRing: View {
    var progress: Double   // 0..1
    var color: Color = Theme.accent
    var lineWidth: CGFloat = 6
    @State private var animated: Double = 0

    var body: some View {
        ZStack {
            Circle().stroke(Theme.line, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: animated)
                .stroke(color, style: .init(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: color.opacity(0.6), radius: 6)
        }
        .onAppear { withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) { animated = progress } }
        .onChange(of: progress) { _, new in
            withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) { animated = new }
        }
    }
}

// MARK: - Metric chip

struct MetricChip: View {
    let label: String
    let value: String
    let icon: String
    var tint: Color = Theme.accent
    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(tint.opacity(0.15))
                Image(systemName: icon).font(.system(size: 13, weight: .semibold)).foregroundStyle(tint)
            }
            .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(label.uppercased())
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1.5)
                    .foregroundStyle(Theme.textTertiary)
                Text(value)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .glassCard(radius: 14)
    }
}

// MARK: - Section header

struct SectionHeader: View {
    let title: String
    var trailing: String? = nil
    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(2)
                .foregroundStyle(Theme.textTertiary)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.aetherCaption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }
}

// MARK: - Primary button

struct PrimaryButton: View {
    let title: String
    var icon: String? = nil
    var loading: Bool = false
    var action: () -> Void
    @State private var pressed = false

    var body: some View {
        Button {
            Haptics.medium()
            action()
        } label: {
            HStack(spacing: 8) {
                if loading {
                    ProgressView().tint(Theme.bg).scaleEffect(0.85)
                } else if let icon {
                    Image(systemName: icon).font(.system(size: 15, weight: .bold))
                }
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(Theme.bg)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(LinearGradient(
                            colors: [Color.white.opacity(0.96), Color(white: 0.85)],
                            startPoint: .top, endPoint: .bottom
                        ))
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(LinearGradient(
                            colors: [Color.white.opacity(0.6), .clear],
                            startPoint: .top, endPoint: .center
                        ))
                        .blendMode(.plusLighter)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.5), lineWidth: 0.5)
            )
            .scaleEffect(pressed ? 0.97 : 1)
        }
        .buttonStyle(.plain)
        .disabled(loading)
        .simultaneousGesture(DragGesture(minimumDistance: 0)
            .onChanged { _ in withAnimation(.spring(duration: 0.2)) { pressed = true } }
            .onEnded { _ in withAnimation(.spring(duration: 0.3)) { pressed = false } }
        )
    }
}

struct GhostButton: View {
    let title: String
    var icon: String? = nil
    var action: () -> Void
    var body: some View {
        Button {
            Haptics.tap(); action()
        } label: {
            HStack(spacing: 8) {
                if let icon { Image(systemName: icon).font(.system(size: 14, weight: .semibold)) }
                Text(title).font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(Theme.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .glassCard(radius: 14)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Tier emblem

struct TierEmblem: View {
    let tier: Tier
    var size: CGFloat = 44
    @State private var rotation: Double = 0
    var body: some View {
        ZStack {
            Circle()
                .fill(
                    AngularGradient(
                        colors: [
                            tier.color.opacity(0.4),
                            tier.color,
                            .white.opacity(0.9),
                            tier.color.opacity(0.5),
                            tier.color
                        ],
                        center: .center,
                        angle: .degrees(rotation)
                    )
                )
                .overlay(Circle().strokeBorder(.white.opacity(0.3), lineWidth: 0.6))
                .shadow(color: tier.color.opacity(0.7), radius: 10)
            // Inner glyph
            Image(systemName: glyph)
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(.black.opacity(0.75))
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(.linear(duration: 14).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        }
    }

    private var glyph: String {
        switch tier {
        case .bronze: "triangle.fill"
        case .silver: "diamond.fill"
        case .gold:   "star.fill"
        case .elite:  "hexagon.fill"
        case .greek:  "laurel.leading"
        }
    }
}

// MARK: - Blur fade-in (cinematic, reduce-motion aware)

struct BlurFadeIn: ViewModifier {
    let delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var on = false
    func body(content: Content) -> some View {
        content
            .opacity(on ? 1 : 0)
            .blur(radius: on ? 0 : 6)
            .offset(y: on ? 0 : 14)
            .onAppear {
                let anim: Animation = reduceMotion
                    ? .easeOut(duration: 0.2)
                    : .spring(response: 0.42, dampingFraction: 0.86).delay(delay)
                withAnimation(anim) { on = true }
            }
    }
}

extension View {
    func blurFadeIn(delay: Double = 0) -> some View { modifier(BlurFadeIn(delay: delay)) }
}

// MARK: - Floating ambient motion

struct AmbientFloat: ViewModifier {
    @State private var y: CGFloat = 0
    let amplitude: CGFloat
    let duration: Double
    func body(content: Content) -> some View {
        content.offset(y: y)
            .onAppear {
                withAnimation(.easeInOut(duration: duration).repeatForever(autoreverses: true)) {
                    y = amplitude
                }
            }
    }
}

extension View {
    func ambientFloat(amplitude: CGFloat = 4, duration: Double = 3.4) -> some View {
        modifier(AmbientFloat(amplitude: amplitude, duration: duration))
    }
}
