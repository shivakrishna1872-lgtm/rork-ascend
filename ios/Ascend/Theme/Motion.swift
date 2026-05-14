import SwiftUI

/// Cinematic but snappy motion presets.
enum Motion {
    /// Primary entrance — quick, weighty.
    static let entrance = Animation.spring(response: 0.42, dampingFraction: 0.86)
    /// Secondary content arrival.
    static let secondary = Animation.spring(response: 0.36, dampingFraction: 0.88)
    /// UI feedback (taps, toggles).
    static let snappy = Animation.spring(response: 0.28, dampingFraction: 0.78)
    /// Cross-tab swap.
    static let tab = Animation.spring(response: 0.32, dampingFraction: 0.88)
    /// Number/score morph.
    static let numberMorph = Animation.spring(response: 0.7, dampingFraction: 0.86)
    /// Ring stroke draw-in.
    static let ringDraw = Animation.spring(response: 0.9, dampingFraction: 0.85)
    /// Ambient breathing loop.
    static let ambient = Animation.easeInOut(duration: 5.2).repeatForever(autoreverses: true)
}

// MARK: - Parallax modifier driven by scroll offset

struct ParallaxOffset: ViewModifier {
    var offsetY: CGFloat
    var amount: CGFloat = 0.35
    var blurMax: CGFloat = 0
    func body(content: Content) -> some View {
        let progress = min(1, max(0, -offsetY / 240))
        return content
            .offset(y: offsetY * amount)
            .scaleEffect(1 - progress * 0.04, anchor: .top)
            .blur(radius: blurMax * progress)
    }
}

extension View {
    func parallax(_ offsetY: CGFloat, amount: CGFloat = 0.35, blurMax: CGFloat = 0) -> some View {
        modifier(ParallaxOffset(offsetY: offsetY, amount: amount, blurMax: blurMax))
    }
}

// MARK: - Scroll offset reader

struct ScrollOffsetReader: View {
    let onChange: (CGFloat) -> Void
    var body: some View {
        GeometryReader { geo in
            Color.clear
                .preference(key: ScrollOffsetKey.self, value: geo.frame(in: .named("aether.scroll")).minY)
        }
        .frame(height: 0)
        .onPreferenceChange(ScrollOffsetKey.self) { v in
            onChange(v)
        }
    }
}

struct ScrollOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Cinematic reveal — quick spring slide, optional reduce-motion bypass

struct CinematicReveal: ViewModifier {
    let delay: Double
    let yOffset: CGFloat
    let blur: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var on = false

    func body(content: Content) -> some View {
        content
            .opacity(on ? 1 : 0)
            .blur(radius: on ? 0 : blur)
            .offset(y: on ? 0 : yOffset)
            .onAppear {
                let anim: Animation = reduceMotion
                    ? .easeOut(duration: 0.2)
                    : .spring(response: 0.42, dampingFraction: 0.86).delay(delay)
                withAnimation(anim) { on = true }
            }
    }
}

extension View {
    /// Quick, weighty entrance with optional drift and blur.
    func cinematicReveal(delay: Double = 0, yOffset: CGFloat = 14, blur: CGFloat = 6) -> some View {
        modifier(CinematicReveal(delay: delay, yOffset: yOffset, blur: blur))
    }
}

// MARK: - Depth shimmer for tier emblems / cards

struct DepthShimmer: ViewModifier {
    @State private var phase: CGFloat = -1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content.overlay {
            GeometryReader { geo in
                LinearGradient(
                    colors: [
                        .clear,
                        .white.opacity(0.18),
                        .clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .rotationEffect(.degrees(20))
                .offset(x: phase * geo.size.width * 1.4)
                .blendMode(.plusLighter)
                .allowsHitTesting(false)
            }
            .clipped()
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 4.4).repeatForever(autoreverses: false)) {
                phase = 1.2
            }
        }
    }
}

extension View {
    func depthShimmer() -> some View { modifier(DepthShimmer()) }
}

// MARK: - Bottom inset for floating tab bar

extension View {
    /// Reserves space at the bottom of a ScrollView for the floating tab bar.
    func tabBarBottomInset() -> some View {
        self.safeAreaPadding(.bottom, 96)
    }
}
