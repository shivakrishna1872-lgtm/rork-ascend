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
