import WidgetKit
import SwiftUI

@main
nonisolated struct AetherWidgetsBundle: WidgetBundle {
    var body: some Widget {
        CalAIWidget()
        PhysiqueWidget()
        PhysiqueRankWidget()
        PSLRankWidget()
        CombinedWidget()
    }
}
