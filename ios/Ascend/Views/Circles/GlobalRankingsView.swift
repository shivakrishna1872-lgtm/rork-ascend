import SwiftUI

/// Server-authoritative live Top 100 + the current user's row (always
/// visible, even if they're outside the top 100). Polls every 5 s while
/// the view is in front; backend is the source of truth.
struct GlobalRankingsView: View {
    @State private var data: GlobalRankings = .init(top: [], me: nil, total: 0)
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var lastRefresh: Date = .now
    @State private var refreshTask: Task<Void, Never>? = nil

    var body: some View {
        VStack(spacing: 14) {
            standingCard.cinematicReveal(delay: 0.04)
            list
        }
        .task { await loadOnce(); startPolling() }
        .onDisappear { refreshTask?.cancel(); refreshTask = nil }
        .refreshable { await loadOnce() }
    }

    // MARK: - Standing

    private var standingCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        AngularGradient(
                            colors: [Theme.accent.opacity(0.4), Theme.accent,
                                     .white.opacity(0.9), Theme.accent],
                            center: .center
                        )
                    )
                    .frame(width: 52, height: 52)
                    .shadow(color: Theme.accent.opacity(0.55), radius: 12)
                Text(data.me.map { "#\($0.rank)" } ?? "—")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.black.opacity(0.78))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("YOUR GLOBAL RANK")
                    .font(.system(size: 9, weight: .bold)).tracking(1.6)
                    .foregroundStyle(Theme.textTertiary)
                if let me = data.me {
                    Text("#\(me.rank) of \(data.total)")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("\(me.xp) XP · \(me.tier.capitalized)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.accentGlow)
                } else if loading && data.total == 0 {
                    Text("Loading rankings…")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    Text("Unranked")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Earn XP to enter the global leaderboard.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 4) {
                    Circle().fill(Theme.good).frame(width: 6, height: 6)
                        .shadow(color: Theme.good.opacity(0.7), radius: 3)
                    Text("LIVE")
                        .font(.system(size: 9, weight: .bold)).tracking(1.6)
                        .foregroundStyle(Theme.good)
                }
                Text(data.total > 0 ? "\(data.total) athletes" : "—")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(16)
        .glassCard(radius: 20)
    }

    // MARK: - List

    @ViewBuilder
    private var list: some View {
        if let err = loadError, data.top.isEmpty {
            errorCard(err)
        } else if data.top.isEmpty && loading {
            ForEach(0..<6, id: \.self) { idx in skeletonRow.cinematicReveal(delay: 0.08 + Double(idx) * 0.04) }
        } else if data.top.isEmpty {
            emptyCard.cinematicReveal(delay: 0.10)
        } else {
            VStack(spacing: 8) {
                SectionHeader(title: "Top 100", trailing: "Live · auto refresh")
                ForEach(Array(data.top.enumerated()), id: \.element.id) { idx, u in
                    rankRow(user: u, isMe: data.me?.id == u.id)
                        .cinematicReveal(delay: 0.08 + Double(min(idx, 12)) * 0.025)
                }
                if let me = data.me, me.rank > 100 {
                    HStack {
                        Text("· · ·")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Theme.textTertiary)
                        Spacer()
                    }
                    .padding(.vertical, 4)
                    rankRow(user: me, isMe: true)
                }
            }
        }
    }

    private func rankRow(user: RankedUser, isMe: Bool) -> some View {
        let tier = Tier(rawValue: user.tier) ?? Tier.forXP(user.xp)
        return HStack(spacing: 12) {
            ZStack {
                if user.rank <= 3 {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [medalColor(user.rank), medalColor(user.rank).opacity(0.5)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: medalColor(user.rank).opacity(0.6), radius: 6)
                    Text("\(user.rank)")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(.black.opacity(0.78))
                } else {
                    Circle().fill(Color.black.opacity(0.35))
                    Text("\(user.rank)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .frame(width: 30, height: 30)

            avatar(for: user, tier: tier)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(user.name).font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary).lineLimit(1)
                    if isMe {
                        Text("YOU").font(.system(size: 8, weight: .bold)).tracking(1.4)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(Theme.accent.opacity(0.25)))
                            .foregroundStyle(Theme.accentGlow)
                    }
                }
                HStack(spacing: 6) {
                    Text(tier.title).font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(tier.color)
                    if user.streak > 0 {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Theme.warn)
                        Text("\(user.streak)").font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }

            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(user.xp)")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                Text("XP").font(.system(size: 8, weight: .bold)).tracking(1.4)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 14)
                .fill(isMe ? Theme.accent.opacity(0.16) : Theme.surface.opacity(0.55))
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(isMe ? Theme.accent.opacity(0.6) : Theme.line,
                              lineWidth: isMe ? 1 : 0.5)
        }
    }

    private func avatar(for user: RankedUser, tier: Tier) -> some View {
        ZStack {
            Circle().fill(tier.color.opacity(0.35))
            Text(user.avatarSeed.isEmpty ? initials(user.name) : user.avatarSeed)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
        }
        .frame(width: 32, height: 32)
        .overlay(Circle().strokeBorder(tier.color.opacity(0.6), lineWidth: 1))
    }

    private func initials(_ name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        return parts.map { String($0.first ?? "?") }.joined().uppercased()
    }

    private func medalColor(_ rank: Int) -> Color {
        switch rank {
        case 1: Theme.gold
        case 2: Theme.silver
        case 3: Theme.bronze
        default: Theme.textSecondary
        }
    }

    private var skeletonRow: some View {
        HStack(spacing: 12) {
            Circle().fill(Theme.surface).frame(width: 30, height: 30)
            Circle().fill(Theme.surface).frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 4) {
                RoundedRectangle(cornerRadius: 4).fill(Theme.surface).frame(width: 120, height: 10)
                RoundedRectangle(cornerRadius: 3).fill(Theme.surface).frame(width: 60, height: 8)
            }
            Spacer()
            RoundedRectangle(cornerRadius: 4).fill(Theme.surface).frame(width: 36, height: 12)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .glassCard(radius: 14)
        .opacity(0.55)
    }

    private var emptyCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "trophy")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(Theme.accent)
            Text("Be the first").font(.aetherTitle2)
                .foregroundStyle(Theme.textPrimary)
            Text("No one has scored yet. Log an analysis to enter the global leaderboard.")
                .font(.aetherBody)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(22)
        .frame(maxWidth: .infinity)
        .glassCard(radius: 22)
    }

    private func errorCard(_ msg: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(Theme.warn)
            Text(msg).font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Button("Retry") { Task { await loadOnce() } }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.accentGlow)
        }
        .padding(14)
        .glassCard(radius: 14)
    }

    // MARK: - Data

    private func loadOnce() async {
        do {
            let r = try await BackendService.shared.fetchGlobalRankings()
            withAnimation(.smooth(duration: 0.35)) {
                data = r
                loadError = nil
            }
            lastRefresh = .now
        } catch {
            loadError = "Couldn't reach rankings."
        }
        loading = false
    }

    private func startPolling() {
        refreshTask?.cancel()
        refreshTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                if Task.isCancelled { break }
                await loadOnce()
            }
        }
    }
}

// Re-using the cinematicReveal modifier already defined in the project for
// consistent entrance animations.
