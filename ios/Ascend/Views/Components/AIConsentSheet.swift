import SwiftUI

/// One‑time consent popup shown before any data is sent to the third‑party
/// AI provider. Two buttons only: **Allow** and **Not Now** (per App Review
/// Guidelines 5.1.1(i) and 5.1.2(i)).
struct AIConsentSheet: View {
    let onAllow: () -> Void
    let onNotNow: () -> Void

    var body: some View {
        ZStack {
            AmbientBackground().ignoresSafeArea()
            ScrollView {
                VStack(spacing: 22) {
                    icon
                    titleBlock
                    bullets
                    Spacer(minLength: 8)
                    buttons
                    footer
                }
                .padding(.horizontal, 22)
                .padding(.top, 28)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
        }
        .interactiveDismissDisabled(true)
    }

    private var icon: some View {
        ZStack {
            Circle().fill(Theme.accent.opacity(0.14)).frame(width: 96, height: 96)
                .ambientFloat(amplitude: 4, duration: 3.4)
            Image(systemName: "sparkles")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(Theme.accent)
        }
        .padding(.top, 4)
    }

    private var titleBlock: some View {
        VStack(spacing: 8) {
            Text("Use AI Analysis?")
                .font(.aetherTitle)
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
            Text("Ascend uses a third‑party AI provider to analyze your photos and text so it can score your physique, face harmony, and meals.")
                .font(.system(size: 14))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var bullets: some View {
        VStack(alignment: .leading, spacing: 12) {
            bullet(icon: "paperplane.fill",
                   title: "What gets sent",
                   detail: "The photos and short text you submit during a scan or meal log are sent to the AI provider (OpenAI / Google) over a secure connection.")
            bullet(icon: "checkmark.shield.fill",
                   title: "Used only for app features",
                   detail: "Your content is processed solely to return your score and recommendations. It is not used for ads, tracking, or marketing.")
            bullet(icon: "hand.raised.fill",
                   title: "You stay in control",
                   detail: "You can change your mind anytime in Profile → Privacy. Without consent, AI scoring is skipped.")
        }
        .padding(16)
        .glassCard(radius: 18)
    }

    private func bullet(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(Theme.accent.opacity(0.16))
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.accent)
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private var buttons: some View {
        VStack(spacing: 10) {
            Button {
                Haptics.success()
                onAllow()
            } label: {
                Text("Allow")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.bg)
                    .frame(maxWidth: .infinity).frame(height: 52)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(LinearGradient(colors: [.white.opacity(0.96), Theme.accentGlow.opacity(0.9)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                    )
                    .shadow(color: Theme.accent.opacity(0.35), radius: 18, y: 6)
            }
            .buttonStyle(.plain)

            Button {
                Haptics.tap()
                onNotNow()
            } label: {
                Text("Not Now")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(maxWidth: .infinity).frame(height: 48)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface.opacity(0.6)))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.lineStrong, lineWidth: 0.6))
            }
            .buttonStyle(.plain)
        }
    }

    private var footer: some View {
        Text("Your content is never used for advertising or sold. You can revoke consent at any time in Profile → Privacy.")
            .font(.system(size: 11))
            .foregroundStyle(Theme.textTertiary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 4)
    }
}
