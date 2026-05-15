import Foundation
import SwiftData

@Model
final class UserProfile {
    var name: String
    var ageValue: Int
    var sexRaw: String
    var heightCm: Double
    var weightKg: Double
    var goalsRaw: [String]
    var activityRaw: String
    var personalityRaw: String
    var xp: Int
    var streak: Int
    var lastActiveDate: Date?
    var createdAt: Date
    var onboarded: Bool
    var reduceMotion: Bool
    var hydrationGlasses: Int
    var hydrationDate: Date?

    init(
        name: String = "Athlete",
        ageValue: Int = 24,
        sexRaw: String = Sex.male.rawValue,
        heightCm: Double = 178,
        weightKg: Double = 75,
        goalsRaw: [String] = [Goal.aesthetics.rawValue, Goal.gainMuscle.rawValue],
        activityRaw: String = ActivityLevel.active.rawValue,
        personalityRaw: String = AIPersonality.science.rawValue,
        xp: Int = 0,
        streak: Int = 0,
        lastActiveDate: Date? = nil,
        createdAt: Date = .now,
        onboarded: Bool = false,
        reduceMotion: Bool = false,
        hydrationGlasses: Int = 0,
        hydrationDate: Date? = nil
    ) {
        self.name = name
        self.ageValue = ageValue
        self.sexRaw = sexRaw
        self.heightCm = heightCm
        self.weightKg = weightKg
        self.goalsRaw = goalsRaw
        self.activityRaw = activityRaw
        self.personalityRaw = personalityRaw
        self.xp = xp
        self.streak = streak
        self.lastActiveDate = lastActiveDate
        self.createdAt = createdAt
        self.onboarded = onboarded
        self.reduceMotion = reduceMotion
        self.hydrationGlasses = hydrationGlasses
        self.hydrationDate = hydrationDate
    }

    var sex: Sex { Sex(rawValue: sexRaw) ?? .male }
    var activity: ActivityLevel { ActivityLevel(rawValue: activityRaw) ?? .active }
    var personality: AIPersonality { AIPersonality(rawValue: personalityRaw) ?? .science }
    var goals: [Goal] { goalsRaw.compactMap { Goal(rawValue: $0) } }
    var tier: Tier { Tier.forXP(xp) }

    var tierProgress: Double {
        let t = tier
        let span = Double(t.xpCeiling - t.xpFloor)
        if span <= 0 { return 1 }
        return min(1, max(0, Double(xp - t.xpFloor) / span))
    }

    /// Mifflin-St Jeor BMR * activity, with goal adjustment
    var dailyCalorieTarget: Int {
        let bmr: Double = {
            if sex == .male {
                return 10 * weightKg + 6.25 * heightCm - 5 * Double(ageValue) + 5
            } else {
                return 10 * weightKg + 6.25 * heightCm - 5 * Double(ageValue) - 161
            }
        }()
        var tdee = bmr * activity.multiplier
        if goals.contains(.loseFat) { tdee -= 400 }
        if goals.contains(.gainMuscle) { tdee += 250 }
        return Int(tdee.rounded())
    }

    var proteinTargetG: Int { Int((weightKg * 2.0).rounded()) }
    var carbTargetG: Int { Int(Double(dailyCalorieTarget) * 0.45 / 4) }
    var fatTargetG: Int { Int(Double(dailyCalorieTarget) * 0.25 / 9) }
}

@Model
final class PhysiqueScanRecord {
    var date: Date
    var physiqueScore: Double
    var symmetryScore: Double
    var muscularityScore: Double
    var conditioningScore: Double
    var vTaperScore: Double
    var bodyFatPercent: Double
    var bodyFatConfidence: Double
    var archetypeRaw: String
    var recommendations: [String]
    var insight: String
    var frontImageData: Data?
    var sideImageData: Data?
    var backImageData: Data?

    init(
        date: Date = .now,
        physiqueScore: Double,
        symmetryScore: Double,
        muscularityScore: Double,
        conditioningScore: Double,
        vTaperScore: Double,
        bodyFatPercent: Double,
        bodyFatConfidence: Double,
        archetypeRaw: String,
        recommendations: [String],
        insight: String,
        frontImageData: Data? = nil,
        sideImageData: Data? = nil,
        backImageData: Data? = nil
    ) {
        self.date = date
        self.physiqueScore = physiqueScore
        self.symmetryScore = symmetryScore
        self.muscularityScore = muscularityScore
        self.conditioningScore = conditioningScore
        self.vTaperScore = vTaperScore
        self.bodyFatPercent = bodyFatPercent
        self.bodyFatConfidence = bodyFatConfidence
        self.archetypeRaw = archetypeRaw
        self.recommendations = recommendations
        self.insight = insight
        self.frontImageData = frontImageData
        self.sideImageData = sideImageData
        self.backImageData = backImageData
    }

    var archetype: Archetype { Archetype(rawValue: archetypeRaw) ?? .balanced }
}

// MARK: - Rolling-average smoothing (stability over time)

/// Applies exponential-style smoothing to physique metrics based on the user's
/// recent history so similar uploads don't produce wildly different scores.
///
/// Strategy: blend new = newWeight * raw + (1 - newWeight) * recentAverage.
/// `newWeight` decreases with the number of prior scans (more history -> more stability).
enum PhysiqueSmoothing {
    static func smooth(raw: PhysiqueAnalysis, blendedSymmetry: Double, blendedVTaper: Double,
                       priors: [PhysiqueScanRecord]) -> PhysiqueAnalysis {
        let n = priors.count
        guard n > 0 else {
            return PhysiqueAnalysis(
                physiqueScore: raw.physiqueScore,
                symmetry: blendedSymmetry,
                muscularity: raw.muscularity,
                conditioning: raw.conditioning,
                vTaper: blendedVTaper,
                bodyFatPercent: raw.bodyFatPercent,
                bodyFatConfidence: raw.bodyFatConfidence,
                archetype: raw.archetype,
                insight: raw.insight,
                recommendations: raw.recommendations
            )
        }
        // 1 scan -> 0.60, 2 -> 0.50, 3 -> 0.42, 4+ -> 0.36
        let newWeight = max(0.36, 0.7 - Double(n) * 0.08)
        let recent = Array(priors.prefix(5))
        func avg(_ key: (PhysiqueScanRecord) -> Double) -> Double {
            recent.map(key).reduce(0, +) / Double(recent.count)
        }
        return PhysiqueAnalysis(
            physiqueScore: blend(raw.physiqueScore, avg(\.physiqueScore), w: newWeight),
            symmetry: blend(blendedSymmetry, avg(\.symmetryScore), w: newWeight),
            muscularity: blend(raw.muscularity, avg(\.muscularityScore), w: newWeight),
            conditioning: blend(raw.conditioning, avg(\.conditioningScore), w: newWeight),
            vTaper: blend(blendedVTaper, avg(\.vTaperScore), w: newWeight),
            bodyFatPercent: blend(raw.bodyFatPercent, avg(\.bodyFatPercent), w: newWeight),
            bodyFatConfidence: raw.bodyFatConfidence,
            archetype: raw.archetype,
            insight: raw.insight,
            recommendations: raw.recommendations
        )
    }

    /// Calibration confidence in 0...1 derived from sample count + score stability.
    /// Surfaces a "how trustworthy is this baseline" signal to the user.
    static func calibration(from records: [PhysiqueScanRecord]) -> Calibration {
        let recent = Array(records.prefix(8))
        guard !recent.isEmpty else { return .none }
        let n = Double(recent.count)
        func avg(_ key: (PhysiqueScanRecord) -> Double) -> Double {
            recent.map(key).reduce(0, +) / n
        }
        func std(_ key: (PhysiqueScanRecord) -> Double) -> Double {
            let m = avg(key)
            let v = recent.map { pow(key($0) - m, 2) }.reduce(0, +) / n
            return sqrt(v)
        }
        let stdAvg = (std(\.physiqueScore) + std(\.symmetryScore)
                      + std(\.muscularityScore) + std(\.conditioningScore)
                      + std(\.vTaperScore)) / 5
        return Calibration(sampleCount: recent.count,
                           sampleCap: 8,
                           dispersion: stdAvg)
    }

    static func history(from records: [PhysiqueScanRecord]) -> ScoreHistory {
        let recent = Array(records.prefix(8))
        guard !recent.isEmpty else { return .none }
        func avg(_ key: (PhysiqueScanRecord) -> Double) -> Double {
            recent.map(key).reduce(0, +) / Double(recent.count)
        }
        func std(_ key: (PhysiqueScanRecord) -> Double) -> Double {
            let m = avg(key)
            let v = recent.map { pow(key($0) - m, 2) }.reduce(0, +) / Double(recent.count)
            return sqrt(v)
        }
        // Trend: oldest → newest delta on physique score (records are newest-first).
        let trend: Double = {
            guard recent.count >= 2,
                  let oldest = recent.last, let newest = recent.first else { return 0 }
            return newest.physiqueScore - oldest.physiqueScore
        }()
        let s = """
        n=\(recent.count) prior scans — personal baseline (rolling mean ± std):
        physique \(Int(avg(\.physiqueScore).rounded()))±\(Int(std(\.physiqueScore).rounded())), \
        symmetry \(Int(avg(\.symmetryScore).rounded()))±\(Int(std(\.symmetryScore).rounded())), \
        muscle \(Int(avg(\.muscularityScore).rounded()))±\(Int(std(\.muscularityScore).rounded())), \
        lean \(Int(avg(\.conditioningScore).rounded()))±\(Int(std(\.conditioningScore).rounded())), \
        v-taper \(Int(avg(\.vTaperScore).rounded()))±\(Int(std(\.vTaperScore).rounded())), \
        bf \(String(format: "%.1f", avg(\.bodyFatPercent)))±\(String(format: "%.1f", std(\.bodyFatPercent)))%; \
        recent trend on physique: \(String(format: "%+.1f", trend))
        """
        return ScoreHistory(summary: s, isEmpty: false)
    }

    private static func blend(_ a: Double, _ b: Double, w: Double) -> Double {
        max(0, min(100, a * w + b * (1 - w)))
    }
}

enum FaceSmoothing {
    static func smooth(raw: FaceAnalysis, priors: [FaceScanRecord]) -> FaceAnalysis {
        let n = priors.count
        guard n > 0 else { return raw }
        let newWeight = max(0.36, 0.7 - Double(n) * 0.08)
        let recent = Array(priors.prefix(5))
        func avg(_ key: (FaceScanRecord) -> Double) -> Double {
            recent.map(key).reduce(0, +) / Double(recent.count)
        }
        func blend(_ a: Double, _ b: Double) -> Double {
            max(0, min(100, a * newWeight + b * (1 - newWeight)))
        }
        return FaceAnalysis(
            overall: blend(raw.overall, avg(\.overallScore)),
            symmetry: blend(raw.symmetry, avg(\.symmetry)),
            jawline: blend(raw.jawline, avg(\.jawline)),
            thirds: blend(raw.thirds, avg(\.thirds)),
            canthalTilt: blend(raw.canthalTilt, avg(\.canthalTilt)),
            eyeSpacing: blend(raw.eyeSpacing, avg(\.eyeSpacing)),
            glowUpPotential: blend(raw.glowUpPotential, avg(\.glowUpPotential)),
            insight: raw.insight,
            recommendations: raw.recommendations,
            hairstyles: raw.hairstyles
        )
    }

    static func calibration(from records: [FaceScanRecord]) -> Calibration {
        let recent = Array(records.prefix(8))
        guard !recent.isEmpty else { return .none }
        let n = Double(recent.count)
        func avg(_ key: (FaceScanRecord) -> Double) -> Double {
            recent.map(key).reduce(0, +) / n
        }
        func std(_ key: (FaceScanRecord) -> Double) -> Double {
            let m = avg(key)
            let v = recent.map { pow(key($0) - m, 2) }.reduce(0, +) / n
            return sqrt(v)
        }
        let stdAvg = (std(\.overallScore) + std(\.symmetry) + std(\.jawline)
                      + std(\.thirds) + std(\.canthalTilt)
                      + std(\.eyeSpacing)) / 6
        return Calibration(sampleCount: recent.count,
                           sampleCap: 8,
                           dispersion: stdAvg)
    }

    static func history(from records: [FaceScanRecord]) -> ScoreHistory {
        let recent = Array(records.prefix(8))
        guard !recent.isEmpty else { return .none }
        func avg(_ key: (FaceScanRecord) -> Double) -> Double {
            recent.map(key).reduce(0, +) / Double(recent.count)
        }
        func std(_ key: (FaceScanRecord) -> Double) -> Double {
            let m = avg(key)
            let v = recent.map { pow(key($0) - m, 2) }.reduce(0, +) / Double(recent.count)
            return sqrt(v)
        }
        let trend: Double = {
            guard recent.count >= 2,
                  let oldest = recent.last, let newest = recent.first else { return 0 }
            return newest.overallScore - oldest.overallScore
        }()
        let s = """
        n=\(recent.count) prior scans — personal baseline (rolling mean ± std):
        overall \(Int(avg(\.overallScore).rounded()))±\(Int(std(\.overallScore).rounded())), \
        symmetry \(Int(avg(\.symmetry).rounded()))±\(Int(std(\.symmetry).rounded())), \
        jawline \(Int(avg(\.jawline).rounded()))±\(Int(std(\.jawline).rounded())), \
        thirds \(Int(avg(\.thirds).rounded()))±\(Int(std(\.thirds).rounded())), \
        canthal \(Int(avg(\.canthalTilt).rounded()))±\(Int(std(\.canthalTilt).rounded())), \
        eye-spacing \(Int(avg(\.eyeSpacing).rounded()))±\(Int(std(\.eyeSpacing).rounded())); \
        recent trend on overall: \(String(format: "%+.1f", trend))
        """
        return ScoreHistory(summary: s, isEmpty: false)
    }
}

// MARK: - Calibration model

/// Trust level for the user's personal baseline. Improves as more scans are
/// logged AND as recent score variance settles down.
nonisolated struct Calibration: Equatable {
    let sampleCount: Int
    let sampleCap: Int
    let dispersion: Double // average std across metrics

    static let none = Calibration(sampleCount: 0, sampleCap: 8, dispersion: 0)

    var isEmpty: Bool { sampleCount == 0 }

    /// 0...1 — combines sample size and inverse dispersion.
    var score: Double {
        guard sampleCount > 0 else { return 0 }
        let sampleWeight = min(1.0, Double(sampleCount) / Double(sampleCap))
        // Dispersion of ~10 pts is rough; <3 is locked-in.
        let stability = max(0, min(1, 1 - (dispersion / 10)))
        return sampleWeight * 0.55 + stability * 0.45
    }

    var stage: Stage {
        if sampleCount == 0 { return .empty }
        if sampleCount < 3 || score < 0.45 { return .calibrating }
        if score < 0.75 { return .stable }
        return .lockedIn
    }

    enum Stage {
        case empty, calibrating, stable, lockedIn
        var label: String {
            switch self {
            case .empty: return "AWAITING DATA"
            case .calibrating: return "CALIBRATING"
            case .stable: return "STABLE"
            case .lockedIn: return "LOCKED-IN"
            }
        }
    }
}

@Model
final class FaceScanRecord {
    var date: Date
    var overallScore: Double
    var symmetry: Double
    var jawline: Double
    var thirds: Double
    var canthalTilt: Double
    var eyeSpacing: Double
    var glowUpPotential: Double
    var recommendations: [String]
    var hairstyles: [String]
    var insight: String
    var imageData: Data?

    init(
        date: Date = .now,
        overallScore: Double,
        symmetry: Double,
        jawline: Double,
        thirds: Double,
        canthalTilt: Double,
        eyeSpacing: Double,
        glowUpPotential: Double,
        recommendations: [String],
        hairstyles: [String],
        insight: String,
        imageData: Data? = nil
    ) {
        self.date = date
        self.overallScore = overallScore
        self.symmetry = symmetry
        self.jawline = jawline
        self.thirds = thirds
        self.canthalTilt = canthalTilt
        self.eyeSpacing = eyeSpacing
        self.glowUpPotential = glowUpPotential
        self.recommendations = recommendations
        self.hairstyles = hairstyles
        self.insight = insight
        self.imageData = imageData
    }
}

@Model
final class MealEntry {
    var date: Date
    var name: String
    var calories: Int
    var proteinG: Int
    var carbsG: Int
    var fatsG: Int
    var note: String
    var imageData: Data?

    init(
        date: Date = .now,
        name: String,
        calories: Int,
        proteinG: Int,
        carbsG: Int,
        fatsG: Int,
        note: String = "",
        imageData: Data? = nil
    ) {
        self.date = date
        self.name = name
        self.calories = calories
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatsG = fatsG
        self.note = note
        self.imageData = imageData
    }
}

@Model
final class Achievement {
    var key: String
    var title: String
    var subtitle: String
    var unlockedAt: Date
    init(key: String, title: String, subtitle: String, unlockedAt: Date = .now) {
        self.key = key; self.title = title; self.subtitle = subtitle; self.unlockedAt = unlockedAt
    }
}
