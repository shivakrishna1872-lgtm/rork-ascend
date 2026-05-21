import SwiftUI
import SwiftData
import PhotosUI

/// iMessage-style chat with the AI coach. The coach can take real actions in
/// the app (set calorie/protein targets, log meals/lifts/water, update profile,
/// open scan flows, generate a week plan). Messages are session-only and never
/// persisted to disk. Falls back to a deterministic offline reply if every
/// upstream AI model is unreachable so chat never feels broken.
struct CoachChatView: View {
    let user: UserProfile
    @Environment(\.modelContext) private var ctx
    @Query(sort: \PhysiqueScanRecord.date, order: .reverse) private var scans: [PhysiqueScanRecord]
    @Query(sort: \FaceScanRecord.date, order: .reverse) private var faces: [FaceScanRecord]
    @Query(sort: \MealEntry.date, order: .reverse) private var meals: [MealEntry]
    @Query(sort: \LiftEntry.date, order: .reverse) private var lifts: [LiftEntry]

    @State private var messages: [ChatMessage] = []
    @State private var input: String = ""
    @State private var sending: Bool = false
    @State private var pendingImages: [UIImage] = []
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var typingShown: Bool = false
    @FocusState private var inputFocused: Bool

    private var shouldShowStarters: Bool {
        guard let last = messages.last else { return true }
        if case .assistant = last.kind { return true }
        return false
    }

    private let starters: [String] = [
        "How am I doing this week?",
        "I was sick — drop today's cals",
        "Plan my week",
        "Log 200g chicken & 1 cup rice",
        "Log bench 100kg PR",
        "Add a glass of water"
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 18)
                .padding(.top, 6)
                .padding(.bottom, 8)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        if messages.isEmpty {
                            emptyState.padding(.top, 28).padding(.horizontal, 18)
                        }
                        ForEach(messages) { m in
                            messageRow(m)
                                .padding(.horizontal, 14)
                                .id(m.id)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                        if typingShown {
                            HStack {
                                typingBubble
                                Spacer()
                            }
                            .padding(.horizontal, 14)
                            .id("typing")
                            .transition(.opacity)
                        }
                        Color.clear.frame(height: 6).id("bottom")
                    }
                    .padding(.top, 10)
                }
                .scrollIndicators(.hidden)
                .onChange(of: messages.count) { _, _ in
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
                .onChange(of: typingShown) { _, on in
                    if on {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
                            proxy.scrollTo("typing", anchor: .bottom)
                        }
                    }
                }
            }

            if shouldShowStarters {
                starterChips
                    .padding(.bottom, 6)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            composer
                .padding(.horizontal, 14)
                .padding(.bottom, 96) // floating tab bar
                .padding(.top, 6)
        }
        .background(Color.clear)
        .animation(.spring(response: 0.4, dampingFraction: 0.86), value: messages.count)
        .onChange(of: pickerItems) { _, items in
            Task { await loadPickedImages(items) }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            ZStack {
                Circle().fill(Theme.accent.opacity(0.2))
                    .overlay(Circle().strokeBorder(Theme.accent.opacity(0.5), lineWidth: 0.6))
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.accentGlow)
            }
            .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text("Coach".uppercased())
                    .font(.system(size: 10, weight: .heavy)).tracking(2)
                    .foregroundStyle(Theme.textTertiary)
                Text("Your AI coach")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
            }
            Spacer()
            Button {
                Haptics.tap()
                withAnimation(.smooth(duration: 0.35)) {
                    messages.removeAll()
                    pendingImages.removeAll()
                    pickerItems.removeAll()
                }
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 38, height: 38)
                    .glassCard(radius: 12)
            }
            .buttonStyle(.plain)
            .opacity(messages.isEmpty ? 0.4 : 1)
            .disabled(messages.isEmpty)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().fill(Theme.accent.opacity(0.15))
                Circle().strokeBorder(Theme.accent.opacity(0.45), lineWidth: 0.8)
                Image(systemName: "sparkles")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Theme.accentGlow)
            }
            .frame(width: 64, height: 64)
            .ambientFloat(amplitude: 3, duration: 3.0)

            VStack(spacing: 6) {
                Text("Talk to your coach")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Ask anything, attach a photo, or just say what you need. I can adjust your targets, log meals or water, log lifts, and pull up scans for you.")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Starter chips

    private var starterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(starters, id: \.self) { s in
                    Button {
                        Haptics.soft()
                        input = s
                        inputFocused = true
                    } label: {
                        Text(s)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(Capsule().fill(Theme.surface.opacity(0.55)))
                            .overlay(Capsule().strokeBorder(Theme.lineStrong, lineWidth: 0.6))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .contentMargins(.horizontal, 16)
    }

    // MARK: - Message row

    private func messageRow(_ m: ChatMessage) -> some View {
        Group {
            switch m.kind {
            case .user:
                HStack {
                    Spacer(minLength: 36)
                    userBubble(m)
                }
            case .assistant:
                HStack(alignment: .bottom, spacing: 8) {
                    avatar
                    assistantBubble(m)
                    Spacer(minLength: 36)
                }
            case .action(let action, _):
                HStack {
                    actionCard(for: m, action: action)
                    Spacer(minLength: 24)
                }
            }
        }
    }

    private var avatar: some View {
        ZStack {
            Circle().fill(Theme.accent.opacity(0.2))
                .overlay(Circle().strokeBorder(Theme.accent.opacity(0.5), lineWidth: 0.6))
            Image(systemName: "sparkles")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Theme.accentGlow)
        }
        .frame(width: 22, height: 22)
        .padding(.bottom, 4)
    }

    private func userBubble(_ m: ChatMessage) -> some View {
        VStack(alignment: .trailing, spacing: 6) {
            if !m.images.isEmpty {
                HStack(spacing: 6) {
                    ForEach(Array(m.images.enumerated()), id: \.offset) { _, img in
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 120, height: 120)
                            .clipShape(.rect(cornerRadius: 14))
                    }
                }
            }
            if !m.text.isEmpty {
                Text(m.text)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Theme.accent.opacity(0.30))
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Theme.accent.opacity(0.6), lineWidth: 0.6)
                    )
            }
        }
    }

    private func assistantBubble(_ m: ChatMessage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(m.text)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Theme.surface.opacity(0.6))
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Theme.lineStrong, lineWidth: 0.6)
                )
            if m.isOffline {
                Text("OFFLINE MODE")
                    .font(.system(size: 8, weight: .heavy)).tracking(1.5)
                    .foregroundStyle(Theme.warn)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(Theme.warn.opacity(0.15)))
                    .overlay(Capsule().strokeBorder(Theme.warn.opacity(0.4), lineWidth: 0.5))
                    .padding(.leading, 4)
            }
        }
    }

    private var typingBubble: some View {
        HStack(alignment: .bottom, spacing: 8) {
            avatar
            HStack(spacing: 5) {
                ForEach(0..<3) { i in
                    TypingDot(delay: Double(i) * 0.18)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.surface.opacity(0.6)))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.lineStrong, lineWidth: 0.6))
        }
    }

    // MARK: - Action card

    private func actionCard(for message: ChatMessage, action: CoachToolCall) -> some View {
        let state = message.actionState
        let tint = CoachActionStyle.tint(for: action.tool)
        let icon = CoachActionStyle.icon(for: action.tool)
        let needsConfirm = CoachActionStyle.needsConfirm(action.tool)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(tint.opacity(0.18))
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(tint)
                }
                .frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(actionTitle(for: action.tool))
                        .font(.system(size: 11, weight: .heavy)).tracking(1.2)
                        .foregroundStyle(Theme.textTertiary)
                    Text(action.summary)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            // Plan card extra: show plan text
            if action.tool == "generatePlan", let plan = action.args.planText, !plan.isEmpty {
                Text(plan)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }

            switch state {
            case .pending:
                if needsConfirm {
                    HStack(spacing: 8) {
                        Button {
                            Haptics.tap()
                            cancelAction(message.id)
                        } label: {
                            Text("Cancel")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Theme.textSecondary)
                                .frame(maxWidth: .infinity)
                                .frame(height: 38)
                                .background(RoundedRectangle(cornerRadius: 11).fill(Theme.surface.opacity(0.55)))
                                .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Theme.lineStrong, lineWidth: 0.6))
                        }
                        .buttonStyle(.plain)
                        Button {
                            Haptics.medium()
                            applyAction(message.id, action: action, manual: true)
                        } label: {
                            Text("Apply")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Theme.bg)
                                .frame(maxWidth: .infinity)
                                .frame(height: 38)
                                .background(RoundedRectangle(cornerRadius: 11).fill(tint))
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    ProgressView().tint(Theme.accentGlow).padding(.vertical, 4)
                }
            case .applied:
                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Theme.good)
                        Text("Applied")
                            .font(.system(size: 12, weight: .heavy)).tracking(1)
                            .foregroundStyle(Theme.good)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Capsule().fill(Theme.good.opacity(0.15)))
                    .overlay(Capsule().strokeBorder(Theme.good.opacity(0.4), lineWidth: 0.5))
                    if CoachActionStyle.supportsUndo(action.tool) {
                        Button {
                            Haptics.tap()
                            undoAction(message.id, action: action)
                        } label: {
                            Text("Undo")
                                .font(.system(size: 12, weight: .heavy)).tracking(1)
                                .foregroundStyle(Theme.textPrimary)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(Capsule().fill(Theme.surface.opacity(0.6)))
                                .overlay(Capsule().strokeBorder(Theme.lineStrong, lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer(minLength: 0)
                }
            case .cancelled:
                Text("CANCELLED")
                    .font(.system(size: 10, weight: .heavy)).tracking(1.5)
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().fill(Theme.surface.opacity(0.6)))
            case .undone:
                Text("UNDONE")
                    .font(.system(size: 10, weight: .heavy)).tracking(1.5)
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().fill(Theme.surface.opacity(0.6)))
            case .failed(let reason):
                Text(reason.uppercased())
                    .font(.system(size: 10, weight: .heavy)).tracking(1.2)
                    .foregroundStyle(Theme.bad)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().fill(Theme.bad.opacity(0.15)))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.surface.opacity(0.65)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(tint.opacity(0.4), lineWidth: 0.7))
    }

    private func actionTitle(for tool: String) -> String {
        switch tool {
        case "setCalorieTarget": return "CALORIE TARGET"
        case "setProteinTarget": return "PROTEIN TARGET"
        case "updateProfile":    return "PROFILE UPDATE"
        case "logMeal":          return "LOG MEAL"
        case "removeLastMeal":   return "REMOVE MEAL"
        case "logLifts":         return "LOG LIFTS"
        case "addHydration":     return "HYDRATION"
        case "openTab":          return "OPEN"
        case "generatePlan":     return "WEEK PLAN"
        default:                 return "ACTION"
        }
    }

    // MARK: - Composer

    private var composer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !pendingImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(pendingImages.enumerated()), id: \.offset) { idx, img in
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: img)
                                    .resizable().scaledToFill()
                                    .frame(width: 56, height: 56)
                                    .clipShape(.rect(cornerRadius: 10))
                                Button {
                                    Haptics.tap()
                                    pendingImages.remove(at: idx)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundStyle(.white, .black.opacity(0.6))
                                }
                                .offset(x: 5, y: -5)
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }
            HStack(spacing: 8) {
                PhotosPicker(selection: $pickerItems,
                             maxSelectionCount: 3,
                             matching: .images) {
                    Image(systemName: "paperclip")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(Theme.surface.opacity(0.55)))
                        .overlay(Circle().strokeBorder(Theme.lineStrong, lineWidth: 0.6))
                }

                TextField("Message your coach…", text: $input, axis: .vertical)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(Theme.textPrimary)
                    .tint(Theme.accentGlow)
                    .focused($inputFocused)
                    .lineLimit(1...4)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 20).fill(Theme.surface.opacity(0.55)))
                    .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Theme.lineStrong, lineWidth: 0.6))

                let canSend = !sending && (!input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !pendingImages.isEmpty)
                Button {
                    Haptics.medium()
                    Task { await send() }
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(canSend ? Theme.bg : Theme.textTertiary)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(canSend ? Theme.accentGlow : Theme.surface.opacity(0.55)))
                        .overlay(Circle().strokeBorder(canSend ? Theme.accentGlow : Theme.lineStrong, lineWidth: 0.6))
                        .shadow(color: canSend ? Theme.accentGlow.opacity(0.5) : .clear, radius: 8)
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
            }
        }
    }

    // MARK: - Sending

    @MainActor
    private func loadPickedImages(_ items: [PhotosPickerItem]) async {
        var loaded: [UIImage] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               let img = UIImage(data: data) {
                loaded.append(img)
            }
        }
        pendingImages.append(contentsOf: loaded)
        pickerItems.removeAll()
    }

    private func send() async {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let imgs = pendingImages
        guard !text.isEmpty || !imgs.isEmpty else { return }

        let userMessage = ChatMessage(kind: .user, text: text, images: imgs)
        await MainActor.run {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) {
                messages.append(userMessage)
            }
            input = ""
            pendingImages = []
            sending = true
            typingShown = true
        }

        // Build history (text + last attachment carries images)
        let history = messages.map { m -> ChatTurn in
            switch m.kind {
            case .user:
                return ChatTurn(role: "user", text: m.text, images: m.images.isEmpty ? nil : m.images)
            case .assistant:
                return ChatTurn(role: "assistant", text: m.text)
            case .action(let a, _):
                let json = "[action: \(a.tool) — \(a.summary)]"
                return ChatTurn(role: "assistant", text: json)
            }
        }
        let context = buildContext()

        do {
            let reply = try await AIService.shared.coachChat(history: history, context: context)
            await MainActor.run {
                typingShown = false
                appendAssistantReply(reply)
                sending = false
            }
        } catch let e as AIServiceError {
            await MainActor.run {
                typingShown = false
                sending = false
                let assistant = ChatMessage(kind: .assistant,
                                            text: e.errorDescription ?? "Something went wrong.",
                                            isOffline: true)
                withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) {
                    messages.append(assistant)
                }
            }
        } catch {
            await MainActor.run {
                typingShown = false
                sending = false
                let assistant = ChatMessage(kind: .assistant,
                                            text: "I couldn't reach the coach right now. Try again in a moment.",
                                            isOffline: true)
                withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) {
                    messages.append(assistant)
                }
            }
        }
    }

    @MainActor
    private func appendAssistantReply(_ reply: CoachReply) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) {
            if !reply.reply.isEmpty {
                messages.append(ChatMessage(kind: .assistant, text: reply.reply,
                                            isOffline: reply.isOffline == true))
            }
            for action in reply.actions {
                let msg = ChatMessage(kind: .action(action, action.id), text: "")
                messages.append(msg)
                // Auto-apply small actions immediately.
                if !CoachActionStyle.needsConfirm(action.tool) {
                    applyAction(msg.id, action: action, manual: false)
                }
            }
        }
    }

    // MARK: - Actions

    private func applyAction(_ messageId: UUID, action: CoachToolCall, manual: Bool) {
        let result = CoachActionRunner.apply(action: action, user: user, ctx: ctx, meals: meals, lifts: lifts)
        if let idx = messages.firstIndex(where: { $0.id == messageId }) {
            switch result {
            case .applied:
                messages[idx].actionState = .applied
                Haptics.success()
            case .failed(let r):
                messages[idx].actionState = .failed(r)
                Haptics.warning()
            }
        }
    }

    private func cancelAction(_ messageId: UUID) {
        guard let idx = messages.firstIndex(where: { $0.id == messageId }) else { return }
        messages[idx].actionState = .cancelled
    }

    private func undoAction(_ messageId: UUID, action: CoachToolCall) {
        CoachActionRunner.undo(action: action, user: user, ctx: ctx, meals: meals, lifts: lifts)
        if let idx = messages.firstIndex(where: { $0.id == messageId }) {
            messages[idx].actionState = .undone
        }
    }

    // MARK: - Context

    private func buildContext() -> CoachContext {
        let snap = ProfileSnapshot(
            age: user.ageValue, sex: user.sexRaw,
            heightCm: user.heightCm, weightKg: user.weightKg,
            goals: user.goalsRaw, unitSystem: user.unitSystemRaw
        )
        let cal = Calendar.current
        let cutoff = cal.date(byAdding: .day, value: -7, to: .now) ?? .now.addingTimeInterval(-7*86400)
        let recent = meals.filter { $0.date >= cutoff }
        var byDay: [Date: (kcal: Int, p: Int)] = [:]
        for m in recent {
            let d = cal.startOfDay(for: m.date)
            var e = byDay[d] ?? (0, 0)
            e.kcal += m.calories; e.p += m.proteinG
            byDay[d] = e
        }
        let n = max(1, byDay.count)
        let avgKcal = byDay.values.reduce(0) { $0 + $1.kcal } / n
        let avgProt = byDay.values.reduce(0) { $0 + $1.p } / n
        let today = meals.filter { cal.isDateInToday($0.date) }
        let todayCals = today.reduce(0) { $0 + $1.calories }
        let todayProt = today.reduce(0) { $0 + $1.proteinG }

        let p0 = scans.first
        let pTrend: Double = {
            guard let newest = scans.first, scans.count >= 2,
                  let oldest = scans.prefix(6).last else { return 0 }
            return newest.physiqueScore - oldest.physiqueScore
        }()
        let f0 = faces.first
        let fTrend: Double = {
            guard let newest = faces.first, faces.count >= 2,
                  let oldest = faces.prefix(6).last else { return 0 }
            return newest.overallScore - oldest.overallScore
        }()

        let hydration: Int = {
            if let d = user.hydrationDate, cal.isDateInToday(d) { return user.hydrationGlasses }
            return 0
        }()

        return CoachContext(
            profile: snap,
            streak: user.streak,
            xp: user.xp,
            tier: user.tier.rawValue,
            hydrationGlasses: hydration,
            calorieTarget: user.dailyCalorieTarget,
            proteinTarget: user.proteinTargetG,
            baseCalorieTarget: user.baseDailyCalorieTarget,
            calorieOverrideUntil: user.calorieOverrideUntil,
            latestPhysique: p0?.physiqueScore,
            latestBodyFat: p0?.bodyFatPercent,
            physiqueTrend: pTrend,
            physiqueScanCount: scans.count,
            latestPSL: f0?.overallScore,
            faceTrend: fTrend,
            faceScanCount: faces.count,
            avgCalories: avgKcal,
            avgProtein: avgProt,
            mealsLogged7d: recent.count,
            todayCalories: todayCals,
            todayProtein: todayProt,
            benchKg: lifts.first(where: { $0.benchKg > 0 })?.benchKg,
            squatKg: lifts.first(where: { $0.squatKg > 0 })?.squatKg,
            deadliftKg: lifts.first(where: { $0.deadliftKg > 0 })?.deadliftKg
        )
    }
}

// MARK: - Chat message model (in-memory only)

struct ChatMessage: Identifiable {
    let id: UUID
    let kind: Kind
    let text: String
    let images: [UIImage]
    let isOffline: Bool
    var actionState: ActionState = .pending

    init(kind: Kind, text: String, images: [UIImage] = [], isOffline: Bool = false) {
        self.id = UUID()
        self.kind = kind
        self.text = text
        self.images = images
        self.isOffline = isOffline
    }

    enum Kind {
        case user
        case assistant
        case action(CoachToolCall, String)
    }

    enum ActionState {
        case pending
        case applied
        case cancelled
        case undone
        case failed(String)
    }
}

// MARK: - Visual styling for action cards

enum CoachActionStyle {
    static func icon(for tool: String) -> String {
        switch tool {
        case "setCalorieTarget": return "flame.fill"
        case "setProteinTarget": return "fork.knife"
        case "updateProfile":    return "person.crop.circle.badge.checkmark"
        case "logMeal":          return "fork.knife.circle.fill"
        case "removeLastMeal":   return "trash.fill"
        case "logLifts":         return "dumbbell.fill"
        case "addHydration":     return "drop.fill"
        case "openTab":          return "arrow.up.right.square.fill"
        case "generatePlan":     return "list.bullet.rectangle.fill"
        default:                 return "sparkles"
        }
    }
    static func tint(for tool: String) -> Color {
        switch tool {
        case "setCalorieTarget", "setProteinTarget", "updateProfile": return Theme.accentGlow
        case "logMeal", "removeLastMeal":   return Theme.warn
        case "logLifts":                    return Theme.good
        case "addHydration":                return Theme.accent
        case "openTab":                     return Theme.accentGlow
        case "generatePlan":                return Theme.gold
        default:                            return Theme.accent
        }
    }
    static func needsConfirm(_ tool: String) -> Bool {
        switch tool {
        case "setCalorieTarget", "setProteinTarget", "updateProfile", "removeLastMeal":
            return true
        default:
            return false
        }
    }
    static func supportsUndo(_ tool: String) -> Bool {
        switch tool {
        case "addHydration", "logMeal", "logLifts", "openTab", "generatePlan":
            return true
        default:
            return false
        }
    }
}

// MARK: - Typing dot

private struct TypingDot: View {
    let delay: Double
    @State private var on = false
    var body: some View {
        Circle()
            .fill(Theme.textSecondary)
            .frame(width: 6, height: 6)
            .opacity(on ? 1 : 0.3)
            .scaleEffect(on ? 1 : 0.7)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true).delay(delay)) {
                    on = true
                }
            }
    }
}
