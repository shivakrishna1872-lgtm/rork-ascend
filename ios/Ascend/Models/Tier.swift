import SwiftUI

enum Tier: String, CaseIterable, Codable {
    case bronze, silver, gold, elite, greek

    var title: String {
        switch self {
        case .bronze: "Bronze"
        case .silver: "Silver"
        case .gold:   "Gold"
        case .elite:  "Elite"
        case .greek:  "Greek God"
        }
    }

    var subtitle: String {
        switch self {
        case .bronze: "Beginning Optimization"
        case .silver: "Visible Progress"
        case .gold:   "Advanced Consistency"
        case .elite:  "Rare Discipline"
        case .greek:  "Peak Optimization"
        }
    }

    var color: Color {
        switch self {
        case .bronze: Theme.bronze
        case .silver: Theme.silver
        case .gold:   Theme.gold
        case .elite:  Theme.elite
        case .greek:  Theme.greek
        }
    }

    var xpFloor: Int {
        switch self {
        case .bronze: 0
        case .silver: 500
        case .gold:   1500
        case .elite:  4000
        case .greek:  10000
        }
    }

    var xpCeiling: Int {
        switch self {
        case .bronze: 500
        case .silver: 1500
        case .gold:   4000
        case .elite:  10000
        case .greek:  25000
        }
    }

    static func forXP(_ xp: Int) -> Tier {
        if xp >= Tier.greek.xpFloor { return .greek }
        if xp >= Tier.elite.xpFloor { return .elite }
        if xp >= Tier.gold.xpFloor  { return .gold }
        if xp >= Tier.silver.xpFloor { return .silver }
        return .bronze
    }

    /// 0–100 score → tier (used for Physique / PSL standings, not XP).
    static func forScore(_ score: Double) -> Tier {
        if score >= 90 { return .greek }
        if score >= 80 { return .elite }
        if score >= 65 { return .gold }
        if score >= 50 { return .silver }
        return .bronze
    }

    /// Inclusive score range used to label score-based tier ladders.
    var scoreRange: ClosedRange<Int> {
        switch self {
        case .bronze: 0...49
        case .silver: 50...64
        case .gold:   65...79
        case .elite:  80...89
        case .greek:  90...100
        }
    }

    var next: Tier? {
        switch self {
        case .bronze: .silver
        case .silver: .gold
        case .gold:   .elite
        case .elite:  .greek
        case .greek:  nil
        }
    }
}

enum Goal: String, CaseIterable, Codable, Identifiable {
    case loseFat = "Lose Fat"
    case gainMuscle = "Gain Muscle"
    case aesthetics = "Improve Aesthetics"
    case athletic = "Athletic Performance"
    case discipline = "Improve Discipline"
    case transformation = "Transformation"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .loseFat: "flame"
        case .gainMuscle: "figure.strengthtraining.traditional"
        case .aesthetics: "sparkles"
        case .athletic: "bolt.heart"
        case .discipline: "scope"
        case .transformation: "arrow.triangle.2.circlepath"
        }
    }
}

enum ActivityLevel: String, CaseIterable, Codable, Identifiable {
    case sedentary = "Sedentary"
    case active = "Active"
    case athlete = "Athlete"
    var id: String { rawValue }
    var multiplier: Double {
        switch self {
        case .sedentary: 1.35
        case .active:    1.55
        case .athlete:   1.80
        }
    }
}

enum Sex: String, CaseIterable, Codable, Identifiable {
    case male = "Male"
    case female = "Female"
    var id: String { rawValue }
}

enum AIPersonality: String, CaseIterable, Codable, Identifiable {
    case science = "Science-Based"
    case motivational = "Motivational"
    case aesthetic = "Aesthetic-Focused"
    var id: String { rawValue }
}

enum Archetype: String, Codable, CaseIterable {
    case leanAthletic = "Lean Athletic"
    case aesthetic = "Aesthetic"
    case vTaper = "V-Taper"
    case powerBuild = "Power Build"
    case swimmer = "Swimmer Build"
    case balanced = "Balanced Physique"
}
