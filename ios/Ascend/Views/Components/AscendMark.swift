import SwiftUI

/// The Ascend emblem — an abstract ascending diamond mark.
struct AscendMark: View {
    var size: CGFloat = 96
    var glow: Bool = true
    @State private var pulse: CGFloat = 0
    @State private var shimmer: CGFloat = -1

    var body: some View {
        ZStack {
            if glow {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Theme.accent.opacity(0.45), .clear],
                            center: .center,
                            startRadius: 2,
                            endRadius: size * 0.9
                        )
                    )
                    .frame(width: size * 1.8, height: size * 1.8)
                    .scaleEffect(1 + pulse * 0.08)
                    .opacity(0.6 + pulse * 0.2)
            }
            // Ascending diamond made of two chevrons
            ZStack {
                AscendShape()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.95),
                                Theme.accentGlow.opacity(0.8),
                                Theme.accent.opacity(0.6),
                                Color.white.opacity(0.4)
                            ],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                AscendShape()
                    .stroke(Color.white.opacity(0.7), lineWidth: 0.8)
                // shimmer sweep
                AscendShape()
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0),
                                .init(color: .white.opacity(0.7), location: 0.5),
                                .init(color: .clear, location: 1)
                            ],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .mask(AscendShape())
                    .offset(x: size * shimmer)
                    .blendMode(.plusLighter)
            }
            .frame(width: size, height: size)
            .shadow(color: Theme.accent.opacity(0.6), radius: 12)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true)) {
                pulse = 1
            }
            withAnimation(.linear(duration: 3.2).repeatForever(autoreverses: false).delay(0.4)) {
                shimmer = 1
            }
        }
    }
}

struct AscendShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        // Upward diamond
        p.move(to: CGPoint(x: w*0.5, y: h*0.08))
        p.addLine(to: CGPoint(x: w*0.92, y: h*0.50))
        p.addLine(to: CGPoint(x: w*0.5, y: h*0.92))
        p.addLine(to: CGPoint(x: w*0.08, y: h*0.50))
        p.closeSubpath()
        // Inner notch (chevron carve)
        p.move(to: CGPoint(x: w*0.5, y: h*0.30))
        p.addLine(to: CGPoint(x: w*0.72, y: h*0.50))
        p.addLine(to: CGPoint(x: w*0.5, y: h*0.70))
        p.addLine(to: CGPoint(x: w*0.28, y: h*0.50))
        p.closeSubpath()
        return p
    }
}
