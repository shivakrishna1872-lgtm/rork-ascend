import SwiftUI
import SwiftData
import AuthenticationServices

struct OnboardingFlow: View {
    @Environment(\.modelContext) private var ctx
    let existing: UserProfile?

    @State private var step: Int = 0
    @State private var name: String = ""
    @State private var email: String? = nil
    @State private var appleUserId: String? = nil
    @State private var signedInWithApple: Bool = false
    @State private var age: Int? = nil
    @State private var sex: Sex? = nil
    @State private var heightCm: Double? = nil
    @State private var weightKg: Double? = nil
    @State private var unitSystem: UnitSystem = .metric
    @State private var goals: Set<Goal> = []
    @State private var activity: ActivityLevel? = nil
    @State private var notifications: Bool = false
    @State private var camera: Bool = false

    @State private var heightTouched = false
    @State private var weightTouched = false
    @State private var idealWeightKg: Double? = nil
    @State private var idealWeightTouched = false
    @State private var weightPaceKgPerWeek: Double = 0

    var body: some View {
        ZStack {
            VStack {
                if step > 0 {
                    HStack(spacing: 6) {
                        ForEach(0..<7, id: \.self) { i in
                            Capsule()
                                .fill(i <= step ? Theme.accent : Theme.line)
                                .frame(height: 3)
                                .animation(.smooth, value: step)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 6)
                }
                Spacer(minLength: 0)
            }

            Group {
                switch step {
                case 0: welcome
                case 1: personal
                case 2: bodyDims
                case 3: idealWeightStep
                case 4: goalsStep
                case 5: activityStep
                default: permissionsStep
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 30)
            .padding(.top, 60)
            .id(step)
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .move(edge: .trailing)).combined(with: .scale(scale: 0.98)),
                removal: .opacity.combined(with: .move(edge: .leading))
            ))
        }
        .animation(.smooth(duration: 0.5), value: step)
    }

    // MARK: - Steps

    private var welcome: some View {
        VStack(spacing: 0) {
            Spacer()
            AscendMark(size: 110).padding(.bottom, 28)
            Text("Ascend Life")
                .font(.system(size: 38, weight: .semibold)).tracking(6)
                .foregroundStyle(Theme.textPrimary)
                .blurFadeIn(delay: 0.15)
            Text("An operating system for self-improvement")
                .font(.system(size: 14, weight: .medium)).tracking(1)
                .foregroundStyle(Theme.textSecondary)
                .padding(.top, 10)
                .blurFadeIn(delay: 0.35)
            Text("Measure. Track. Evolve your physique,\nnutrition, and aesthetics.")
                .font(.aetherBody).multilineTextAlignment(.center)
                .foregroundStyle(Theme.textTertiary)
                .padding(.top, 22)
                .blurFadeIn(delay: 0.55)

            Spacer()

            VStack(spacing: 12) {
                SignInWithAppleButton(.continue, onRequest: { req in
                    req.requestedScopes = [.fullName, .email]
                }, onCompletion: { result in
                    handleApple(result: result)
                })
                .signInWithAppleButtonStyle(.white)
                .frame(height: 54)
                .clipShape(.rect(cornerRadius: 16))

                GhostButton(title: "Continue as Guest") {
                    advance()
                }

                Text("By continuing, you accept that Ascend Life is an aid, not medical advice.")
                    .font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center).padding(.top, 6)
            }
            .blurFadeIn(delay: 0.75)
        }
    }

    private var personal: some View {
        VStack(alignment: .leading, spacing: 22) {
            stepHeader(title: "About you", caption: "These numbers calibrate your engine.")

            if !signedInWithApple {
                VStack(alignment: .leading, spacing: 8) {
                    fieldLabel("Name")
                    TextField("Enter your name", text: $name)
                        .textInputAutocapitalization(.words)
                        .font(.system(size: 17, weight: .semibold))
                        .padding(.horizontal, 16).frame(height: 52)
                        .glassCard(radius: 14)
                }
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(Theme.good)
                    Text("Signed in with Apple")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                }
                .padding(.horizontal, 14).frame(height: 44)
                .glassCard(radius: 12)
            }

            VStack(alignment: .leading, spacing: 8) {
                fieldLabel("Age")
                HStack {
                    Text(age.map { "\($0) years" } ?? "Tap to set")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(age == nil ? Theme.textTertiary : Theme.textPrimary)
                        .contentTransition(.numericText())
                        .monospacedDigit()
                    Spacer()
                    Stepper("", value: Binding(
                        get: { age ?? 24 },
                        set: { age = $0 }
                    ), in: 14...90)
                    .labelsHidden()
                }
                .padding(.horizontal, 16).frame(height: 52)
                .glassCard(radius: 14)
            }

            VStack(alignment: .leading, spacing: 8) {
                fieldLabel("Sex")
                HStack(spacing: 10) {
                    ForEach(Sex.allCases) { s in
                        let on = sex == s
                        Button {
                            Haptics.tap()
                            withAnimation(.spring) { sex = s }
                        } label: {
                            Text(s.rawValue)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(on ? Theme.bg : Theme.textPrimary)
                                .frame(maxWidth: .infinity).frame(height: 48)
                                .background {
                                    if on {
                                        RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.9))
                                    } else {
                                        RoundedRectangle(cornerRadius: 12).fill(Theme.surface.opacity(0.5))
                                    }
                                }
                                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.lineStrong, lineWidth: 0.6))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Spacer(minLength: 0)
            primaryNext(enabled: personalValid)
        }
    }

    private var personalValid: Bool {
        let nameOk = signedInWithApple || !name.trimmingCharacters(in: .whitespaces).isEmpty
        return nameOk && age != nil && sex != nil
    }

    private var bodyDims: some View {
        VStack(alignment: .leading, spacing: 22) {
            stepHeader(title: "Body dimensions", caption: "Used for calorie + macro targeting.")

            // Units selector (metric vs imperial).
            VStack(alignment: .leading, spacing: 8) {
                fieldLabel("Units")
                HStack(spacing: 10) {
                    ForEach(UnitSystem.allCases) { u in
                        let on = unitSystem == u
                        Button {
                            Haptics.tap()
                            withAnimation(.spring) { unitSystem = u }
                        } label: {
                            VStack(spacing: 2) {
                                Text(u.rawValue)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(on ? Theme.bg : Theme.textPrimary)
                                Text(u == .metric ? "cm · kg · kcal" : "ft/in · lb · cal")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(on ? Theme.bg.opacity(0.7) : Theme.textTertiary)
                            }
                            .frame(maxWidth: .infinity).frame(height: 52)
                            .background {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(on ? .white.opacity(0.9) : Theme.surface.opacity(0.5))
                            }
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.lineStrong, lineWidth: 0.6))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                fieldLabel("Height")
                HStack {
                    Text(heightTouched ? unitSystem.formatHeight(cm: heightCm ?? 175) : "—")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(heightTouched ? Theme.textPrimary : Theme.textTertiary)
                        .contentTransition(.numericText())
                        .monospacedDigit()
                    Spacer()
                }
                .padding(.horizontal, 16).frame(height: 52)
                .glassCard(radius: 14)
                Slider(value: Binding(
                    get: { heightCm ?? 175 },
                    set: { heightCm = $0; heightTouched = true }
                ), in: 140...210, step: 1)
                .tint(Theme.accent)
            }

            VStack(alignment: .leading, spacing: 8) {
                fieldLabel("Weight")
                HStack {
                    Text(weightTouched ? unitSystem.formatWeight(kg: weightKg ?? 72) : "—")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(weightTouched ? Theme.textPrimary : Theme.textTertiary)
                        .contentTransition(.numericText())
                        .monospacedDigit()
                    Spacer()
                }
                .padding(.horizontal, 16).frame(height: 52)
                .glassCard(radius: 14)
                Slider(value: Binding(
                    get: { weightKg ?? 72 },
                    set: { weightKg = $0; weightTouched = true }
                ), in: 40...160, step: 0.5)
                .tint(Theme.accent)
            }

            Spacer(minLength: 0)
            primaryNext(enabled: heightTouched && weightTouched)
        }
    }

    // MARK: - Ideal weight + pace

    private var idealWeightStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            stepHeader(title: "Target physique",
                       caption: "Where do you want to land, and how fast?")

            VStack(alignment: .leading, spacing: 8) {
                fieldLabel("Ideal Weight")
                HStack {
                    Text(idealWeightTouched
                         ? unitSystem.formatWeight(kg: idealWeightKg ?? (weightKg ?? 72))
                         : "—")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(idealWeightTouched ? Theme.textPrimary : Theme.textTertiary)
                        .contentTransition(.numericText())
                        .monospacedDigit()
                    Spacer()
                    if idealWeightTouched, let target = idealWeightKg, let current = weightKg {
                        Text(directionLabel(current: current, target: target))
                            .font(.system(size: 11, weight: .semibold)).tracking(1.5)
                            .foregroundStyle(Theme.accentGlow)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Theme.accent.opacity(0.18)))
                    }
                }
                .padding(.horizontal, 16).frame(height: 52)
                .glassCard(radius: 14)
                Slider(value: Binding(
                    get: { idealWeightKg ?? (weightKg ?? 72) },
                    set: { idealWeightKg = $0; idealWeightTouched = true; syncPaceSign() }
                ), in: 40...160, step: 0.5)
                .tint(Theme.accent)
            }

            VStack(alignment: .leading, spacing: 8) {
                fieldLabel("Pace")
                let direction = paceDirection
                HStack(spacing: 10) {
                    ForEach(paceOptions(for: direction), id: \.kg) { opt in
                        let on = abs(weightPaceKgPerWeek - opt.kg) < 0.001
                        Button {
                            Haptics.tap()
                            withAnimation(.spring) { weightPaceKgPerWeek = opt.kg }
                        } label: {
                            VStack(spacing: 2) {
                                Text(opt.title)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(on ? Theme.bg : Theme.textPrimary)
                                Text(opt.subtitle(unit: unitSystem))
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(on ? Theme.bg.opacity(0.7) : Theme.textTertiary)
                            }
                            .frame(maxWidth: .infinity).frame(height: 56)
                            .background {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(on ? .white.opacity(0.9) : Theme.surface.opacity(0.5))
                            }
                            .overlay(RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(Theme.lineStrong, lineWidth: 0.6))
                        }
                        .buttonStyle(.plain)
                    }
                }

                if let weeks = estimatedWeeks {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)
                        Text("Estimated \(weeks) week\(weeks == 1 ? "" : "s") to reach your target")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .padding(.top, 6)
                }
            }

            Spacer(minLength: 0)
            primaryNext(enabled: idealWeightTouched)
        }
    }

    private enum PaceDirection { case lose, gain, maintain }

    private var paceDirection: PaceDirection {
        guard let target = idealWeightKg, let current = weightKg else { return .maintain }
        if target < current - 0.5 { return .lose }
        if target > current + 0.5 { return .gain }
        return .maintain
    }

    private func directionLabel(current: Double, target: Double) -> String {
        let diff = target - current
        if abs(diff) < 0.5 { return "MAINTAIN" }
        let absStr = unitSystem.formatWeight(kg: abs(diff))
        return diff < 0 ? "↓ \(absStr)" : "↑ \(absStr)"
    }

    private struct PaceOption {
        let title: String
        let kg: Double // signed kg/week
        func subtitle(unit: UnitSystem) -> String {
            if kg == 0 { return "hold" }
            let perWeek = unit.formatWeight(kg: abs(kg))
            return "\(perWeek)/wk"
        }
    }

    private func paceOptions(for dir: PaceDirection) -> [PaceOption] {
        switch dir {
        case .lose:
            return [
                .init(title: "Easy", kg: -0.25),
                .init(title: "Steady", kg: -0.5),
                .init(title: "Aggressive", kg: -0.75)
            ]
        case .gain:
            return [
                .init(title: "Lean", kg: 0.15),
                .init(title: "Steady", kg: 0.30),
                .init(title: "Bulk", kg: 0.50)
            ]
        case .maintain:
            return [.init(title: "Maintain", kg: 0)]
        }
    }

    private func syncPaceSign() {
        // Snap pace to the new direction so an old "lose" selection doesn't
        // linger after the user swings ideal weight above current.
        switch paceDirection {
        case .lose:
            if weightPaceKgPerWeek >= 0 { weightPaceKgPerWeek = -0.5 }
        case .gain:
            if weightPaceKgPerWeek <= 0 { weightPaceKgPerWeek = 0.30 }
        case .maintain:
            weightPaceKgPerWeek = 0
        }
    }

    private var estimatedWeeks: Int? {
        guard let target = idealWeightKg, let current = weightKg,
              weightPaceKgPerWeek != 0 else { return nil }
        let diff = target - current
        if (diff > 0 && weightPaceKgPerWeek <= 0) || (diff < 0 && weightPaceKgPerWeek >= 0) {
            return nil
        }
        let weeks = abs(diff / weightPaceKgPerWeek)
        return max(1, Int(weeks.rounded()))
    }

    private var goalsStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            stepHeader(title: "Your direction", caption: "Pick up to three — we adapt.")

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(Goal.allCases) { goal in
                    let on = goals.contains(goal)
                    Button {
                        Haptics.tap()
                        withAnimation(.spring) {
                            if on { goals.remove(goal) }
                            else if goals.count < 3 { goals.insert(goal) }
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            Image(systemName: goal.icon)
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(on ? Theme.accentGlow : Theme.textSecondary)
                            Text(goal.rawValue)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
                        .background {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(on ? Theme.accent.opacity(0.18) : Theme.surface.opacity(0.5))
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(on ? Theme.accent : Theme.lineStrong, lineWidth: on ? 1.2 : 0.6)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer(minLength: 0)
            primaryNext(enabled: !goals.isEmpty)
        }
    }

    private var activityStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            stepHeader(title: "Activity level", caption: "How much do you move on a typical week?")

            VStack(spacing: 12) {
                ForEach(ActivityLevel.allCases) { a in
                    let on = activity == a
                    Button {
                        Haptics.tap()
                        withAnimation(.spring) { activity = a }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(a.rawValue).font(.system(size: 17, weight: .semibold))
                                Text(activityCaption(a))
                                    .font(.aetherBody).foregroundStyle(Theme.textSecondary)
                            }
                            Spacer()
                            ZStack {
                                Circle().strokeBorder(on ? Theme.accent : Theme.lineStrong, lineWidth: 1.2)
                                if on { Circle().fill(Theme.accent).padding(4) }
                            }.frame(width: 22, height: 22)
                        }
                        .padding(16)
                        .glassCard(radius: 16)
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer(minLength: 0)
            primaryNext(enabled: activity != nil)
        }
    }

    private var permissionsStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            stepHeader(title: "Final calibration", caption: "Optional permissions. You can change these later.")

            permissionRow(icon: "camera.fill", title: "Camera & Photos", detail: "Capture scans and meals.", isOn: $camera)
            permissionRow(icon: "bell.badge.fill", title: "Notifications", detail: "Streak reminders, weekly insight.", isOn: $notifications)

            Spacer(minLength: 0)
            PrimaryButton(title: "Begin Optimization", icon: "arrow.right") {
                finish()
            }
        }
    }

    // MARK: - Helpers

    private func stepHeader(title: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.aetherTitle).foregroundStyle(Theme.textPrimary)
                .blurFadeIn(delay: 0.05)
            Text(caption).font(.aetherBody).foregroundStyle(Theme.textSecondary)
                .blurFadeIn(delay: 0.15)
        }
        .padding(.top, 8)
    }

    private func fieldLabel(_ s: String) -> some View {
        Text(s.uppercased()).font(.system(size: 11, weight: .semibold)).tracking(2)
            .foregroundStyle(Theme.textTertiary)
    }

    private func primaryNext(enabled: Bool = true) -> some View {
        PrimaryButton(title: step >= 5 ? "Continue" : "Next", icon: "arrow.right") {
            if enabled { advance() }
        }
        .opacity(enabled ? 1 : 0.5)
        .disabled(!enabled)
    }

    private func activityCaption(_ a: ActivityLevel) -> String {
        switch a {
        case .sedentary: "Mostly seated, light walking."
        case .active:    "Several training sessions per week."
        case .athlete:   "Daily training, high output."
        }
    }

    private func permissionRow(icon: String, title: String, detail: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(Theme.accent.opacity(0.18))
                Image(systemName: icon).foregroundStyle(Theme.accentGlow)
            }.frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.aetherHeadline)
                Text(detail).font(.aetherBody).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Toggle("", isOn: isOn).labelsHidden().tint(Theme.accent)
        }
        .padding(16)
        .glassCard(radius: 16)
    }

    private func advance() {
        Haptics.soft()
        withAnimation { step += 1 }
    }

    private func handleApple(result: Result<ASAuthorization, Error>) {
        guard case .success(let auth) = result,
              let cred = auth.credential as? ASAuthorizationAppleIDCredential else {
            advance(); return
        }
        if let n = cred.fullName {
            let formatter = PersonNameComponentsFormatter()
            let nm = formatter.string(from: n)
            if !nm.isEmpty { name = nm }
        }
        if let e = cred.email, !e.isEmpty { email = e }
        appleUserId = cred.user
        signedInWithApple = true
        // Capture the authorizationCode so we can revoke server-side on delete.
        let authCode: String? = {
            guard let data = cred.authorizationCode else { return nil }
            return String(data: data, encoding: .utf8)
        }()
        // Persist immediately — Apple only returns name/email on first sign-in.
        AuthService.shared.store(
            userId: cred.user,
            name: name.isEmpty ? nil : name,
            email: email,
            authorizationCode: authCode
        )
        if name.trimmingCharacters(in: .whitespaces).isEmpty,
           let cached = AuthService.shared.cachedName, !cached.isEmpty {
            name = cached
        }
        if email == nil { email = AuthService.shared.cachedEmail }
        Haptics.success()
        advance()
    }

    private func requestNotifications() {
        Task { await NotificationService.shared.requestAuthorization() }
    }

    private func finish() {
        let finalName = name.trimmingCharacters(in: .whitespaces).isEmpty ? "Athlete" : name
        let finalAge = age ?? 24
        let finalSex = sex ?? .male
        let finalHeight = heightCm ?? 175
        let finalWeight = weightKg ?? 72
        let finalActivity = activity ?? .active

        let finalIdealWeight = idealWeightKg ?? 0
        let finalPace = weightPaceKgPerWeek

        if let existing {
            existing.name = finalName
            existing.ageValue = finalAge
            existing.sexRaw = finalSex.rawValue
            existing.heightCm = finalHeight
            existing.weightKg = finalWeight
            existing.goalsRaw = goals.map { $0.rawValue }
            existing.activityRaw = finalActivity.rawValue
            existing.unitSystemRaw = unitSystem.rawValue
            existing.idealWeightKg = finalIdealWeight
            existing.weightPaceKgPerWeek = finalPace
            existing.onboarded = true
            if let appleUserId { existing.appleUserId = appleUserId }
            if let email { existing.email = email }
        } else {
            let u = UserProfile(
                name: finalName,
                ageValue: finalAge,
                sexRaw: finalSex.rawValue,
                heightCm: finalHeight,
                weightKg: finalWeight,
                goalsRaw: goals.map { $0.rawValue },
                activityRaw: finalActivity.rawValue,
                onboarded: true,
                appleUserId: appleUserId,
                email: email,
                unitSystemRaw: unitSystem.rawValue,
                idealWeightKg: finalIdealWeight,
                weightPaceKgPerWeek: finalPace
            )
            ctx.insert(u)
        }
        try? ctx.save()
        if notifications { requestNotifications() }
        Haptics.success()
    }
}
