import WidgetKit
import SwiftUI

// MARK: - Shared keys (mirror of WidgetSync.Key in main app)

nonisolated enum SharedKey {
    static let appGroupID = "group.app.rork.5dm6zbnyue71m6ouijlfh.shared"
    // Cal AI
    static let caloriesEaten = "cal.eaten"
    static let caloriesTarget = "cal.target"
    static let proteinEaten = "cal.proteinEaten"
    static let proteinTarget = "cal.proteinTarget"
    static let carbsEaten = "cal.carbsEaten"
    static let carbsTarget = "cal.carbsTarget"
    static let fatsEaten = "cal.fatsEaten"
    static let fatsTarget = "cal.fatsTarget"
    static let hydration = "cal.hydration"
    static let calorieHistory = "cal.history7"
    static let mealsLogged = "cal.mealsToday"
    // Physique
    static let physiqueScore = "phys.score"
    static let physiqueDate = "phys.date"
    static let symmetryScore = "phys.symmetry"
    static let muscularityScore = "phys.muscle"
    static let conditioningScore = "phys.conditioning"
    static let bodyFat = "phys.bf"
    static let bodyFatPrev = "phys.bfPrev"
    static let physiqueHistory = "phys.history6"
    static let physiqueCount = "phys.count"
    // PSL
    static let pslScore = "psl.score"
    static let pslDate = "psl.date"
    static let pslSymmetry = "psl.symmetry"
    static let pslJawline = "psl.jawline"
    static let pslGlowUp = "psl.glowUp"
    static let pslHistory = "psl.history6"
    static let pslCount = "psl.count"
    // Identity
    static let userName = "user.name"
    static let xp = "user.xp"
    static let tierRaw = "user.tier"
    static let tierXPFloor = "user.tierFloor"
    static let tierXPCeil = "user.tierCeil"
    static let streak = "user.streak"
    static let streakHistory = "user.streak7"
    // Leaderboard
    static let groupName = "lb.groupName"
    static let groupRank = "lb.rank"
    static let groupSize = "lb.size"
    static let gapToNextXP = "lb.gapNext"
    static let topThreeNames = "lb.topNames"
    static let topThreeXP = "lb.topXP"
    static let updatedAt = "meta.updatedAt"
}

nonisolated enum WTier: String {
    case bronze, silver, gold, elite, greek
    var title: String {
        switch self {
        case .bronze: "Bronze"; case .silver: "Silver"; case .gold: "Gold"
        case .elite: "Elite"; case .greek: "Greek God"
        }
    }
    var color: Color {
        switch self {
        case .bronze: Color(red: 0.72, green: 0.49, blue: 0.30)
        case .silver: Color(red: 0.78, green: 0.82, blue: 0.86)
        case .gold:   Color(red: 0.92, green: 0.78, blue: 0.40)
        case .elite:  Color(red: 0.58, green: 0.78, blue: 0.94)
        case .greek:  Color(red: 0.96, green: 0.92, blue: 0.78)
        }
    }
    var glyph: String {
        switch self {
        case .bronze: "triangle.fill"; case .silver: "diamond.fill"
        case .gold: "star.fill"; case .elite: "hexagon.fill"
        case .greek: "laurel.leading"
        }
    }
    static func forScore(_ s: Double) -> WTier {
        if s >= 90 { return .greek }
        if s >= 80 { return .elite }
        if s >= 65 { return .gold }
        if s >= 50 { return .silver }
        return .bronze
    }
}

nonisolated enum WTheme {
    static let bg = Color(red: 0.04, green: 0.045, blue: 0.055)
    static let surface = Color(red: 0.11, green: 0.12, blue: 0.14)
    static let textPrimary = Color(red: 0.96, green: 0.97, blue: 0.99)
    static let textSecondary = Color(red: 0.66, green: 0.70, blue: 0.76)
    static let textTertiary = Color(red: 0.44, green: 0.48, blue: 0.54)
    static let line = Color.white.opacity(0.08)
    static let accent = Color(red: 0.45, green: 0.62, blue: 0.82)
    static let good = Color(red: 0.50, green: 0.78, blue: 0.62)
    static let warn = Color(red: 0.92, green: 0.74, blue: 0.42)
}

// MARK: - Entry

nonisolated struct AetherEntry: TimelineEntry {
    let date: Date
    let hasData: Bool

    // Cal AI
    let kcalEaten: Int
    let kcalTarget: Int
    let proteinEaten: Int
    let proteinTarget: Int
    let carbsEaten: Int
    let carbsTarget: Int
    let fatsEaten: Int
    let fatsTarget: Int
    let hydration: Int
    let mealsLogged: Int
    let calorieHistory: [Int]

    // Physique
    let physiqueScore: Double
    let symmetryScore: Double
    let muscularityScore: Double
    let conditioningScore: Double
    let bodyFat: Double
    let bodyFatPrev: Double
    let physiqueHistory: [Double]
    let physiqueCount: Int
    let physiqueDate: Date?

    // PSL
    let pslScore: Double
    let pslSymmetry: Double
    let pslJawline: Double
    let pslGlowUp: Double
    let pslHistory: [Double]
    let pslCount: Int
    let pslDate: Date?

    // Identity
    let userName: String
    let xp: Int
    let tier: WTier
    let tierFloor: Int
    let tierCeil: Int
    let streak: Int
    let streakHistory: [Int]

    // Leaderboard
    let groupName: String
    let rank: Int
    let groupSize: Int
    let gap: Int
    let topNames: [String]
    let topXP: [Int]

    static let placeholder = AetherEntry(
        date: .now, hasData: true,
        kcalEaten: 1240, kcalTarget: 2400,
        proteinEaten: 96, proteinTarget: 160,
        carbsEaten: 140, carbsTarget: 240,
        fatsEaten: 48, fatsTarget: 70,
        hydration: 5, mealsLogged: 3,
        calorieHistory: [1900, 2100, 1800, 2300, 2050, 1750, 1240],
        physiqueScore: 78,
        symmetryScore: 82, muscularityScore: 74, conditioningScore: 71,
        bodyFat: 14.5, bodyFatPrev: 15.4,
        physiqueHistory: [72, 73, 75, 74, 77, 78],
        physiqueCount: 6, physiqueDate: .now,
        pslScore: 76, pslSymmetry: 80, pslJawline: 72, pslGlowUp: 18,
        pslHistory: [70, 71, 73, 72, 75, 76], pslCount: 5, pslDate: .now,
        userName: "Athlete", xp: 1280, tier: .silver,
        tierFloor: 500, tierCeil: 1500, streak: 7,
        streakHistory: [1,1,0,1,1,1,1],
        groupName: "Gym Bros", rank: 2, groupSize: 6, gap: 240,
        topNames: ["Alex", "You", "Maya"], topXP: [1520, 1280, 940]
    )

    static let empty = AetherEntry(
        date: .now, hasData: false,
        kcalEaten: 0, kcalTarget: 2000,
        proteinEaten: 0, proteinTarget: 0,
        carbsEaten: 0, carbsTarget: 0,
        fatsEaten: 0, fatsTarget: 0,
        hydration: 0, mealsLogged: 0,
        calorieHistory: [],
        physiqueScore: 0, symmetryScore: 0, muscularityScore: 0, conditioningScore: 0,
        bodyFat: 0, bodyFatPrev: 0, physiqueHistory: [], physiqueCount: 0, physiqueDate: nil,
        pslScore: 0, pslSymmetry: 0, pslJawline: 0, pslGlowUp: 0,
        pslHistory: [], pslCount: 0, pslDate: nil,
        userName: "", xp: 0, tier: .bronze, tierFloor: 0, tierCeil: 500,
        streak: 0, streakHistory: [0,0,0,0,0,0,0],
        groupName: "", rank: 0, groupSize: 0, gap: 0,
        topNames: [], topXP: []
    )

    nonisolated static func load() -> AetherEntry {
        guard let d = UserDefaults(suiteName: SharedKey.appGroupID),
              d.object(forKey: SharedKey.updatedAt) != nil
        else { return .empty }

        let tierRaw = d.string(forKey: SharedKey.tierRaw) ?? "bronze"
        let calHist = (d.array(forKey: SharedKey.calorieHistory) as? [Int]) ?? []
        let physHist = (d.array(forKey: SharedKey.physiqueHistory) as? [Double]) ?? []
        let pslHist = (d.array(forKey: SharedKey.pslHistory) as? [Double]) ?? []
        let streakHist = (d.array(forKey: SharedKey.streakHistory) as? [Int]) ?? Array(repeating: 0, count: 7)
        let topNames = (d.array(forKey: SharedKey.topThreeNames) as? [String]) ?? []
        let topXP = (d.array(forKey: SharedKey.topThreeXP) as? [Int]) ?? []

        let physTS = d.double(forKey: SharedKey.physiqueDate)
        let pslTS = d.double(forKey: SharedKey.pslDate)

        return AetherEntry(
            date: .now,
            hasData: true,
            kcalEaten: d.integer(forKey: SharedKey.caloriesEaten),
            kcalTarget: max(1, d.integer(forKey: SharedKey.caloriesTarget)),
            proteinEaten: d.integer(forKey: SharedKey.proteinEaten),
            proteinTarget: max(1, d.integer(forKey: SharedKey.proteinTarget)),
            carbsEaten: d.integer(forKey: SharedKey.carbsEaten),
            carbsTarget: max(1, d.integer(forKey: SharedKey.carbsTarget)),
            fatsEaten: d.integer(forKey: SharedKey.fatsEaten),
            fatsTarget: max(1, d.integer(forKey: SharedKey.fatsTarget)),
            hydration: d.integer(forKey: SharedKey.hydration),
            mealsLogged: d.integer(forKey: SharedKey.mealsLogged),
            calorieHistory: calHist,
            physiqueScore: d.double(forKey: SharedKey.physiqueScore),
            symmetryScore: d.double(forKey: SharedKey.symmetryScore),
            muscularityScore: d.double(forKey: SharedKey.muscularityScore),
            conditioningScore: d.double(forKey: SharedKey.conditioningScore),
            bodyFat: d.double(forKey: SharedKey.bodyFat),
            bodyFatPrev: d.double(forKey: SharedKey.bodyFatPrev),
            physiqueHistory: physHist,
            physiqueCount: d.integer(forKey: SharedKey.physiqueCount),
            physiqueDate: physTS > 0 ? Date(timeIntervalSince1970: physTS) : nil,
            pslScore: d.double(forKey: SharedKey.pslScore),
            pslSymmetry: d.double(forKey: SharedKey.pslSymmetry),
            pslJawline: d.double(forKey: SharedKey.pslJawline),
            pslGlowUp: d.double(forKey: SharedKey.pslGlowUp),
            pslHistory: pslHist,
            pslCount: d.integer(forKey: SharedKey.pslCount),
            pslDate: pslTS > 0 ? Date(timeIntervalSince1970: pslTS) : nil,
            userName: d.string(forKey: SharedKey.userName) ?? "",
            xp: d.integer(forKey: SharedKey.xp),
            tier: WTier(rawValue: tierRaw) ?? .bronze,
            tierFloor: d.integer(forKey: SharedKey.tierXPFloor),
            tierCeil: max(1, d.integer(forKey: SharedKey.tierXPCeil)),
            streak: d.integer(forKey: SharedKey.streak),
            streakHistory: streakHist,
            groupName: d.string(forKey: SharedKey.groupName) ?? "",
            rank: d.integer(forKey: SharedKey.groupRank),
            groupSize: d.integer(forKey: SharedKey.groupSize),
            gap: d.integer(forKey: SharedKey.gapToNextXP),
            topNames: topNames,
            topXP: topXP
        )
    }
}

// MARK: - Providers

nonisolated struct AetherProvider: TimelineProvider {
    func placeholder(in context: Context) -> AetherEntry { .placeholder }
    func getSnapshot(in context: Context, completion: @escaping (AetherEntry) -> Void) {
        completion(context.isPreview ? .placeholder : AetherEntry.load())
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<AetherEntry>) -> Void) {
        let entry = AetherEntry.load()
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: .now)!
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

// MARK: - Shared chrome & primitives

nonisolated struct WidgetChrome<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        content()
            .containerBackground(for: .widget) {
                ZStack {
                    WTheme.bg
                    RadialGradient(
                        colors: [WTheme.accent.opacity(0.18), .clear],
                        center: .topLeading, startRadius: 5, endRadius: 220
                    )
                    .blendMode(.plusLighter)
                }
            }
    }
}

nonisolated struct ProgressArc: View {
    var progress: Double
    var color: Color
    var lineWidth: CGFloat = 7
    var body: some View {
        ZStack {
            Circle().stroke(WTheme.line, style: .init(lineWidth: lineWidth))
            Circle()
                .trim(from: 0, to: min(1, max(0, progress)))
                .stroke(color, style: .init(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

nonisolated struct TinyEmblem: View {
    let tier: WTier
    var size: CGFloat = 22
    var body: some View {
        ZStack {
            Circle()
                .fill(
                    AngularGradient(
                        colors: [tier.color.opacity(0.4), tier.color, .white.opacity(0.85), tier.color],
                        center: .center
                    )
                )
                .overlay(Circle().strokeBorder(.white.opacity(0.3), lineWidth: 0.6))
            Image(systemName: tier.glyph)
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(.black.opacity(0.75))
        }
        .frame(width: size, height: size)
    }
}

/// Mini sparkline / bar chart.
nonisolated struct MiniBarChart: View {
    var values: [Double]
    var color: Color
    var highlightLast: Bool = true
    var body: some View {
        GeometryReader { geo in
            let count = max(values.count, 1)
            let maxV = max(values.max() ?? 1, 1)
            let barW = (geo.size.width - CGFloat(count - 1) * 3) / CGFloat(count)
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(Array(values.enumerated()), id: \.offset) { idx, v in
                    let h = max(2, CGFloat(v / maxV) * geo.size.height)
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(highlightLast && idx == values.count - 1 ? color : color.opacity(0.55))
                        .frame(width: barW, height: h)
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
    }
}

nonisolated struct SparkLine: View {
    var values: [Double]
    var color: Color
    var body: some View {
        GeometryReader { geo in
            let count = max(values.count, 1)
            let maxV = values.max() ?? 1
            let minV = values.min() ?? 0
            let span = max(maxV - minV, 1)
            Path { p in
                for (i, v) in values.enumerated() {
                    let x = CGFloat(i) / CGFloat(max(1, count - 1)) * geo.size.width
                    let y = geo.size.height - CGFloat((v - minV) / span) * geo.size.height
                    if i == 0 { p.move(to: CGPoint(x: x, y: y)) }
                    else { p.addLine(to: CGPoint(x: x, y: y)) }
                }
            }
            .stroke(color, style: .init(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
            .shadow(color: color.opacity(0.6), radius: 3)
        }
    }
}

nonisolated struct MicroBar: View {
    let label: String
    let value: Double
    let color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label.uppercased()).font(.system(size: 8, weight: .bold)).tracking(1.2)
                    .foregroundStyle(WTheme.textTertiary)
                Spacer()
                Text("\(Int(value))")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(WTheme.textSecondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(WTheme.line)
                    Capsule().fill(color)
                        .frame(width: max(2, geo.size.width * min(1, value / 100)))
                }
            }.frame(height: 3)
        }
    }
}

nonisolated struct EmptyStateView: View {
    let icon: String
    let title: String
    let subtitle: String
    let tint: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tint)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(WTheme.textPrimary)
            Text(subtitle)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(WTheme.textSecondary)
                .lineLimit(3)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Cal AI widget

nonisolated struct CalAIWidgetView: View {
    var entry: AetherEntry
    @Environment(\.widgetFamily) private var family

    var remaining: Int { max(0, entry.kcalTarget - entry.kcalEaten) }
    var progress: Double { min(1, Double(entry.kcalEaten) / Double(max(1, entry.kcalTarget))) }
    var yesterday: Int { entry.calorieHistory.count >= 2 ? entry.calorieHistory[entry.calorieHistory.count - 2] : 0 }
    var delta: Int { entry.kcalEaten - yesterday }
    var hasMeals: Bool { entry.mealsLogged > 0 || entry.kcalEaten > 0 }

    var body: some View {
        WidgetChrome {
            switch family {
            case .systemSmall: small
            case .accessoryCircular: lockCircular
            case .accessoryRectangular: lockRect
            case .accessoryInline: Text(hasMeals ? "\(remaining) kcal left" : "Log your first meal")
            default: medium
            }
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("CAL AI").font(.system(size: 9, weight: .bold)).tracking(1.6)
                    .foregroundStyle(WTheme.textTertiary)
                Spacer()
                Image(systemName: "fork.knife").font(.system(size: 10, weight: .bold))
                    .foregroundStyle(WTheme.accent)
            }
            if hasMeals {
                ZStack {
                    ProgressArc(progress: progress, color: WTheme.accent, lineWidth: 8)
                    VStack(spacing: 0) {
                        Text("\(remaining)")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(WTheme.textPrimary)
                        Text("LEFT").font(.system(size: 7, weight: .bold)).tracking(1.5)
                            .foregroundStyle(WTheme.textTertiary)
                    }
                }
                .frame(maxWidth: .infinity)
                HStack(spacing: 3) {
                    Image(systemName: delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 8, weight: .bold))
                    Text("\(abs(delta)) vs yesterday")
                        .font(.system(size: 9, weight: .semibold))
                }
                .foregroundStyle(delta == 0 ? WTheme.textTertiary : (delta > 0 ? WTheme.warn : WTheme.good))
            } else {
                EmptyStateView(icon: "fork.knife.circle",
                               title: "Log your first meal",
                               subtitle: "Cal AI estimates calories and macros instantly.",
                               tint: WTheme.accent)
            }
        }
        .widgetURL(URL(string: "aether://cal"))
    }

    private var medium: some View {
        HStack(spacing: 14) {
            ZStack {
                ProgressArc(progress: progress, color: WTheme.accent, lineWidth: 9)
                VStack(spacing: 0) {
                    Text("\(remaining)")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(WTheme.textPrimary)
                    Text("LEFT").font(.system(size: 7, weight: .bold)).tracking(1.5)
                        .foregroundStyle(WTheme.textTertiary)
                }
            }
            .frame(width: 86, height: 86)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("CAL AI · TODAY").font(.system(size: 8, weight: .bold)).tracking(1.6)
                        .foregroundStyle(WTheme.textTertiary)
                    Spacer()
                    if entry.hydration > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "drop.fill").font(.system(size: 8, weight: .bold))
                                .foregroundStyle(WTheme.accent)
                            Text("\(entry.hydration)").font(.system(size: 9, weight: .semibold, design: .rounded))
                                .foregroundStyle(WTheme.textSecondary)
                        }
                    }
                }
                if hasMeals {
                    macroRow(label: "P", value: entry.proteinEaten, target: entry.proteinTarget,
                             color: Color(red: 0.58, green: 0.78, blue: 0.94))
                    macroRow(label: "C", value: entry.carbsEaten, target: entry.carbsTarget,
                             color: Color(red: 0.92, green: 0.74, blue: 0.42))
                    macroRow(label: "F", value: entry.fatsEaten, target: entry.fatsTarget,
                             color: Color(red: 0.55, green: 0.74, blue: 0.62))

                    if !entry.calorieHistory.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("7-DAY KCAL").font(.system(size: 7, weight: .bold)).tracking(1.2)
                                .foregroundStyle(WTheme.textTertiary)
                            MiniBarChart(values: entry.calorieHistory.map { Double($0) },
                                         color: WTheme.accent)
                                .frame(height: 18)
                        }
                    }
                } else {
                    Text("No meals logged today").font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(WTheme.textPrimary)
                    Text("Tap to add your first meal and unlock today's macros.")
                        .font(.system(size: 10)).foregroundStyle(WTheme.textSecondary)
                        .lineLimit(3)
                }
            }
            Spacer(minLength: 0)
        }
        .widgetURL(URL(string: "aether://cal"))
    }

    private func macroRow(label: String, value: Int, target: Int, color: Color) -> some View {
        let p = min(1, Double(value) / Double(max(1, target)))
        return HStack(spacing: 8) {
            Text(label).font(.system(size: 9, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 10, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(WTheme.line)
                    Capsule().fill(color).frame(width: max(2, geo.size.width * p))
                }
            }.frame(height: 4)
            Text("\(value)g")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(WTheme.textSecondary)
                .frame(width: 32, alignment: .trailing)
        }
    }

    private var lockCircular: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Text("\(remaining)")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                Text("kcal").font(.system(size: 8, weight: .semibold))
            }
        }
    }

    private var lockRect: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Cal AI").font(.system(size: 11, weight: .bold))
            if hasMeals {
                Text("\(remaining) kcal remaining").font(.system(size: 12, weight: .semibold))
                Text("P \(entry.proteinEaten)g · C \(entry.carbsEaten)g · F \(entry.fatsEaten)g")
                    .font(.system(size: 10))
            } else {
                Text("Log your first meal").font(.system(size: 12, weight: .semibold))
            }
        }
    }
}

nonisolated struct CalAIWidget: Widget {
    let kind = "AetherCalAI"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AetherProvider()) { entry in
            CalAIWidgetView(entry: entry)
        }
        .configurationDisplayName("Cal AI")
        .description("Calories remaining, macros, and 7-day trend.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: - Physique widget

nonisolated struct PhysiqueWidgetView: View {
    var entry: AetherEntry
    @Environment(\.widgetFamily) private var family

    var hasScans: Bool { entry.physiqueCount > 0 }
    var bfDelta: Double { entry.bodyFatPrev > 0 ? entry.bodyFat - entry.bodyFatPrev : 0 }

    var body: some View {
        WidgetChrome {
            switch family {
            case .accessoryCircular: lockCircular
            case .accessoryRectangular: lockRect
            case .accessoryInline: Text(hasScans ? "Score \(Int(entry.physiqueScore)) · \(entry.streak)d" : "Take your first scan")
            case .systemMedium: medium
            default: small
            }
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("PHYSIQUE").font(.system(size: 9, weight: .bold)).tracking(1.6)
                    .foregroundStyle(WTheme.textTertiary)
                Spacer()
                TinyEmblem(tier: WTier.forScore(entry.physiqueScore), size: 18)
            }
            if hasScans {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(Int(entry.physiqueScore))")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(WTheme.textPrimary)
                    Text("/100").font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(WTheme.textTertiary)
                }
                if entry.physiqueHistory.count >= 2 {
                    SparkLine(values: entry.physiqueHistory, color: WTier.forScore(entry.physiqueScore).color)
                        .frame(height: 18)
                }
                HStack(spacing: 6) {
                    if entry.bodyFat > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: bfDelta < 0 ? "arrow.down" : (bfDelta > 0 ? "arrow.up" : "minus"))
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(bfDelta < 0 ? WTheme.good : (bfDelta > 0 ? WTheme.warn : WTheme.textTertiary))
                            Text(String(format: "%.1f%%", entry.bodyFat))
                                .font(.system(size: 9, weight: .semibold, design: .rounded))
                                .foregroundStyle(WTheme.textSecondary)
                        }
                    }
                    Spacer()
                    HStack(spacing: 3) {
                        Image(systemName: "flame.fill").font(.system(size: 8, weight: .bold))
                            .foregroundStyle(WTheme.warn)
                        Text("\(entry.streak)").font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(WTheme.textSecondary)
                    }
                }
            } else {
                EmptyStateView(icon: "viewfinder",
                               title: "Take your first scan",
                               subtitle: "Three angles. Cinematic analysis. Two minutes.",
                               tint: WTheme.accent)
            }
        }
        .widgetURL(URL(string: "aether://physique"))
    }

    private var medium: some View {
        HStack(spacing: 14) {
            ZStack {
                ProgressArc(progress: entry.physiqueScore / 100,
                            color: WTier.forScore(entry.physiqueScore).color, lineWidth: 9)
                VStack(spacing: 0) {
                    Text("\(Int(entry.physiqueScore))")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(WTheme.textPrimary)
                    Text("SCORE").font(.system(size: 7, weight: .bold)).tracking(1.3)
                        .foregroundStyle(WTheme.textTertiary)
                }
            }
            .frame(width: 86, height: 86)

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    TinyEmblem(tier: WTier.forScore(entry.physiqueScore), size: 14)
                    Text(WTier.forScore(entry.physiqueScore).title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(WTheme.textPrimary)
                    Spacer()
                    if let date = entry.physiqueDate {
                        Text(date, format: .dateTime.month(.abbreviated).day())
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(WTheme.textTertiary)
                    }
                }
                if hasScans {
                    MicroBar(label: "Symmetry", value: entry.symmetryScore, color: WTheme.accent)
                    MicroBar(label: "Muscle", value: entry.muscularityScore, color: WTheme.good)
                    MicroBar(label: "Lean", value: entry.conditioningScore, color: WTheme.warn)
                    if entry.physiqueHistory.count >= 2 {
                        SparkLine(values: entry.physiqueHistory,
                                  color: WTier.forScore(entry.physiqueScore).color)
                            .frame(height: 14)
                    }
                } else {
                    Text("No scans yet").font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(WTheme.textPrimary)
                    Text("Tap to start your first physique scan.")
                        .font(.system(size: 10)).foregroundStyle(WTheme.textSecondary)
                }
            }
            Spacer(minLength: 0)
        }
        .widgetURL(URL(string: "aether://physique"))
    }

    private var lockCircular: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Text("\(Int(entry.physiqueScore))").font(.system(size: 16, weight: .bold, design: .rounded))
                Text("score").font(.system(size: 8))
            }
        }
    }

    private var lockRect: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Physique").font(.system(size: 11, weight: .bold))
            if hasScans {
                Text("Score \(Int(entry.physiqueScore))  ·  \(WTier.forScore(entry.physiqueScore).title)")
                    .font(.system(size: 12, weight: .semibold))
                Text("\(entry.streak) day streak").font(.system(size: 10))
            } else {
                Text("Take your first scan").font(.system(size: 12, weight: .semibold))
            }
        }
    }
}

nonisolated struct PhysiqueWidget: Widget {
    let kind = "AetherPhysique"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AetherProvider()) { entry in
            PhysiqueWidgetView(entry: entry)
        }
        .configurationDisplayName("Physique")
        .description("Physique score, body fat trend, and 6-scan sparkline.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: - Rank widget (shared chrome, parameterized by metric)

nonisolated enum RankMetric { case physique, psl }

nonisolated struct RankWidgetView: View {
    var entry: AetherEntry
    var metric: RankMetric
    @Environment(\.widgetFamily) private var family

    var score: Double { metric == .physique ? entry.physiqueScore : entry.pslScore }
    var count: Int { metric == .physique ? entry.physiqueCount : entry.pslCount }
    var history: [Double] { metric == .physique ? entry.physiqueHistory : entry.pslHistory }
    var title: String { metric == .physique ? "PHYSIQUE RANK" : "PSL RANK" }
    var icon: String { metric == .physique ? "figure.arms.open" : "face.smiling" }
    var deeplink: String { metric == .physique ? "aether://physique" : "aether://psl" }
    var hasData: Bool { count > 0 }
    var inCircle: Bool { entry.groupSize > 1 && !entry.groupName.isEmpty }
    var scoreTier: WTier { WTier.forScore(score) }

    var body: some View {
        WidgetChrome {
            switch family {
            case .accessoryCircular: lockCircular
            case .accessoryRectangular: lockRect
            case .accessoryInline: Text(inlineText)
            case .systemMedium: medium
            default: small
            }
        }
    }

    private var inlineText: String {
        if inCircle { return "#\(entry.rank) · \(Int(score)) \(metric == .physique ? "phys" : "psl")" }
        return "\(Int(score)) \(metric == .physique ? "physique" : "psl")"
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.system(size: 9, weight: .bold)).tracking(1.6)
                    .foregroundStyle(WTheme.textTertiary)
                Spacer()
                Image(systemName: icon).font(.system(size: 10, weight: .bold))
                    .foregroundStyle(scoreTier.color)
            }
            if !hasData {
                EmptyStateView(icon: "viewfinder",
                               title: metric == .physique ? "No physique scans" : "No facial scans",
                               subtitle: "Run an analysis to unlock ranks.",
                               tint: scoreTier.color)
            } else if inCircle {
                Text("#\(entry.rank)")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(WTheme.textPrimary)
                Text("of \(entry.groupSize) in \(entry.groupName)")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(WTheme.textSecondary)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text("Score \(Int(score))").font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(scoreTier.color)
                    if entry.gap > 0 {
                        Text("· +\(entry.gap) XP")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(WTheme.textTertiary)
                    }
                }
            } else {
                Text("\(Int(score))")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(WTheme.textPrimary)
                if history.count >= 2 {
                    SparkLine(values: history, color: scoreTier.color)
                        .frame(height: 18)
                }
                Text("\(scoreTier.title) tier")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(scoreTier.color)
            }
        }
        .widgetURL(URL(string: deeplink))
    }

    private var medium: some View {
        HStack(spacing: 14) {
            VStack(spacing: 2) {
                if inCircle {
                    Text("#\(entry.rank)")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(WTheme.textPrimary)
                    Text("of \(entry.groupSize)").font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(WTheme.textSecondary)
                } else {
                    Text("\(Int(score))")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(WTheme.textPrimary)
                    Text("score").font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(WTheme.textSecondary)
                }
            }
            .frame(width: 84)

            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 8, weight: .bold)).tracking(1.6)
                    .foregroundStyle(WTheme.textTertiary)
                if !hasData {
                    Text(metric == .physique ? "No physique scans yet" : "No facial scans yet")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(WTheme.textPrimary)
                    Text("Run an analysis to start tracking your rank.")
                        .font(.system(size: 10)).foregroundStyle(WTheme.textSecondary)
                        .lineLimit(2)
                } else {
                    if inCircle {
                        Text(entry.groupName).font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(WTheme.textPrimary).lineLimit(1)
                        podium
                    } else {
                        HStack(spacing: 5) {
                            TinyEmblem(tier: scoreTier, size: 14)
                            Text("\(scoreTier.title) · \(Int(score))")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(scoreTier.color)
                        }
                    }
                    if history.count >= 2 {
                        SparkLine(values: history, color: scoreTier.color)
                            .frame(height: 16)
                    }
                    if inCircle, entry.gap > 0 {
                        Text("+\(entry.gap) XP to climb")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(scoreTier.color)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .widgetURL(URL(string: deeplink))
    }

    private var podium: some View {
        HStack(spacing: 4) {
            ForEach(Array(zip(entry.topNames.prefix(3), entry.topXP.prefix(3)).enumerated()),
                    id: \.offset) { _, pair in
                HStack(spacing: 3) {
                    Circle().fill(scoreTier.color.opacity(0.6)).frame(width: 5, height: 5)
                    Text(pair.0.prefix(8))
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(WTheme.textSecondary)
                        .lineLimit(1)
                }
            }
        }
    }

    private var lockCircular: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                if inCircle {
                    Text("#\(entry.rank)").font(.system(size: 16, weight: .bold, design: .rounded))
                    Text("rank").font(.system(size: 8))
                } else {
                    Text("\(Int(score))").font(.system(size: 16, weight: .bold, design: .rounded))
                    Text(metric == .physique ? "phys" : "psl").font(.system(size: 8))
                }
            }
        }
    }

    private var lockRect: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(metric == .physique ? "Physique Rank" : "PSL Rank")
                .font(.system(size: 11, weight: .bold))
            if !hasData {
                Text("No scans yet").font(.system(size: 12, weight: .semibold))
            } else if inCircle {
                Text("#\(entry.rank) of \(entry.groupSize) · \(Int(score))")
                    .font(.system(size: 12, weight: .semibold))
                if entry.gap > 0 { Text("+\(entry.gap) XP").font(.system(size: 10)) }
            } else {
                Text("\(scoreTier.title) · \(Int(score))").font(.system(size: 12, weight: .semibold))
            }
        }
    }
}

nonisolated struct PhysiqueRankWidget: Widget {
    let kind = "AetherPhysiqueRank"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AetherProvider()) { entry in
            RankWidgetView(entry: entry, metric: .physique)
        }
        .configurationDisplayName("Physique Rank")
        .description("Your physique rank, score, and circle podium.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

nonisolated struct PSLRankWidget: Widget {
    let kind = "AetherPSLRank"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AetherProvider()) { entry in
            RankWidgetView(entry: entry, metric: .psl)
        }
        .configurationDisplayName("PSL Rank")
        .description("Your PSL rank, facial harmony score, and trend.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: - Combined overview

nonisolated struct CombinedWidgetView: View {
    var entry: AetherEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        WidgetChrome {
            if family == .systemLarge { large } else { medium }
        }
    }

    private var medium: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                tile(title: "CAL", value: "\(max(0, entry.kcalTarget - entry.kcalEaten))",
                     unit: "left", color: WTheme.accent,
                     progress: Double(entry.kcalEaten) / Double(max(1, entry.kcalTarget)),
                     spark: entry.calorieHistory.map { Double($0) })
                tile(title: "BODY", value: entry.physiqueCount > 0 ? "\(Int(entry.physiqueScore))" : "—",
                     unit: "score", color: WTier.forScore(entry.physiqueScore).color,
                     progress: entry.physiqueScore / 100, spark: entry.physiqueHistory)
                tile(title: "PSL", value: entry.pslCount > 0 ? "\(Int(entry.pslScore))" : "—",
                     unit: "harmony", color: WTier.forScore(entry.pslScore).color,
                     progress: entry.pslScore / 100, spark: entry.pslHistory)
            }
        }
    }

    private var large: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                tile(title: "CAL", value: "\(max(0, entry.kcalTarget - entry.kcalEaten))",
                     unit: "left", color: WTheme.accent,
                     progress: Double(entry.kcalEaten) / Double(max(1, entry.kcalTarget)),
                     spark: entry.calorieHistory.map { Double($0) })
                tile(title: "BODY", value: entry.physiqueCount > 0 ? "\(Int(entry.physiqueScore))" : "—",
                     unit: "score", color: WTier.forScore(entry.physiqueScore).color,
                     progress: entry.physiqueScore / 100, spark: entry.physiqueHistory)
                tile(title: "PSL", value: entry.pslCount > 0 ? "\(Int(entry.pslScore))" : "—",
                     unit: "harmony", color: WTier.forScore(entry.pslScore).color,
                     progress: entry.pslScore / 100, spark: entry.pslHistory)
            }

            // Identity strip
            HStack(alignment: .center, spacing: 12) {
                TinyEmblem(tier: entry.tier, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.userName.isEmpty ? "Welcome" : entry.userName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(WTheme.textPrimary)
                    Text("\(entry.tier.title) · \(entry.xp) XP")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(WTheme.textSecondary)
                }
                Spacer()
                VStack(spacing: 1) {
                    HStack(spacing: 3) {
                        Image(systemName: "flame.fill").font(.system(size: 10, weight: .bold))
                            .foregroundStyle(WTheme.warn)
                        Text("\(entry.streak)").font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(WTheme.textPrimary)
                    }
                    Text("STREAK").font(.system(size: 7, weight: .bold)).tracking(1.4)
                        .foregroundStyle(WTheme.textTertiary)
                }
            }
            .padding(.horizontal, 4)

            // Weekly heatmap
            HStack(spacing: 6) {
                ForEach(0..<7, id: \.self) { i in
                    let on = i < entry.streakHistory.count ? entry.streakHistory[i] == 1 : false
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(on ? entry.tier.color : WTheme.line)
                        .frame(height: 18)
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .strokeBorder(WTheme.line, lineWidth: 0.5)
                        )
                }
            }

            // XP bar
            GeometryReader { geo in
                let span = max(1, Double(entry.tierCeil - entry.tierFloor))
                let p = min(1, max(0, Double(entry.xp - entry.tierFloor) / span))
                ZStack(alignment: .leading) {
                    Capsule().fill(WTheme.line)
                    Capsule().fill(entry.tier.color).frame(width: geo.size.width * p)
                }
            }
            .frame(height: 4)
        }
        .widgetURL(URL(string: "aether://home"))
    }

    private func tile(title: String, value: String, unit: String, color: Color,
                      progress: Double, spark: [Double]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 8, weight: .bold)).tracking(1.4)
                .foregroundStyle(WTheme.textTertiary)
            Text(value).font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(WTheme.textPrimary)
                .minimumScaleFactor(0.6).lineLimit(1)
            Text(unit).font(.system(size: 8, weight: .semibold))
                .foregroundStyle(WTheme.textSecondary)
            if spark.count >= 2 {
                SparkLine(values: spark, color: color).frame(height: 12)
            } else {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(WTheme.line)
                        Capsule().fill(color).frame(width: max(2, geo.size.width * min(1, max(0, progress))))
                    }
                }.frame(height: 3)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(WTheme.surface.opacity(0.55))
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(WTheme.line, lineWidth: 0.6)
        }
    }
}

nonisolated struct CombinedWidget: Widget {
    let kind = "AetherCombined"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AetherProvider()) { entry in
            CombinedWidgetView(entry: entry)
        }
        .configurationDisplayName("Aether Overview")
        .description("Calories, physique, PSL, and weekly streak — all in one.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}
