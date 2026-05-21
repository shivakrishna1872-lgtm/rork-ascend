import SwiftUI
import SwiftData

/// Backend-backed Circles tab. Server is the source of truth; we cache
/// the most recent fetch in @State and poll every 5s while visible.
struct CirclesView: View {
    let user: UserProfile

    @State private var mode: Mode = .circles
    @State private var circles: [RemoteCircle] = []
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var refreshTask: Task<Void, Never>? = nil

    @State private var showCreate = false
    @State private var showJoin = false
    @State private var newName = ""
    @State private var newAccent: GroupAccent = .steel
    @State private var joinCode = ""
    @State private var joinError: String? = nil
    @State private var joining = false
    @State private var creating = false

    @State private var path = NavigationPath()
    @State private var deepLink = DeepLinkRouter.shared

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
                        GlobalRankingsView()
                    }
                }
                .padding(.horizontal, 20).padding(.top, 12)
            }
            .scrollIndicators(.hidden)
            .tabBarBottomInset()
            .refreshable { await loadCircles() }
            .navigationDestination(for: String.self) { circleId in
                GroupDetailView(circleId: circleId, user: user)
            }
            .sheet(isPresented: $showCreate) { createSheet }
            .sheet(isPresented: $showJoin, onDismiss: { joinCode = ""; joinError = nil }) { joinSheet }
        }
        .tint(Theme.accent)
        .task {
            await syncUserOnce()
            await loadCircles()
            startPolling()
            consumePendingDeepLinkIfAny()
        }
        .onDisappear { refreshTask?.cancel(); refreshTask = nil }
        .onChange(of: deepLink.pendingJoinCode) { _, _ in
            consumePendingDeepLinkIfAny()
        }
        .onChange(of: user.xp) { _, _ in
            Task { await syncUserOnce() }
        }
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
                circleIconButton(icon: "arrow.right.circle") { showJoin = true }
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

    // MARK: - Circles content

    @ViewBuilder
    private var circlesContent: some View {
        if loading && circles.isEmpty {
            ForEach(0..<2, id: \.self) { i in skeletonCircle.cinematicReveal(delay: 0.10 + Double(i) * 0.06) }
        } else if let err = loadError, circles.isEmpty {
            errorCard(err)
        } else if circles.isEmpty {
            emptyState.cinematicReveal(delay: 0.12)
        } else {
            ForEach(Array(circles.enumerated()), id: \.element.id) { idx, c in
                Button {
                    Haptics.tap(); path.append(c.id)
                } label: { circleCard(c) }
                .buttonStyle(.plain)
                .cinematicReveal(delay: 0.12 + Double(min(idx, 6)) * 0.05)
            }
        }
    }

    private func circleCard(_ c: RemoteCircle) -> some View {
        let accent = GroupAccent(rawValue: c.accent) ?? .steel
        let myUserId = BackendService.shared.currentUserId
        let myRank = c.members.first(where: { ($0.isMe ?? false) || $0.id == myUserId })?.rank ?? 0
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("CIRCLE").font(.system(size: 9, weight: .bold)).tracking(2)
                        .foregroundStyle(Theme.textTertiary)
                    Text(c.name).font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                }
                Spacer()
                avatarFan(for: c, accent: accent)
            }

            HStack(spacing: 12) {
                statChip(label: "Members", value: "\(c.memberCount)")
                statChip(label: "Your rank", value: myRank > 0 ? "#\(myRank)" : "—")
                inviteChip(code: c.code)
            }

            HStack(spacing: 8) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.textTertiary)
                Text("Long-press code to copy")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
                ShareLink(item: inviteURL(for: c.code),
                          message: Text(shareMessage(for: c))) {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.up")
                        Text("Share")
                    }
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Capsule().fill(Color.white.opacity(0.1)))
                    .overlay(Capsule().strokeBorder(Theme.lineStrong, lineWidth: 0.5))
                }
                .simultaneousGesture(TapGesture().onEnded { Haptics.tap() })
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
                            colors: [accent.color.opacity(0.22), .clear],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(accent.color.opacity(0.35), lineWidth: 0.8)
        )
        .clipShape(.rect(cornerRadius: 22))
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

    private func inviteChip(code: String) -> some View {
        Button {
            UIPasteboard.general.string = code
            Haptics.success()
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text("CODE")
                    .font(.system(size: 8, weight: .bold)).tracking(1.4)
                    .foregroundStyle(Theme.textTertiary)
                HStack(spacing: 4) {
                    Text(code)
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .tracking(1.5)
                        .foregroundStyle(Theme.textPrimary)
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.accent.opacity(0.18)))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.accent.opacity(0.4), lineWidth: 0.6))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                UIPasteboard.general.string = code
                Haptics.success()
            } label: {
                Label("Copy Code", systemImage: "doc.on.doc")
            }
            ShareLink(item: inviteURL(for: code),
                      message: Text("Join my Ascend circle with code \(code)")) {
                Label("Share Invite", systemImage: "square.and.arrow.up")
            }
        }
    }

    private func avatarFan(for c: RemoteCircle, accent: GroupAccent) -> some View {
        let actives = c.members.prefix(3)
        return HStack(spacing: -10) {
            ForEach(Array(actives.enumerated()), id: \.element.id) { _, m in
                ZStack {
                    Circle().fill(accent.color.opacity(0.3))
                    Text(m.avatarSeed.isEmpty ? initials(m.name) : m.avatarSeed)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                }
                .frame(width: 30, height: 30)
                .overlay(Circle().strokeBorder(Theme.bg, lineWidth: 2))
            }
            if c.memberCount > 3 {
                ZStack {
                    Circle().fill(accent.color)
                    Text("+\(c.memberCount - 3)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.black.opacity(0.75))
                }
                .frame(width: 30, height: 30)
                .overlay(Circle().strokeBorder(Theme.bg, lineWidth: 2))
            }
        }
    }

    private func initials(_ name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        return parts.map { String($0.first ?? "?") }.joined().uppercased()
    }

    // MARK: - Empty / error / skeleton

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "person.2.crop.square.stack")
                .font(.system(size: 38, weight: .bold))
                .foregroundStyle(Theme.accent)
                .ambientFloat(amplitude: 3, duration: 3.4)
            Text("Build your first circle")
                .font(.aetherTitle2).foregroundStyle(Theme.textPrimary)
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

    private func errorCard(_ msg: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Theme.warn)
            Text(msg).font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
            GhostButton(title: "Retry", icon: "arrow.clockwise") {
                Task { await loadCircles() }
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity)
        .glassCard(radius: 22)
    }

    private var skeletonCircle: some View {
        VStack(alignment: .leading, spacing: 14) {
            RoundedRectangle(cornerRadius: 6).fill(Theme.surface).frame(width: 140, height: 18)
            HStack(spacing: 10) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 10).fill(Theme.surface).frame(height: 36)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .glassCard(radius: 22)
        .opacity(0.55)
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

                PrimaryButton(title: "Create Circle", icon: "checkmark", loading: creating) {
                    let n = newName.trimmingCharacters(in: .whitespaces)
                    guard !n.isEmpty else { return }
                    creating = true
                    Task {
                        do {
                            let c = try await BackendService.shared.createCircle(
                                name: n, accent: newAccent.rawValue, ownerName: user.name
                            )
                            Haptics.success()
                            await loadCircles()
                            creating = false
                            showCreate = false
                            // Jump straight to detail.
                            path.append(c.id)
                        } catch {
                            creating = false
                            joinError = "Could not create circle: \(error.localizedDescription)"
                        }
                    }
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
                            joinCode = String(new.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(6))
                        }
                    if let err = joinError {
                        Text(err).font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.bad)
                    }
                }

                PrimaryButton(title: "Join", icon: "arrow.right", loading: joining) {
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
        if circles.contains(where: { $0.code == code }) {
            joinError = "You're already in that circle."
            return
        }
        joining = true
        joinError = nil
        Task {
            do {
                let c = try await BackendService.shared.joinCircle(code: code, userName: user.name)
                Haptics.success()
                await loadCircles()
                joining = false
                showJoin = false
                path.append(c.id)
            } catch {
                joining = false
                joinError = (error as? BackendError)?.errorDescription
                    ?? error.localizedDescription
            }
        }
    }

    // MARK: - Data

    private func syncUserOnce() async {
        await BackendService.shared.upsertUser(
            name: user.name, xp: user.xp,
            streak: user.streak, tier: user.tier.rawValue
        )
    }

    private func loadCircles() async {
        do {
            let list = try await BackendService.shared.listCircles()
            withAnimation(.smooth(duration: 0.3)) {
                circles = list
                loadError = nil
            }
        } catch {
            loadError = "Couldn't load your circles."
        }
        loading = false
    }

    private func startPolling() {
        refreshTask?.cancel()
        refreshTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                if Task.isCancelled { break }
                await loadCircles()
            }
        }
    }

    private func consumePendingDeepLinkIfAny() {
        guard let code = deepLink.pendingJoinCode else { return }
        joinCode = code
        joinError = nil
        deepLink.pendingJoinCode = nil
        showJoin = true
    }

    // MARK: - Shareable URLs

    private func inviteURL(for code: String) -> URL {
        let base = Config.EXPO_PUBLIC_RORK_FUNCTIONS_URL
            .trimmingCharacters(in: .init(charactersIn: "/"))
        return URL(string: "\(base)/join/\(code)") ?? URL(string: "https://ascend.app/join/\(code)")!
    }

    private func shareMessage(for c: RemoteCircle) -> String {
        "\(user.name) invited you to \"\(c.name)\" on Ascend. Join with code \(c.code)."
    }
}

// `tabBarBottomInset` lives in the project; reuse it.
