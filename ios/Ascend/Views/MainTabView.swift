import SwiftUI
import SwiftData

struct MainTabView: View {
    let user: UserProfile
    @Environment(\.modelContext) private var ctx
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tab: AppTab = .home

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch tab {
                case .home:        HomeView(user: user)
                case .physique:    PhysiqueView(user: user)
                case .cal:         CalAIView(user: user)
                case .psl:         PSLView(user: user)
                case .ai:          CoachChatView(user: user)
                case .circles:     CirclesView(user: user)
                }
            }
            .id(tab)
            .transition(
                AnyTransition.asymmetric(
                    insertion: AnyTransition.opacity.combined(with: .scale(scale: 0.985)),
                    removal: AnyTransition.opacity.combined(with: .scale(scale: 1.02))
                )
            )

            AscendTabBar(selected: $tab)
                .padding(.horizontal, 18)
                .padding(.bottom, 6)
        }
        .animation(reduceMotion ? .easeOut(duration: 0.2) : Motion.tab, value: tab)
        .task {
            WidgetSync.push(user: user, context: ctx)
        }
        .onChange(of: tab) { _, _ in
            WidgetSync.push(user: user, context: ctx)
        }
        .onReceive(NotificationCenter.default.publisher(for: .switchTab)) { note in
            if let t = note.object as? AppTab {
                withAnimation(Motion.tab) { tab = t }
            }
        }
    }
}

enum AppTab: String, CaseIterable {
    case home, physique, cal, psl, ai, circles
    var icon: String {
        switch self {
        case .home:        "square.grid.2x2"
        case .physique:    "figure.stand"
        case .cal:         "fork.knife"
        case .psl:         "face.smiling"
        case .ai:          "sparkles"
        case .circles:     "person.2.fill"
        }
    }
    var title: String {
        switch self {
        case .home: "Home"
        case .physique: "Physique"
        case .cal: "Cal AI"
        case .psl: "PSL"
        case .ai: "Coach"
        case .circles: "Circles"
        }
    }
}

struct AscendTabBar: View {
    @Binding var selected: AppTab
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AppTab.allCases, id: \.self) { t in
                Button {
                    Haptics.soft()
                    withAnimation(Motion.snappy) { selected = t }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: t.icon)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(selected == t ? Theme.textPrimary : Theme.textTertiary)
                            .symbolEffect(.bounce, value: selected == t)
                        Text(t.title)
                            .font(.system(size: 9, weight: .semibold))
                            .tracking(0.6)
                            .foregroundStyle(selected == t ? Theme.textPrimary : Theme.textTertiary)
                    }
                    .frame(maxWidth: .infinity).frame(height: 56)
                    .background {
                        if selected == t {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Theme.accent.opacity(0.16))
                                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.accent.opacity(0.5), lineWidth: 0.6))
                                .matchedGeometryEffect(id: "tab", in: ns)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color.black.opacity(0.35))
                )
        }
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Theme.lineStrong, lineWidth: 0.6))
        .softShadow()
    }
}
