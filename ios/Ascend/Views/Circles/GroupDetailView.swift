import SwiftUI

/// Backend-backed detail screen for a single circle. Polls every 4s while
/// visible so rank changes from other members show up live.
struct GroupDetailView: View {
    let circleId: String
    let user: UserProfile

    @Environment(\.dismiss) private var dismiss
    @State private var circle: RemoteCircle? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var refreshTask: Task<Void, Never>? = nil
    @State private var codeCopied = false
    @State private var showLeaveConfirm = false
    @State private var showDeleteConfirm = false

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                if let c = circle {
                    header(for: c).cinematicReveal(delay: 0.02)
                    inviteBlock(for: c).cinematicReveal(delay: 0.08)
                    leaderboard(for: c).cinematicReveal(delay: 0.16)
                    dangerZone(for: c).cinematicReveal(delay: 0.24)
                    Color.clear.frame(height: 40)
                } else if loading {
                    ProgressView().tint(Theme.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 220)
                } else if let err = loadError {
                    VStack(spacing: 10) {
                        Image(systemName: "wifi.exclamationmark")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(Theme.warn)
                        Text(err).font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .multilineTextAlignment(.center)
                        GhostButton(title: "Retry", icon: "arrow.clockwise") {
                            Task { await load() }
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity)
                    .glassCard(radius: 18)
                }
            }
            .padding(.horizontal, 20).padding(.top, 12)
        }
        .scrollIndicators(.hidden)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let c = circle {
                    ShareLink(item: inviteURL(for: c.code),
                              message: Text("Join my Ascend circle \"\(c.name)\" with code \(c.code)")) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .simultaneousGesture(TapGesture().onEnded { Haptics.tap() })
                }
            }
        }
        .task { await load(); startPolling() }
        .refreshable { await load() }
        .onDisappear { refreshTask?.cancel(); refreshTask = nil }
    }

    // MARK: - Sections

    private func header(for c: RemoteCircle) -> some View {
        let accent = (GroupAccent(rawValue: c.accent) ?? .steel).color
        return VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        AngularGradient(
                            colors: [accent.opacity(0.4), accent, .white.opacity(0.9), accent],
                            center: .center
                        )
                    )
                    .frame(width: 72, height: 72)
                    .shadow(color: accent.opacity(0.5), radius: 18)
                Text(c.name.prefix(1).uppercased())
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.black.opacity(0.75))
            }
            Text(c.name)
                .font(.aetherTitle)
                .foregroundStyle(Theme.textPrimary)
            HStack(spacing: 6) {
                Circle().fill(Theme.good).frame(width: 6, height: 6)
                    .shadow(color: Theme.good.opacity(0.7), radius: 3)
                Text("LIVE · \(c.memberCount) member\(c.memberCount == 1 ? "" : "s")")
                    .font(.system(size: 11, weight: .bold)).tracking(1.5)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
    }

    private func inviteBlock(for c: RemoteCircle) -> some View {
        VStack(spacing: 14) {
            Text("INVITE CODE")
                .font(.system(size: 10, weight: .bold)).tracking(1.8)
                .foregroundStyle(Theme.textTertiary)

            Button {
                UIPasteboard.general.string = c.code
                Haptics.success()
                withAnimation(.snappy) { codeCopied = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                    withAnimation { codeCopied = false }
                }
            } label: {
                HStack(spacing: 12) {
                    Text(c.code)
                        .font(.system(size: 36, weight: .bold, design: .monospaced))
                        .tracking(8)
                        .foregroundStyle(Theme.textPrimary)
                    Image(systemName: codeCopied ? "checkmark.circle.fill" : "doc.on.doc.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(codeCopied ? Theme.good : Theme.textTertiary)
                        .contentTransition(.symbolEffect(.replace))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(RoundedRectangle(cornerRadius: 18).fill(Color.black.opacity(0.3)))
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Theme.lineStrong, lineWidth: 0.8))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Invite code \(c.code). Tap to copy.")

            HStack(spacing: 10) {
                ShareLink(item: inviteURL(for: c.code),
                          message: Text("Join my Ascend circle \"\(c.name)\" with code \(c.code)")) {
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                        Text("Share invite")
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.bg)
                    .frame(maxWidth: .infinity).frame(height: 50)
                    .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.95)))
                }
                .simultaneousGesture(TapGesture().onEnded { Haptics.medium() })

                Button {
                    UIPasteboard.general.string = c.code
                    Haptics.success()
                    withAnimation(.snappy) { codeCopied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                        withAnimation { codeCopied = false }
                    }
                } label: {
                    HStack {
                        Image(systemName: "doc.on.doc")
                        Text("Copy")
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(maxWidth: .infinity).frame(height: 50)
                    .glassCard(radius: 14)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .glassCard(radius: 22)
    }

    private func leaderboard(for c: RemoteCircle) -> some View {
        VStack(spacing: 10) {
            SectionHeader(title: "Private Leaderboard", trailing: "Live")
                .padding(.horizontal, 2)
            ForEach(c.members) { m in
                rankRow(member: m, accent: (GroupAccent(rawValue: c.accent) ?? .steel).color)
            }
        }
    }

    private func rankRow(member: RankedUser, accent: Color) -> some View {
        let tier = Tier(rawValue: member.tier) ?? Tier.forXP(member.xp)
        return HStack(spacing: 14) {
            Text("#\(member.rank)")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(member.rank <= 3 ? tier.color : Theme.textTertiary)
                .frame(width: 36, alignment: .leading)
            TierEmblem(tier: tier, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(member.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    if member.isMe ?? false {
                        Text("YOU").font(.system(size: 8, weight: .bold)).tracking(1.4)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(accent.opacity(0.3)))
                            .foregroundStyle(Theme.textPrimary)
                    }
                }
                HStack(spacing: 6) {
                    Text(tier.title).font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(tier.color)
                    if member.streak > 0 {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Theme.warn)
                        Text("\(member.streak)").font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(member.xp)")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                Text("XP").font(.system(size: 8, weight: .bold)).tracking(1.4)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 14)
                .fill((member.isMe ?? false) ? accent.opacity(0.14) : Theme.surface.opacity(0.5))
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder((member.isMe ?? false) ? accent.opacity(0.55) : Theme.line,
                              lineWidth: (member.isMe ?? false) ? 1 : 0.5)
        }
    }

    @ViewBuilder
    private func dangerZone(for c: RemoteCircle) -> some View {
        VStack(spacing: 10) {
            if c.isOwner {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    HStack { Image(systemName: "trash"); Text("Delete circle") }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.bad)
                        .frame(maxWidth: .infinity).frame(height: 46)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.bad.opacity(0.12)))
                }
                .buttonStyle(.plain)
            } else {
                Button(role: .destructive) {
                    showLeaveConfirm = true
                } label: {
                    HStack { Image(systemName: "rectangle.portrait.and.arrow.right"); Text("Leave circle") }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.bad)
                        .frame(maxWidth: .infinity).frame(height: 46)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.bad.opacity(0.12)))
                }
                .buttonStyle(.plain)
            }
        }
        .confirmationDialog("Leave this circle?", isPresented: $showLeaveConfirm, titleVisibility: .visible) {
            Button("Leave", role: .destructive) {
                Task {
                    try? await BackendService.shared.leaveCircle(id: c.id)
                    Haptics.medium(); dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete this circle for everyone?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Task {
                    try? await BackendService.shared.deleteCircle(id: c.id)
                    Haptics.medium(); dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Data

    private func load() async {
        do {
            let c = try await BackendService.shared.fetchCircle(id: circleId)
            withAnimation(.smooth(duration: 0.3)) { circle = c; loadError = nil }
        } catch {
            loadError = (error as? BackendError)?.errorDescription
                ?? "Couldn't load this circle."
        }
        loading = false
    }

    private func startPolling() {
        refreshTask?.cancel()
        refreshTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                if Task.isCancelled { break }
                await load()
            }
        }
    }

    private func inviteURL(for code: String) -> URL {
        let base = Config.EXPO_PUBLIC_RORK_FUNCTIONS_URL
            .trimmingCharacters(in: .init(charactersIn: "/"))
        return URL(string: "\(base)/join/\(code)") ?? URL(string: "https://ascend.app/join/\(code)")!
    }
}
