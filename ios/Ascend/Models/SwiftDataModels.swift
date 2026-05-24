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
    var appleUserId: String?
    var email: String?
    var unitSystemRaw: String = UnitSystem.metric.rawValue
    /// Coach-set temporary daily calorie target override. 0 = no override.
    var calorieOverrideValue: Int = 0
    var calorieOverrideUntil: Date? = nil
    /// Coach-set temporary daily protein target override (grams). 0 = no override.
    var proteinOverrideValue: Int = 0
    var proteinOverrideUntil: Date? = nil
    /// Target weight in kg. 0 means "no goal set" → maintenance.
    var idealWeightKg: Double = 0
    /// Desired rate of weight change in kg per week. Sign mirrors direction:
    /// negative = cut, positive = gain, 0 = maintain.
    var weightPaceKgPerWeek: Double = 0
    /// Target physique archetype (see `IdealAesthetic`). Empty = no preference.
    var idealAestheticRaw: String = ""

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
        hydrationDate: Date? = nil,
        appleUserId: String? = nil,
        email: String? = nil,
        unitSystemRaw: String = UnitSystem.metric.rawValue,
        calorieOverrideValue: Int = 0,
        calorieOverrideUntil: Date? = nil,
        proteinOverrideValue: Int = 0,
        proteinOverrideUntil: Date? = nil,
        idealWeightKg: Double = 0,
        weightPaceKgPerWeek: Double = 0,
        idealAestheticRaw: String = ""
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
        self.appleUserId = appleUserId
        self.email = email
        self.unitSystemRaw = unitSystemRaw
        self.calorieOverrideValue = calorieOverrideValue
        self.calorieOverrideUntil = calorieOverrideUntil
        self.proteinOverrideValue = proteinOverrideValue
        self.proteinOverrideUntil = proteinOverrideUntil
        self.idealWeightKg = idealWeightKg
        self.weightPaceKgPerWeek = weightPaceKgPerWeek
        self.idealAestheticRaw = idealAestheticRaw
    }

    /// Resolved aesthetic preference, nil if the user skipped the question.
    var idealAesthetic: IdealAesthetic? {
        IdealAesthetic(rawValue: idealAestheticRaw)
    }

    var sex: Sex { Sex(rawValue: sexRaw) ?? .male }
    var unitSystem: UnitSystem { UnitSystem(rawValue: unitSystemRaw) ?? .metric }
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

    /// Mifflin-St Jeor BMR * activity, with goal adjustment, honoring any
    /// active coach-set override that hasn't expired yet.
    var dailyCalorieTarget: Int {
        if calorieOverrideValue > 0,
           let until = calorieOverrideUntil, until > .now {
            return calorieOverrideValue
        }
        return baseDailyCalorieTarget
    }

    /// Underlying TDEE-derived target, ignoring any override.
    var baseDailyCalorieTarget: Int {
        let bmr: Double = {
            if sex == .male {
                return 10 * weightKg + 6.25 * heightCm - 5 * Double(ageValue) + 5
            } else {
                return 10 * weightKg + 6.25 * heightCm - 5 * Double(ageValue) - 161
            }
        }()
        var tdee = bmr * activity.multiplier
        // Pace-based adjustment dominates if the user set an ideal weight + pace.
        // ~7700 kcal per kg of body mass → daily delta = pace * 7700 / 7.
        if idealWeightKg > 0 && weightPaceKgPerWeek != 0 {
            let dailyDelta = weightPaceKgPerWeek * 7700.0 / 7.0
            // Safety cap so the AI / user can't starve themselves or binge.
            let capped = max(-900.0, min(700.0, dailyDelta))
            tdee += capped
        } else {
            if goals.contains(.loseFat) { tdee -= 400 }
            if goals.contains(.gainMuscle) { tdee += 250 }
        }
        return Int(tdee.rounded())
    }

    /// Estimated weeks to reach ideal weight at the current pace. nil if not set.
    var weeksToGoal: Int? {
        guard idealWeightKg > 0, weightPaceKgPerWeek != 0 else { return nil }
        let diff = idealWeightKg - weightKg
        if (diff > 0 && weightPaceKgPerWeek <= 0) || (diff < 0 && weightPaceKgPerWeek >= 0) {
            return nil
        }
        let weeks = abs(diff / weightPaceKgPerWeek)
        return max(1, Int(weeks.rounded()))
    }

    var proteinTargetG: Int {
        if proteinOverrideValue > 0,
           let until = proteinOverrideUntil, until > .now {
            return proteinOverrideValue
        }
        return Int((weightKg * 2.0).rounded())
    }
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
    /// Provenance — which deterministic engine produced these numbers.
    var engineVersion: String = EngineRegistry.Physique.current.rawValue
    /// Calibration profile version active at scan time.
    var calibrationVersion: String = "calibration_v1"
    /// SHA-256 of the Vision anchors. Same inputs → same hash → reproducible.
    var inputHash: String = ""
    /// Self-contained replay payload (JSON) — re-running through the same
    /// engine version produces identical numbers. See `ScanReplay`.
    var inputPayload: String = ""
    /// Human-readable reasons the displayed confidence isn't 100%.
    /// e.g. "Legs not visible", "Low lighting", "PSL/Physique disagree".
    /// Always honest — shown in the UI so users understand what the
    /// detector actually saw. Empty array = clean, high-confidence scan.
    var confidenceReasons: [String] = []
    /// Worst-case `BodyContinuity.Partiality` across all 3 angles, as a
    /// raw string. Drives per-region scoring + UI badge. Default "full".
    var partialityRaw: String = "full"
    /// True when the cross-pipeline check (PSL ↔ Physique) flagged a
    /// divergence. UI renders an uncertainty badge.
    var isUncertaintyEvent: Bool = false

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
        backImageData: Data? = nil,
        engineVersion: String = EngineRegistry.Physique.current.rawValue,
        calibrationVersion: String = "calibration_v1",
        inputHash: String = "",
        inputPayload: String = "",
        confidenceReasons: [String] = [],
        partialityRaw: String = "full",
        isUncertaintyEvent: Bool = false
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
        self.engineVersion = engineVersion
        self.calibrationVersion = calibrationVersion
        self.inputHash = inputHash
        self.inputPayload = inputPayload
        self.confidenceReasons = confidenceReasons
        self.partialityRaw = partialityRaw
        self.isUncertaintyEvent = isUncertaintyEvent
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
        // Dynamic weighting — strongly favor the NEW reading so real progress shows up.
        // 1 scan -> 0.82, 2 -> 0.76, 3 -> 0.70, 4 -> 0.66, 5+ -> 0.62
        // The baseline still anchors against noise, but every scan moves the dial meaningfully.
        let baseWeight = max(0.62, 0.88 - Double(n) * 0.06)
        let recent = Array(priors.prefix(5))
        func avg(_ key: (PhysiqueScanRecord) -> Double) -> Double {
            recent.map(key).reduce(0, +) / Double(recent.count)
        }
        func std(_ key: (PhysiqueScanRecord) -> Double) -> Double {
            let m = avg(key)
            let v = recent.map { pow(key($0) - m, 2) }.reduce(0, +) / Double(recent.count)
            return sqrt(v)
        }
        // Breakthrough rule: any meaningful movement (>= max(0.6*std, 2 pts)) in the
        // improvement direction trusts the new reading even more, so visible progress
        // produces a satisfying jump instead of a tiny nudge. Regressions also register
        // visibly so the score reflects reality both ways.
        func adapt(_ rawVal: Double, _ avgVal: Double, _ stdVal: Double, lowerIsBetter: Bool = false) -> Double {
            let delta = lowerIsBetter ? (avgVal - rawVal) : (rawVal - avgVal)
            let threshold = max(stdVal * 0.4, 1.2)
            if delta > threshold {
                let bonus = min(0.35, (delta - threshold) / 5.0)
                return min(0.98, baseWeight + 0.18 + bonus)
            }
            if delta < -threshold {
                let penalty = min(0.25, (-delta - threshold) / 7.0)
                return min(0.95, baseWeight + 0.14 + penalty)
            }
            return baseWeight
        }
        let wPhysique = adapt(raw.physiqueScore, avg(\.physiqueScore), std(\.physiqueScore))
        let wSym = adapt(blendedSymmetry, avg(\.symmetryScore), std(\.symmetryScore))
        let wMus = adapt(raw.muscularity, avg(\.muscularityScore), std(\.muscularityScore))
        let wCon = adapt(raw.conditioning, avg(\.conditioningScore), std(\.conditioningScore))
        let wVT = adapt(blendedVTaper, avg(\.vTaperScore), std(\.vTaperScore))
        // For body fat, lower is the "improvement" direction.
        let wBF = adapt(raw.bodyFatPercent, avg(\.bodyFatPercent), std(\.bodyFatPercent), lowerIsBetter: true)
        return PhysiqueAnalysis(
            physiqueScore: blend(raw.physiqueScore, avg(\.physiqueScore), w: wPhysique),
            symmetry: blend(blendedSymmetry, avg(\.symmetryScore), w: wSym),
            muscularity: blend(raw.muscularity, avg(\.muscularityScore), w: wMus),
            conditioning: blend(raw.conditioning, avg(\.conditioningScore), w: wCon),
            vTaper: blend(blendedVTaper, avg(\.vTaperScore), w: wVT),
            bodyFatPercent: blend(raw.bodyFatPercent, avg(\.bodyFatPercent), w: wBF),
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
        // Dynamic weighting — strongly favor the NEW reading so real grooming/leanness/posture
        // wins show up immediately. 1 -> 0.82, 2 -> 0.76, 3 -> 0.70, 4 -> 0.66, 5+ -> 0.62
        let baseWeight = max(0.62, 0.88 - Double(n) * 0.06)
        let recent = Array(priors.prefix(5))
        func avg(_ key: (FaceScanRecord) -> Double) -> Double {
            recent.map(key).reduce(0, +) / Double(recent.count)
        }
        func std(_ key: (FaceScanRecord) -> Double) -> Double {
            let m = avg(key)
            let v = recent.map { pow(key($0) - m, 2) }.reduce(0, +) / Double(recent.count)
            return sqrt(v)
        }
        // Breakthrough: any meaningful move (>= max(0.6*std, 2 pts)) trusts the new
        // reading more. Regressions register visibly so progress feedback is honest.
        func adapt(_ rawVal: Double, _ avgVal: Double, _ stdVal: Double) -> Double {
            let delta = rawVal - avgVal
            let threshold = max(stdVal * 0.4, 1.2)
            if delta > threshold {
                let bonus = min(0.35, (delta - threshold) / 5.0)
                return min(0.98, baseWeight + 0.18 + bonus)
            }
            if delta < -threshold {
                let penalty = min(0.25, (-delta - threshold) / 7.0)
                return min(0.95, baseWeight + 0.14 + penalty)
            }
            return baseWeight
        }
        func blend(_ a: Double, _ b: Double, _ w: Double) -> Double {
            max(0, min(100, a * w + b * (1 - w)))
        }
        let wO = adapt(raw.overall, avg(\.overallScore), std(\.overallScore))
        let wS = adapt(raw.symmetry, avg(\.symmetry), std(\.symmetry))
        let wJ = adapt(raw.jawline, avg(\.jawline), std(\.jawline))
        let wT = adapt(raw.thirds, avg(\.thirds), std(\.thirds))
        let wC = adapt(raw.canthalTilt, avg(\.canthalTilt), std(\.canthalTilt))
        let wE = adapt(raw.eyeSpacing, avg(\.eyeSpacing), std(\.eyeSpacing))
        let wG = adapt(raw.glowUpPotential, avg(\.glowUpPotential), std(\.glowUpPotential))
        return FaceAnalysis(
            overall: blend(raw.overall, avg(\.overallScore), wO),
            symmetry: blend(raw.symmetry, avg(\.symmetry), wS),
            jawline: blend(raw.jawline, avg(\.jawline), wJ),
            thirds: blend(raw.thirds, avg(\.thirds), wT),
            canthalTilt: blend(raw.canthalTilt, avg(\.canthalTilt), wC),
            eyeSpacing: blend(raw.eyeSpacing, avg(\.eyeSpacing), wE),
            glowUpPotential: blend(raw.glowUpPotential, avg(\.glowUpPotential), wG),
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
    var engineVersion: String = EngineRegistry.PSL.current.rawValue
    var calibrationVersion: String = "calibration_v1"
    var inputHash: String = ""
    /// Self-contained replay payload (JSON) — re-running through the same
    /// engine version produces identical numbers. See `ScanReplay`.
    var inputPayload: String = ""

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
        imageData: Data? = nil,
        engineVersion: String = EngineRegistry.PSL.current.rawValue,
        calibrationVersion: String = "calibration_v1",
        inputHash: String = "",
        inputPayload: String = ""
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
        self.engineVersion = engineVersion
        self.calibrationVersion = calibrationVersion
        self.inputHash = inputHash
        self.inputPayload = inputPayload
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
final class LiftEntry {
    var date: Date
    /// Bench press 1RM in kilograms. 0 means not logged this session.
    var benchKg: Double
    /// Squat 1RM in kilograms. 0 means not logged this session.
    var squatKg: Double
    /// Deadlift 1RM in kilograms. 0 means not logged this session.
    var deadliftKg: Double
    var note: String

    init(date: Date = .now, benchKg: Double = 0, squatKg: Double = 0, deadliftKg: Double = 0, note: String = "") {
        self.date = date
        self.benchKg = benchKg
        self.squatKg = squatKg
        self.deadliftKg = deadliftKg
        self.note = note
    }

    var totalKg: Double { benchKg + squatKg + deadliftKg }
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
