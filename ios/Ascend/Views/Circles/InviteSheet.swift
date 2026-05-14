import SwiftUI
import SwiftData

struct InviteSheet: View {
    let group: FriendGroup
    let inviterName: String
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var showContacts = false
    @State private var codeCopied = false

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                header
                inviteCard
                actions
                if !group.members.isEmpty {
                    pendingSection
                }
                Color.clear.frame(height: 20)
            }
            .padding(.horizontal, 20).padding(.top, 8)
        }
        .scrollIndicators(.hidden)
        .background(Theme.bg.opacity(0.0))
        .sheet(isPresented: $showContacts) {
            ContactsPicker { picked in
                addContacts(picked)
                showContacts = false
            }
            .ignoresSafeArea()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("INVITE TO".uppercased())
                .font(.system(size: 10, weight: .bold)).tracking(2)
                .foregroundStyle(Theme.textTertiary)
            Text(group.name)
                .font(.aetherTitle)
                .foregroundStyle(Theme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var inviteCard: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(
                        AngularGradient(
                            colors: [group.accent.color.opacity(0.4),
                                     group.accent.color,
                                     .white.opacity(0.9),
                                     group.accent.color],
                            center: .center
                        )
                    )
                    .frame(width: 78, height: 78)
                    .shadow(color: group.accent.color.opacity(0.5), radius: 18)
                Image(systemName: "person.2.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.black.opacity(0.75))
            }
            .depthShimmer()

            VStack(spacing: 4) {
                Text("Your invite code")
                    .font(.system(size: 11, weight: .semibold)).tracking(1.6)
                    .foregroundStyle(Theme.textTertiary)
                Button {
                    UIPasteboard.general.string = group.inviteCode
                    Haptics.success()
                    withAnimation(.snappy) { codeCopied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                        withAnimation { codeCopied = false }
                    }
                } label: {
                    HStack(spacing: 10) {
                        Text(group.inviteCode)
                            .font(.system(size: 32, weight: .bold, design: .monospaced))
                            .tracking(6)
                            .foregroundStyle(Theme.textPrimary)
                        Image(systemName: codeCopied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(codeCopied ? Theme.good : Theme.textTertiary)
                            .contentTransition(.symbolEffect(.replace))
                    }
                }
                .buttonStyle(.plain)
                Text("Anyone with this code joins your circle.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.vertical, 26)
        .frame(maxWidth: .infinity)
        .glassCard(radius: 26)
    }

    private var actions: some View {
        VStack(spacing: 10) {
            ShareLink(item: shareURL, message: Text(shareMessage)) {
                HStack {
                    Image(systemName: "square.and.arrow.up")
                    Text("Share invite link").font(.system(size: 16, weight: .semibold))
                }
                .foregroundStyle(Theme.bg)
                .frame(maxWidth: .infinity).frame(height: 54)
                .background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.95)))
            }
            .simultaneousGesture(TapGesture().onEnded { Haptics.medium() })

            GhostButton(title: "Pick from contacts", icon: "person.crop.circle.badge.plus") {
                showContacts = true
            }
        }
    }

    private var pendingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Members")
            ForEach(group.members) { m in
                HStack(spacing: 12) {
                    avatar(for: m)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(m.displayName).font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        if !m.phoneOrEmail.isEmpty {
                            Text(m.phoneOrEmail).font(.system(size: 11))
                                .foregroundStyle(Theme.textTertiary)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                    if m.isPending {
                        Text("PENDING")
                            .font(.system(size: 9, weight: .bold)).tracking(1.5)
                            .foregroundStyle(Theme.warn)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Capsule().fill(Theme.warn.opacity(0.15)))
                    } else {
                        Text("\(m.xp) XP")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .padding(12)
                .glassCard(radius: 14)
            }
        }
    }

    private func avatar(for m: Friend) -> some View {
        ZStack {
            Circle().fill(group.accent.color.opacity(0.3))
            Text(m.initials)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
        }
        .frame(width: 32, height: 32)
    }

    private var shareURL: URL { group.inviteURL }
    private var shareMessage: String {
        "\(inviterName) invited you to \"\(group.name)\" on Ascend. Join with code \(group.inviteCode)."
    }

    private func addContacts(_ contacts: [ContactsPicker.PickedContact]) {
        for c in contacts {
            let f = Friend(displayName: c.name, phoneOrEmail: c.phoneOrEmail, source: .contact, xp: 0, isPending: true)
            f.group = group
            ctx.insert(f)
        }
        try? ctx.save()
        Haptics.success()
    }
}
