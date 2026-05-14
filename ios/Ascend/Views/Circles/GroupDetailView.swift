import SwiftUI
import SwiftData

struct GroupDetailView: View {
    @Bindable var group: FriendGroup
    let user: UserProfile
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var showInvite = false
    @State private var showRename = false
    @State private var renameDraft = ""
    @State private var pickedAccent: GroupAccent = .steel

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                header.cinematicReveal(delay: 0.02)
                actions.cinematicReveal(delay: 0.08)
                leaderboard.cinematicReveal(delay: 0.16)
                accentPicker.cinematicReveal(delay: 0.24)
                dangerZone.cinematicReveal(delay: 0.32)
                Color.clear.frame(height: 40)
            }
            .padding(.horizontal, 20).padding(.top, 12)
        }
        .scrollIndicators(.hidden)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    renameDraft = group.name
                    showRename = true
                } label: {
                    Image(systemName: "pencil")
                }
            }
        }
        .sheet(isPresented: $showInvite) {
            InviteSheet(group: group, inviterName: user.name)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .alert("Rename Circle", isPresented: $showRename) {
            TextField("Name", text: $renameDraft)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                let trimmed = renameDraft.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { group.name = trimmed; try? ctx.save() }
            }
        }
        .onAppear { pickedAccent = group.accent }
    }

    private var header: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        AngularGradient(
                            colors: [group.accent.color.opacity(0.4), group.accent.color, .white.opacity(0.9), group.accent.color],
                            center: .center
                        )
                    )
                    .frame(width: 72, height: 72)
                    .shadow(color: group.accent.color.opacity(0.5), radius: 18)
                Text(group.name.prefix(1).uppercased())
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.black.opacity(0.75))
            }
            .depthShimmer()
            Text(group.name)
                .font(.aetherTitle)
                .foregroundStyle(Theme.textPrimary)
            Text("\(group.members.filter { !$0.isPending }.count + 1) members · code \(group.inviteCode)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button {
                Haptics.tap(); showInvite = true
            } label: {
                HStack {
                    Image(systemName: "person.crop.circle.badge.plus")
                    Text("Invite")
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.bg)
                .frame(maxWidth: .infinity).frame(height: 48)
                .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.95)))
            }.buttonStyle(.plain)

            ShareLink(item: group.inviteURL, message: Text("Join my Ascend circle \"\(group.name)\" with code \(group.inviteCode)")) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 48, height: 48)
                    .foregroundStyle(Theme.textPrimary)
                    .glassCard(radius: 14)
            }
            .simultaneousGesture(TapGesture().onEnded { Haptics.tap() })
        }
    }

    private var leaderboard: some View {
        let ranked = group.rankedMembers(currentUserXP: user.xp, currentUserName: user.name)
        return VStack(spacing: 10) {
            SectionHeader(title: "Private Leaderboard")
                .padding(.horizontal, 2)

            ForEach(Array(ranked.enumerated()), id: \.element.id) { idx, m in
                rankRow(rank: idx + 1, member: m)
            }

            let pending = group.members.filter { $0.isPending }
            if !pending.isEmpty {
                SectionHeader(title: "Pending Invites")
                    .padding(.horizontal, 2).padding(.top, 8)
                ForEach(pending) { m in
                    HStack(spacing: 12) {
                        avatar(for: m, color: group.accent.color)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(m.displayName).font(.system(size: 14, weight: .semibold))
                            if !m.phoneOrEmail.isEmpty {
                                Text(m.phoneOrEmail).font(.system(size: 11))
                                    .foregroundStyle(Theme.textTertiary).lineLimit(1)
                            }
                        }
                        Spacer()
                        Button {
                            ctx.delete(m); try? ctx.save(); Haptics.tap()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(Theme.textTertiary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(12)
                    .glassCard(radius: 14)
                }
            }
        }
    }

    private func rankRow(rank: Int, member: FriendGroup.RankedMember) -> some View {
        HStack(spacing: 14) {
            Text("#\(rank)")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(rank <= 3 ? member.tier.color : Theme.textTertiary)
                .frame(width: 36, alignment: .leading)
            TierEmblem(tier: member.tier, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(member.name).font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(member.tier.title).font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(member.tier.color)
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
                .fill(member.isMe ? group.accent.color.opacity(0.14) : Theme.surface.opacity(0.5))
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(member.isMe ? group.accent.color.opacity(0.55) : Theme.line,
                              lineWidth: member.isMe ? 1 : 0.5)
        }
    }

    private func avatar(for m: Friend, color: Color) -> some View {
        ZStack {
            Circle().fill(color.opacity(0.3))
            Text(m.initials).font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
        }
        .frame(width: 30, height: 30)
    }

    private var accentPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Accent")
            HStack(spacing: 10) {
                ForEach(GroupAccent.allCases) { accent in
                    Button {
                        Haptics.tap()
                        withAnimation(.snappy) {
                            pickedAccent = accent
                            group.accentRaw = accent.rawValue
                            try? ctx.save()
                        }
                    } label: {
                        Circle()
                            .fill(accent.color)
                            .frame(width: 30, height: 30)
                            .overlay(Circle().strokeBorder(accent == pickedAccent ? .white : .white.opacity(0.2),
                                                            lineWidth: accent == pickedAccent ? 2 : 0.6))
                            .shadow(color: accent.color.opacity(0.5), radius: accent == pickedAccent ? 8 : 0)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var dangerZone: some View {
        Button(role: .destructive) {
            Haptics.medium()
            ctx.delete(group)
            try? ctx.save()
            dismiss()
        } label: {
            HStack {
                Image(systemName: "trash")
                Text("Delete Circle")
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Theme.bad)
            .frame(maxWidth: .infinity).frame(height: 46)
            .background(RoundedRectangle(cornerRadius: 14).fill(Theme.bad.opacity(0.12)))
        }
        .buttonStyle(.plain)
    }
}
