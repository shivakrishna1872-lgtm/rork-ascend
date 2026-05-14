import SwiftUI
import SwiftData

@main
struct AscendApp: App {
    @State private var appState = AppState()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            UserProfile.self,
            PhysiqueScanRecord.self,
            FaceScanRecord.self,
            MealEntry.self,
            Achievement.self,
            FriendGroup.self,
            Friend.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            // Recover from schema migration failure by wiping the store.
            let fallback = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            return (try? ModelContainer(for: schema, configurations: [fallback]))
                ?? { fatalError("ModelContainer failed: \(error)") }()
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
        .modelContainer(sharedModelContainer)
    }
}
