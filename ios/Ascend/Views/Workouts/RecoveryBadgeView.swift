import SwiftUI

/// Small status pill that surfaces today's HealthKit-derived recovery score.
/// Tap to open a sheet with the breakdown + a refresh button.
struct RecoveryBadgeView: View {
    @State private var service = RecoveryService.shared
    @State private var showDetail: Bool = false
    @State private var refreshing: Bool = false

    var body: some View {
        Button {
            Haptics.tap()
            showDetail = true
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(tint.opacity(0.18))
                    Circle()
                        .trim(from: 0, to: CGFloat(service.latest.score) / 100)
                        .stroke(tint, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(service.latest.score)")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                        .monospacedDigit()
                }
                .frame(width: 42, height: 42)
                VStack(alignment: .leading, spacing: 2) {
                    Text("RECOVERY")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.6)
                        .foregroundStyle(Theme.textTertiary)
                    Text(service.latest.label)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                }
                Spacer(minLength: 0)
                Image(systemName: service.status == .ok ? "chevron.right" : "plus.circle.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(service.status == .ok ? Theme.textTertiary : Theme.accentGlow)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface.opacity(0.55)))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.lineStrong, lineWidth: 0.6))
        }
        .buttonStyle(.plain)
        .task {
            if service.status == .unavailable {
                await service.requestAccess()
            } else if service.status == .ok {
                await service.refresh()
            }
        }
        .sheet(isPresented: $showDetail) {
            detailSheet
        }
    }

    private var tint: Color {
        switch service.latest.score {
        case 75...: return Theme.accentGlow
        case 50..<75: return Theme.gold
        default: return .orange
        }
    }

    private var detailSheet: some View {
        NavigationStack {
            ZStack {
                AmbientBackground(intensity: 0.45).ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        scoreRing
                        Text(service.latest.recommendation)
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 8)
                        signalsGrid
                        if service.status != .ok {
                            connectButton
                        } else {
                            refreshButton
                        }
                        disclaimer
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 6)
                    .padding(.bottom, 32)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Recovery")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var scoreRing: some View {
        ZStack {
            Circle().strokeBorder(Theme.line, lineWidth: 8)
            Circle()
                .trim(from: 0, to: CGFloat(service.latest.score) / 100)
                .stroke(tint, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.6, dampingFraction: 0.85), value: service.latest.score)
            VStack(spacing: 2) {
                Text("\(service.latest.score)")
                    .font(.system(size: 44, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                Text(service.latest.label)
                    .font(.system(size: 11, weight: .heavy)).tracking(1.4)
                    .foregroundStyle(tint)
            }
        }
        .frame(width: 160, height: 160)
        .padding(.top, 6)
    }

    private var signalsGrid: some View {
        let r = service.latest
        return VStack(spacing: 10) {
            signalRow("HRV", value: r.hrvMs.map { String(format: "%.0f ms", $0) } ?? "—",
                      icon: "waveform.path.ecg")
            signalRow("Sleep last night", value: r.sleepHours.map { String(format: "%.1fh", $0) } ?? "—",
                      icon: "moon.stars.fill")
            signalRow("Resting HR", value: r.restingHR.map { "\($0) bpm" } ?? "—",
                      icon: "heart.fill")
        }
    }

    private func signalRow(_ title: String, value: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.accentGlow)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Theme.accentGlow.opacity(0.15)))
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .monospacedDigit()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface.opacity(0.5)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.line, lineWidth: 0.5))
    }

    private var connectButton: some View {
        Button {
            Haptics.medium()
            Task { await service.requestAccess() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "heart.text.square.fill")
                Text("Connect Apple Health")
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Theme.bg)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(RoundedRectangle(cornerRadius: 14).fill(Theme.accentGlow))
        }
        .buttonStyle(.plain)
    }

    private var refreshButton: some View {
        Button {
            Haptics.tap()
            refreshing = true
            Task {
                await service.refresh()
                refreshing = false
            }
        } label: {
            HStack(spacing: 8) {
                if refreshing { ProgressView().tint(Theme.textPrimary) }
                else { Image(systemName: "arrow.clockwise") }
                Text(refreshing ? "Refreshing…" : "Refresh")
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Theme.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface.opacity(0.6)))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.lineStrong, lineWidth: 0.6))
        }
        .buttonStyle(.plain)
        .disabled(refreshing)
    }

    private var disclaimer: some View {
        Text("Deterministic score from HRV, sleep, and resting HR. Not medical advice.")
            .font(.system(size: 11))
            .foregroundStyle(Theme.textTertiary)
            .multilineTextAlignment(.center)
            .padding(.top, 4)
    }
}
