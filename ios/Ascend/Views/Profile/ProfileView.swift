import SwiftUI
import SwiftData
import UserNotifications
import UIKit

struct ProfileView: View {
    let user: UserProfile
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var ctx
    @Query(sort: \PhysiqueScanRecord.date, order: .reverse) private var scans: [PhysiqueScanRecord]
    @Query(sort: \MealEntry.date, order: .reverse) private var meals: [MealEntry]
    @Query(sort: \FaceScanRecord.date, order: .reverse) private var faces: [FaceScanRecord]

    @State private var notifStatus: UNAuthorizationStatus = .notDetermined
    @State private var rescheduleConfirmation: String? = nil
    @State private var showDeleteConfirm: Bool = false
    @State private var deleting: Bool = false

    var body: some View {
        ZStack {
            AmbientBackground().ignoresSafeArea()
            ScrollView {
                VStack(spacing: 18) {
                    profileHeader.blurFadeIn(delay: 0.0)
                    accountSection.blurFadeIn(delay: 0.06)
                    statsCard.blurFadeIn(delay: 0.12)
                    personalitySection.blurFadeIn(delay: 0.18)
                    accessibilitySection.blurFadeIn(delay: 0.24)
                    notificationsSection.blurFadeIn(delay: 0.30)
                    aboutSection.blurFadeIn(delay: 0.36)
                    resetButton.blurFadeIn(delay: 0.42)
                    deleteAccountSection.blurFadeIn(delay: 0.48)
                }
                .padding(.horizontal, 20).padding(.top, 18)
            }
            .scrollIndicators(.hidden)
            .safeAreaPadding(.bottom, 40)
        }
        .task { await refreshNotifStatus() }
        .alert("Delete Account?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { performDelete() }
        } message: {
            Text("Are you sure you want to permanently delete your account? This removes all of your scans, meals, streaks, and Apple sign-in. This cannot be undone.")
        }
    }

    // MARK: - Account Settings (name / email / sign-in source)

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Account Settings")
            VStack(spacing: 0) {
                accountRow(label: "Name", value: displayName, icon: "person.fill")
                Divider().overlay(Theme.line)
                accountRow(label: "Email", value: displayEmail, icon: "envelope.fill")
                Divider().overlay(Theme.line)
                accountRow(label: "Sign-in", value: signInLabel, icon: "key.fill")
            }
            .padding(16)
            .glassCard(radius: 18)
        }
    }

    private var displayName: String {
        if !user.name.isEmpty && user.name != "Athlete" { return user.name }
        return AuthService.shared.cachedName ?? user.name
    }

    private var displayEmail: String {
        user.email ?? AuthService.shared.cachedEmail ?? "Not provided"
    }

    private var signInLabel: String {
        (user.appleUserId != nil || AuthService.shared.isSignedIn) ? "Apple" : "Guest"
    }

    private func accountRow(label: String, value: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.accentGlow)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(label.uppercased())
                    .font(.system(size: 9, weight: .semibold)).tracking(1.4)
                    .foregroundStyle(Theme.textTertiary)
                Text(value)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
    }

    // MARK: - Delete Account (inline, no extra navigation)

    private var deleteAccountSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Danger Zone")
            Button {
                Haptics.warning()
                showDeleteConfirm = true
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(Theme.bad.opacity(0.18))
                        Image(systemName: "trash.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Theme.bad)
                    }
                    .frame(width: 36, height: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(deleting ? "Deleting…" : "Delete Account")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.bad)
                        Text("Permanently remove your account and all data.")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    Spacer()
                    if deleting {
                        ProgressView().tint(Theme.bad).scaleEffect(0.8)
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.bad.opacity(0.7))
                    }
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 16).fill(Theme.bad.opacity(0.08)))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.bad.opacity(0.45), lineWidth: 0.8))
            }
            .buttonStyle(.plain)
            .disabled(deleting)
        }
    }

    private func performDelete() {
        guard !deleting else { return }
        deleting = true
        Haptics.warning()
        // 1. Wipe every SwiftData record owned by this user.
        do {
            try ctx.delete(model: PhysiqueScanRecord.self)
            try ctx.delete(model: FaceScanRecord.self)
            try ctx.delete(model: MealEntry.self)
            try ctx.delete(model: Achievement.self)
            try ctx.delete(model: FriendGroup.self)
            try ctx.delete(model: Friend.self)
            try ctx.delete(model: UserProfile.self)
            try ctx.save()
        } catch {
            // Best-effort cleanup; still proceed to sign-out so the user is never stuck.
        }
        // 2. Cancel scheduled notifications & shared widget state.
        NotificationService.shared.cancelAll()
        // 3. Revoke Apple credential cache (full delete, not deactivate).
        AuthService.shared.signOut()
        deleting = false
        // 4. Drop back to the login / onboarding flow.
        dismiss()
    }

    private func refreshNotifStatus() async {
        notifStatus = await NotificationService.shared.currentStatus
    }

    private var notificationsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Notifications")
            VStack(spacing: 0) {
                Toggle(isOn: Binding(
                    get: { notifStatus == .authorized || notifStatus == .provisional },
                    set: { v in handleToggle(enable: v) }
                )) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Daily Reminders").font(.system(size: 15, weight: .medium))
                            Text(notifSubtitle)
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.textTertiary)
                        }
                    } icon: {
                        Image(systemName: "bell.fill").foregroundStyle(Theme.accent)
                    }
                }
                .tint(Theme.accent)
                .padding(.vertical, 8)

                Divider().overlay(Theme.line)

                Button {
                    Haptics.tap()
                    Task {
                        let status = await NotificationService.shared.currentStatus
                        if status == .authorized || status == .provisional {
                            NotificationService.shared.scheduleDefaults()
                            withAnimation(.spring) {
                                rescheduleConfirmation = "Reminders rescheduled for 8:30 AM and 9:00 PM."
                            }
                            Haptics.success()
                            try? await Task.sleep(for: .seconds(3))
                            withAnimation(.spring) { rescheduleConfirmation = nil }
                        } else {
                            openSystemSettings()
                        }
                    }
                } label: {
                    HStack {
                        Label("Reschedule Reminders", systemImage: "arrow.clockwise")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .glassCard(radius: 16)

            if let msg = rescheduleConfirmation {
                Text(msg)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.good)
                    .padding(.horizontal, 4)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var notifSubtitle: String {
        switch notifStatus {
        case .authorized, .provisional, .ephemeral: return "8:30 AM check-in · 9:00 PM nudge"
        case .denied: return "Disabled in iOS Settings"
        case .notDetermined: return "Tap to enable daily reminders"
        @unknown default: return ""
        }
    }

    private func handleToggle(enable: Bool) {
        Haptics.tap()
        Task {
            if enable {
                let status = await NotificationService.shared.currentStatus
                if status == .denied {
                    openSystemSettings()
                } else {
                    _ = await NotificationService.shared.requestAuthorization()
                }
            } else {
                NotificationService.shared.cancelAll()
            }
            await refreshNotifStatus()
        }
    }

    private func openSystemSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    private var profileHeader: some View {
        VStack(spacing: 14) {
            TierEmblem(tier: user.tier, size: 72)
                .ambientFloat(amplitude: 3, duration: 3.2)
            VStack(spacing: 4) {
                Text(user.name).font(.aetherTitle).foregroundStyle(Theme.textPrimary)
                Text("\(user.tier.title) · \(user.xp) XP")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(user.tier.color)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    private var statsCard: some View {
        VStack(spacing: 14) {
            HStack(spacing: 0) {
                stat("Streak", "\(user.streak)", "flame.fill", Theme.warn)
                divider
                stat("Scans", "\(scans.count)", "viewfinder", Theme.accent)
                divider
                stat("Meals", "\(meals.count)", "fork.knife", Theme.good)
                divider
                stat("Faces", "\(faces.count)", "face.smiling", Theme.elite)
            }
        }
        .padding(16)
        .glassCard(radius: 20)
    }

    private var divider: some View {
        Rectangle().fill(Theme.line).frame(width: 0.5, height: 36)
    }

    private func stat(_ label: String, _ value: String, _ icon: String, _ tint: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 13, weight: .bold)).foregroundStyle(tint)
            Text(value).font(.system(size: 19, weight: .semibold, design: .rounded))
            Text(label.uppercased()).font(.system(size: 9, weight: .semibold)).tracking(1.2)
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private var personalitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "AI Personality")
            HStack(spacing: 8) {
                ForEach(AIPersonality.allCases) { p in
                    let on = user.personality == p
                    Button {
                        Haptics.tap()
                        withAnimation(.spring) {
                            user.personalityRaw = p.rawValue
                            try? ctx.save()
                        }
                    } label: {
                        Text(p.rawValue)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(on ? Theme.bg : Theme.textPrimary)
                            .frame(maxWidth: .infinity).frame(height: 44)
                            .background(RoundedRectangle(cornerRadius: 12).fill(on ? .white.opacity(0.9) : Theme.surface.opacity(0.5)))
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.lineStrong, lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var accessibilitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Accessibility")
            VStack(spacing: 0) {
                Toggle(isOn: Binding(get: { user.reduceMotion }, set: { v in
                    user.reduceMotion = v; try? ctx.save()
                })) {
                    Label("Reduce Motion", systemImage: "wand.and.stars.inverse")
                        .font(.system(size: 15, weight: .medium))
                }
                .tint(Theme.accent)
                .padding(.vertical, 8)
            }
            .padding(.horizontal, 16).padding(.vertical, 6)
            .glassCard(radius: 16)

            Text("Dynamic Type, VoiceOver, and high-contrast colors are honored throughout the app.")
                .font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
                .padding(.horizontal, 4)
        }
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "About")
            VStack(alignment: .leading, spacing: 10) {
                row("Age", "\(user.ageValue)")
                Divider().overlay(Theme.line)
                row("Height", "\(Int(user.heightCm)) cm")
                Divider().overlay(Theme.line)
                row("Weight", String(format: "%.1f kg", user.weightKg))
                Divider().overlay(Theme.line)
                row("Calorie Target", "\(user.dailyCalorieTarget) kcal")
                Divider().overlay(Theme.line)
                row("Goals", user.goals.map { $0.rawValue }.joined(separator: ", "))
            }
            .padding(16)
            .glassCard(radius: 18)
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(value).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.textPrimary)
        }
    }

    private var resetButton: some View {
        Button {
            Haptics.warning()
            user.onboarded = false
            try? ctx.save()
            dismiss()
        } label: {
            Text("Restart Onboarding")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.bad)
                .frame(maxWidth: .infinity).frame(height: 44)
                .glassCard(radius: 12)
        }
        .buttonStyle(.plain)
    }
}
