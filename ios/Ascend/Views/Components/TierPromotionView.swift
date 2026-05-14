import SwiftUI

struct TierPromotionView: View {
    let from: Tier
    let to: Tier
    let onDismiss: () -> Void

    @State private var step: Int = 0
    @State private var emblemScale: CGFloat = 0.3
    @State private var rotation: Double = 0

    var body: some View {
        ZStack {
            // Dimming layer
            Color.black.opacity(0.85)
                .ignoresSafeArea()
                .background(.ultraThinMaterial)

            // Radial light
            RadialGradient(
                colors: [to.color.opacity(0.35), .clear],
                center: .center, startRadius: 10, endRadius: 420
            )
            .ignoresSafeArea()
            .blendMode(.plusLighter)
            .opacity(step >= 1 ? 1 : 0)

            VStack(spacing: 28) {
                if step >= 1 {
                    Text("Promotion".uppercased())
                        .font(.system(size: 11, weight: .semibold)).tracking(4)
                        .foregroundStyle(Theme.textSecondary)
                        .transition(.opacity)
                }

                ZStack {
                    if step >= 2 {
                        ForEach(0..<3) { i in
                            Circle()
                                .strokeBorder(to.color.opacity(0.7 - Double(i) * 0.2), lineWidth: 1)
                                .frame(width: 160 + CGFloat(i) * 50, height: 160 + CGFloat(i) * 50)
                                .scaleEffect(emblemScale)
                                .opacity(emblemScale > 0.4 ? 1 : 0)
                        }
                    }
                    if step >= 2 {
                        TierEmblem(tier: to, size: 140)
                            .scaleEffect(emblemScale)
                            .rotation3DEffect(.degrees(rotation), axis: (x: 0, y: 1, z: 0))
                            .shadow(color: to.color.opacity(0.8), radius: 30)
                    }
                }

                if step >= 3 {
                    VStack(spacing: 8) {
                        Text(to.title.uppercased())
                            .font(.system(size: 36, weight: .semibold)).tracking(6)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.white, to.color, .white.opacity(0.7)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                )
                            )
                            .shadow(color: to.color.opacity(0.7), radius: 10)
                        Text(to.subtitle)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .transition(.opacity.combined(with: .blurReplace))
                }

                if step >= 4 {
                    Text("From \(from.title) — discipline shows.".uppercased())
                        .font(.system(size: 10, weight: .semibold)).tracking(1.8)
                        .foregroundStyle(Theme.textTertiary)
                        .transition(.opacity)
                }

                if step >= 4 {
                    Button {
                        Haptics.medium()
                        onDismiss()
                    } label: {
                        Text("Continue")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.bg)
                            .frame(width: 200, height: 50)
                            .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.95)))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 6)
                    .transition(.opacity)
                }
            }
        }
        .onAppear { runSequence() }
    }

    private func runSequence() {
        // Step 1: darken (0.0)
        withAnimation(.smooth(duration: 0.4)) { step = 1 }
        Haptics.soft()

        // Step 2: emblem forms (0.4)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            withAnimation(.spring(duration: 1.2)) {
                step = 2
                emblemScale = 1.0
            }
            withAnimation(.linear(duration: 6).repeatForever(autoreverses: false)) {
                rotation = 360
            }
            Haptics.medium()
        }

        // Step 3: title reveal (1.5)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.smooth(duration: 0.6)) { step = 3 }
            Haptics.success()
        }

        // Step 4: subtitle + button (2.4)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
            withAnimation(.smooth(duration: 0.5)) { step = 4 }
        }
    }
}
