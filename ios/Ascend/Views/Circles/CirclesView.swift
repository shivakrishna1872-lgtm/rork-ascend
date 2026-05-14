import SwiftUI
import SwiftData

struct CirclesView: View {
    let user: UserProfile
    @Environment(\.modelContext) private var ctx
    @Query(sort: \FriendGroup.createdAt, order: .reverse) private var groups: [FriendGroup]

    @State private var mode: Mode = .circles
    @State private var globalMetric: GlobalMetric = .physique
    @State private var showCreate = false
    @State private var showJoin = false
    @State private var newName = ""
    @State private var newAccent: GroupAccent = .steel
    @State private var joinCode = ""
    @State private var joinError: String?
    @State private var path = NavigationPath()
    @Query(sort: \PhysiqueScanRecord.date, order: .reverse) private var scans: [PhysiqueScanRecord]
    @Query(sort: \FaceScanRecord.date, order: .reverse) private var faces: [FaceScanRecord]

    enum GlobalMetric: String, CaseIterable, Identifiable {
        case physique = "Physique"
        case psl = "PSL"
        var id: String { rawValue }
    }

    enum Mode: String, CaseIterable, Identifiable {
        case circles = "Circles"
        case global = "Global"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 18) {
                    header.cinematicReveal(delay: 0)
                    segmented.cinematicReveal(delay: 0.06)

                    if mode == .circles {
                        circlesContent
                    } else {
                        globalContent
                    }

                }
                .padding(.horizontal, 20).padding(.top, 12)
            }
            .scrollIndicators(.hidden)
            .tabBarBottomInset()
            .navigationDestination(for: FriendGroup.ID.self) { id in
                if let g = groups.first(where: { $0.id == id }) {
                    GroupDetailView(group: g, user: user)
                }
            }
            .sheet(isPresented: $showCreate) { createSheet }
            .sheet(isPresented: $showJoin) { joinSheet }
        }
        .tint(Theme.accent)
    }

    // MARK: - Header & segmented

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Progression".uppercased())
                    .font(.system(size: 11, weight: .semibold)).tracking(2)
                    .foregroundStyle(Theme.textTertiary)
                Text("Your Circles")
                    .font(.aetherTitle).foregroundStyle(Theme.textPrimary)
            }
            Spacer()
            HStack(spacing: 8) {
                circleIconButton(icon: "qrcode.viewfinder") {
                    showJoin = true
                }
                circleIconButton(icon: "plus") {
                    newName = ""; newAccent = .steel; showCreate = true
                }
            }
        }
    }

    private func circleIconButton(icon: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap(); action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 42, height: 42)
                .glassCard(radius: 12)
        }
        .buttonStyle(.plain)
    }

    private var segmented: some View {
        HStack(spacing: 6) {
            ForEach(Mode.allCases) { m in
                Button {
                    Haptics.tap()
                    withAnimation(Motion.snappy) { mode = m }
                } label: {
                    Text(m.rawValue)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(mode == m ? Theme.bg : Theme.textPrimary)
                        .frame(maxWidth: .infinity).frame(height: 40)
                        .background {
                            if mode == m {
                                RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.9))
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .glassCard(radius: 14)
    }

    // MARK: - Circles tab content

    @ViewBuilder
    private var circlesContent: some View {
        let pendingCount = groups.flatMap(\.members).filter { $0.isPending }.count

        if pendingCount > 0 {
            HStack(spacing: 10) {
                Image(systemName: "envelope.badge.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.warn)
                Text("\(pendingCount) pending invite\(pendingCount == 1 ? "" : "s")")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .glassCard(radius: 14)
            .cinematicReveal(delay: 0.12)
        }

        if groups.isEmpty {
            emptyState.cinematicReveal(delay: 0.12)
        } else {
            ForEach(Array(groups.enumerated()), id: \.element.id) { idx, g in
                groupCard(g).cinematicReveal(delay: 0.12 + Double(idx) * 0.05)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "person.2.crop.square.stack")
                .font(.system(size: 38, weight: .bold))
                .foregroundStyle(Theme.accent)
                .ambientFloat(amplitude: 3, duration: 3.4)
            Text("Build your first circle")
                .font(.aetherTitle2)
                .foregroundStyle(Theme.textPrimary)
            Text("Invite a friend or two. Discipline compounds when you compete with people you respect.")
                .font(.aetherBody)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)

            VStack(spacing: 10) {
                PrimaryButton(title: "Create a circle", icon: "plus") {
                    newName = ""; newAccent = .steel; showCreate = true
                }
                GhostButton(title: "Join with code", icon: "arrow.right.circle") {
                    joinCode = ""; joinError = nil; showJoin = true
                }
            }
            .padding(.top, 4)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .glassCard(radius: 26)
    }

    private func groupCard(_ g: FriendGroup) -> some View {
        Button {
            Haptics.tap()
            path.append(g.id)
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("CIRCLE").font(.system(size: 9, weight: .bold)).tracking(2)
                            .foregroundStyle(Theme.textTertiary)
                        Text(g.name).font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                    }
                    Spacer()
                    avatarFan(for: g)
                }

                let ranked = g.rankedMembers(currentUserXP: user.xp, currentUserName: user.name)
                let myRank = (ranked.firstIndex(where: { $0.isMe }) ?? 0) + 1
                HStack(spacing: 12) {
                    statChip(label: "Members", value: "\(ranked.count)")
                    statChip(label: "Your rank", value: "#\(myRank)")
                    statChip(label: "Code", value: g.inviteCode)
                }
            }
            .padding(18)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Theme.surface.opacity(0.55))
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(.ultraThinMaterial).opacity(0.35)
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [g.accent.color.opacity(0.22), .clear],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(g.accent.color.opacity(0.35), lineWidth: 0.8)
            )
            .clipShape(.rect(cornerRadius: 22))
        }
        .buttonStyle(.plain)
    }

    private func statChip(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 8, weight: .bold)).tracking(1.4)
                .foregroundStyle(Theme.textTertiary)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.25)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.line, lineWidth: 0.5))
    }

    private func avatarFan(for g: FriendGroup) -> some View {
        let actives = g.members.filter { !$0.isPending }.prefix(3)
        return HStack(spacing: -10) {
            ForEach(Array(actives.enumerated()), id: \.element.id) { _, m in
                ZStack {
                    Circle().fill(g.accent.color.opacity(0.3))
                    Text(m.initials).font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                }
                .frame(width: 30, height: 30)
                .overlay(Circle().strokeBorder(Theme.bg, lineWidth: 2))
            }
            ZStack {
                Circle().fill(g.accent.color)
                Image(systemName: "person.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.black.opacity(0.7))
            }
            .frame(width: 30, height: 30)
            .overlay(Circle().strokeBorder(Theme.bg, lineWidth: 2))
        }
    }

    // MARK: - Global tab content (tier distribution + your standing)

    @ViewBuilder
    private var globalContent: some View {
        metricSegmented.cinematicReveal(delay: 0.10)
        if globalMetric == .physique {
            physiqueStanding.cinematicReveal(delay: 0.16)
            physiqueDistribution.cinematicReveal(delay: 0.22)
            physiqueTierLadder.cinematicReveal(delay: 0.28)
        } else {
            pslStanding.cinematicReveal(delay: 0.16)
            pslDistribution.cinematicReveal(delay: 0.22)
            pslTierLadder.cinematicReveal(delay: 0.28)
        }
    }

    private var metricSegmented: some View {
        HStack(spacing: 6) {
            ForEach(GlobalMetric.allCases) { m in
                Button {
                    Haptics.tap()
                    withAnimation(Motion.snappy) { globalMetric = m }
                } label: {
                    Text(m.rawValue.uppercased())
                        .font(.system(size: 11, weight: .bold)).tracking(1.6)
                        .foregroundStyle(globalMetric == m ? Theme.bg : Theme.textPrimary)
                        .frame(maxWidth: .infinity).frame(height: 36)
                        .background {
                            if globalMetric == m {
                                RoundedRectangle(cornerRadius: 9).fill(.white.opacity(0.9))
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .glassCard(radius: 12)
    }

    private var physiqueScore: Double { scans.first?.physiqueScore ?? 0 }
    private var pslScore: Double { faces.first?.overallScore ?? 0 }
    private var physiqueTier: Tier { Tier.forScore(physiqueScore) }
    private var pslTier: Tier { Tier.forScore(pslScore) }

    private var physiqueStanding: some View {
        scoreStandingCard(
            label: "PHYSIQUE",
            hasData: !scans.isEmpty,
            score: physiqueScore,
            tier: physiqueTier,
            subtitle: scans.first?.archetypeRaw ?? "No scans yet",
            icon: "figure.arms.open",
            count: scans.count,
            unit: "scans"
        )
    }

    private var pslStanding: some View {
        scoreStandingCard(
            label: "PSL",
            hasData: !faces.isEmpty,
            score: pslScore,
            tier: pslTier,
            subtitle: faces.first.map { _ in "Facial Harmony" } ?? "No facial scans yet",
            icon: "face.smiling",
            count: faces.count,
            unit: "analyses"
        )
    }

    private func scoreStandingCard(label: String, hasData: Bool, score: Double, tier: Tier,
                                   subtitle: String, icon: String, count: Int, unit: String) -> some View {
        HStack(spacing: 14) {
            TierEmblem(tier: tier, size: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text("YOUR \(label) STANDING").font(.system(size: 9, weight: .bold)).tracking(1.6)
                    .foregroundStyle(Theme.textTertiary)
                if hasData {
                    Text("\(Int(score)) · \(tier.title)").font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(subtitle).font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(tier.color)
                } else {
                    Text("No data yet").font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Run an analysis to unlock your standing.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            if hasData {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(unit.uppercased()).font(.system(size: 8, weight: .bold)).tracking(1.4)
                        .foregroundStyle(Theme.textTertiary)
                    Text("\(count)").font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                }
            } else {
                Image(systemName: icon).font(.system(size: 22, weight: .light))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(16)
        .glassCard(radius: 20)
    }

    private var physiqueDistribution: some View {
        scoreDistributionCard(myTier: physiqueTier, title: "Physique Tier Distribution")
    }

    private var pslDistribution: some View {
        scoreDistributionCard(myTier: pslTier, title: "PSL Tier Distribution")
    }

    private func scoreDistributionCard(myTier: Tier, title: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold)).tracking(2)
                .foregroundStyle(Theme.textTertiary)
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(Tier.allCases, id: \.self) { t in
                    let pct = scoreDistributionPct(t)
                    let isMe = t == myTier
                    VStack(spacing: 8) {
                        Spacer(minLength: 0)
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 8).fill(t.color.opacity(0.25))
                                .frame(width: 38, height: 110)
                            RoundedRectangle(cornerRadius: 8)
                                .fill(LinearGradient(colors: [t.color.opacity(0.5), t.color],
                                                     startPoint: .top, endPoint: .bottom))
                                .frame(width: 38, height: 110 * pct)
                                .shadow(color: t.color.opacity(0.5), radius: 6)
                        }
                        Text(t.title.prefix(1).uppercased())
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(isMe ? Theme.textPrimary : Theme.textTertiary)
                        if isMe {
                            Text("YOU").font(.system(size: 8, weight: .bold)).tracking(1)
                                .foregroundStyle(Theme.accentGlow)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: 20)
    }

    private func scoreDistributionPct(_ t: Tier) -> CGFloat {
        switch t {
        case .bronze: 1.0
        case .silver: 0.68
        case .gold:   0.40
        case .elite:  0.18
        case .greek:  0.05
        }
    }

    private var physiqueTierLadder: some View {
        scoreTierLadder(myTier: physiqueTier, header: "Physique Tier Ladder")
    }

    private var pslTierLadder: some View {
        scoreTierLadder(myTier: pslTier, header: "PSL Tier Ladder")
    }

    private func scoreTierLadder(myTier: Tier, header: String) -> some View {
        VStack(spacing: 10) {
            SectionHeader(title: header)
            ForEach(Tier.allCases, id: \.self) { t in
                HStack(spacing: 14) {
                    TierEmblem(tier: t, size: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t.title).font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text(t.subtitle).font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(t.scoreRange.lowerBound)\u{2013}\(t.scoreRange.upperBound)")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Theme.textSecondary)
                        Text("SCORE").font(.system(size: 8, weight: .bold)).tracking(1.4)
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                .padding(12)
                .background {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(t == myTier ? t.color.opacity(0.12) : Theme.surface.opacity(0.5))
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(t == myTier ? t.color.opacity(0.5) : Theme.line,
                                      lineWidth: t == myTier ? 1 : 0.5)
                }
            }
        }
    }

    // MARK: - Create / Join sheets

    private var createSheet: some View {
        ScrollView {
            VStack(spacing: 18) {
                Text("New Circle").font(.aetherTitle)
                    .foregroundStyle(Theme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 8) {
                    Text("NAME").font(.system(size: 10, weight: .bold)).tracking(1.8)
                        .foregroundStyle(Theme.textTertiary)
                    TextField("Gym Bros", text: $newName)
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface.opacity(0.6)))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.line, lineWidth: 0.6))
                        .textInputAutocapitalization(.words)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("ACCENT").font(.system(size: 10, weight: .bold)).tracking(1.8)
                        .foregroundStyle(Theme.textTertiary)
                    HStack(spacing: 10) {
                        ForEach(GroupAccent.allCases) { a in
                            Button {
                                Haptics.tap(); withAnimation(Motion.snappy) { newAccent = a }
                            } label: {
                                Circle().fill(a.color)
                                    .frame(width: 34, height: 34)
                                    .overlay(Circle().strokeBorder(a == newAccent ? .white : .white.opacity(0.2),
                                                                    lineWidth: a == newAccent ? 2 : 0.6))
                                    .shadow(color: a.color.opacity(0.5),
                                            radius: a == newAccent ? 8 : 0)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                PrimaryButton(title: "Create Circle", icon: "checkmark") {
                    let n = newName.trimmingCharacters(in: .whitespaces)
                    guard !n.isEmpty else { return }
                    let g = FriendGroup(name: n, accent: newAccent)
                    ctx.insert(g)
                    try? ctx.save()
                    Haptics.success()
                    showCreate = false
                }
                .padding(.top, 6)

                Color.clear.frame(height: 30)
            }
            .padding(.horizontal, 20).padding(.top, 16)
        }
        .scrollIndicators(.hidden)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var joinSheet: some View {
        ScrollView {
            VStack(spacing: 18) {
                Text("Join a Circle").font(.aetherTitle)
                    .foregroundStyle(Theme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 8) {
                    Text("INVITE CODE").font(.system(size: 10, weight: .bold)).tracking(1.8)
                        .foregroundStyle(Theme.textTertiary)
                    TextField("ABC123", text: $joinCode)
                        .padding(14)
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .tracking(4)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface.opacity(0.6)))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.line, lineWidth: 0.6))
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .onChange(of: joinCode) { _, new in
                            joinCode = String(new.uppercased().prefix(6))
                        }
                    if let err = joinError {
                        Text(err).font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.bad)
                    }
                }

                PrimaryButton(title: "Join", icon: "arrow.right") {
                    attemptJoin()
                }
                .padding(.top, 6)

                Text("Don't have a code? Ask a friend to share their invite link from their circle.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 10)
                Color.clear.frame(height: 30)
            }
            .padding(.horizontal, 20).padding(.top, 16)
        }
        .scrollIndicators(.hidden)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private func attemptJoin() {
        let code = joinCode.trimmingCharacters(in: .whitespaces).uppercased()
        guard code.count == 6 else { joinError = "Codes are 6 characters."; return }
        if groups.first(where: { $0.inviteCode == code }) != nil {
            joinError = "You're already in that circle."
            return
        }
        // Create an empty circle that holds the invite code — real members appear when they accept.
        let g = FriendGroup(name: "Circle · \(code)",
                            accent: GroupAccent.allCases.randomElement() ?? .steel,
                            inviteCode: code)
        ctx.insert(g)
        try? ctx.save()
        Haptics.success()
        joinCode = ""
        joinError = nil
        showJoin = false
    }
}
