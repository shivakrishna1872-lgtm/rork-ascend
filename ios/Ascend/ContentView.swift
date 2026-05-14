import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(AppState.self) private var app
    @Query private var users: [UserProfile]

    var body: some View {
        ZStack {
            AmbientBackground().ignoresSafeArea()

            if let user = users.first, user.onboarded {
                MainTabView(user: user)
                    .transition(.opacity.combined(with: .blurReplace))
            } else {
                OnboardingFlow(existing: users.first)
                    .transition(.opacity.combined(with: .blurReplace))
            }

            // Tier promotion overlay
            if let new = app.showTierPromotion {
                TierPromotionView(from: app.lastTier, to: new) {
                    withAnimation(.smooth(duration: 0.4)) { app.showTierPromotion = nil }
                }
                .transition(.opacity)
                .zIndex(99)
            }
        }
        .animation(.smooth(duration: 0.5), value: users.first?.onboarded ?? false)
        .animation(.smooth(duration: 0.45), value: app.showTierPromotion)
    }
}

#Preview {
    RootView()
        .environment(AppState())
        .modelContainer(for: [UserProfile.self, PhysiqueScanRecord.self, FaceScanRecord.self, MealEntry.self, Achievement.self, FriendGroup.self, Friend.self], inMemory: true)
}
