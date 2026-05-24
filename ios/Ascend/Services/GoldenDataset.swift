import Foundation

/// Manually verified ground-truth fixtures used by `RegressionRunner` to
/// evaluate the deterministic scoring engines. Golden samples are **frozen** —
/// once shipped, an entry never changes. To revise a label, ship a new entry
/// with a new id.
///
/// Replay (`ScanReplay`) stays deterministic and immutable. This dataset is
/// the evaluation surface that sits *on top* of replay and tells us when a
/// new engine version drifts from previously hand-verified results.
///
/// Three sample kinds are supported:
///  - `.physique` — frozen `ReplayPayload` JSON + expected score range
///  - `.face`     — frozen `ReplayPayload` JSON + expected score range
///  - `.meal`     — text description + expected food name + macro window
///
/// Each sample carries a set of `EdgeCaseTag`s so regression reports can
/// slice metrics per scenario ("how do we do on mirror selfies?").
nonisolated enum GoldenDataset {

    /// Append-only edge-case taxonomy. New tags get added at the end; never
    /// remove or renumber existing values — historical reports reference them.
    enum EdgeCaseTag: String, Codable, CaseIterable, Sendable {
        case lowLight = "low_light"
        case mirrorSelfie = "mirror_selfie"
        case phoneOcclusion = "phone_occlusion"
        case baggyClothing = "baggy_clothing"
        case mixedMeal = "mixed_meal"
        case croppedBody = "cropped_body"
        case extremeAngle = "extreme_angle"
        case sideProfile = "side_profile"
        case fullBody = "full_body"
        case singleIngredient = "single_ingredient"
        case packaged = "packaged"
        case restaurantPlate = "restaurant_plate"
    }

    enum Kind: String, Codable, Sendable { case physique, face, meal }

    /// Immutable golden sample. `id` is stable forever — reports key on it.
    nonisolated struct Sample: Codable, Sendable, Identifiable {
        let id: String
        let kind: Kind
        let label: String
        let tags: [EdgeCaseTag]
        /// Frozen replay payload JSON (physique/face). Empty for meal samples.
        let replayPayload: String
        /// Expected score (physique/face). `nil` if not applicable.
        let expectedScore: Double?
        /// Hand-verified tolerance window for the expected score.
        let scoreTolerance: Double
        /// Expected confidence band (0...100). Used to grade calibration.
        let expectedConfidenceMin: Double
        let expectedConfidenceMax: Double
        /// Meal samples only.
        let mealDescription: String?
        let expectedFoodName: String?
        let expectedCalories: Int?
        let calorieTolerance: Int?
        let expectedPortionMultiplier: Double?
        let portionTolerance: Double?
        /// Engine versions this sample was hand-verified against. Reports
        /// flag samples whose verification version != current engine.
        let verifiedEngineVersion: String
    }

    // MARK: - Bundled golden samples
    //
    // These are hand-tuned starting fixtures. Production teams typically grow
    // this set by promoting real user scans (with consent) into goldens. The
    // important rule: once an id ships, its values never change.

    static let samples: [Sample] = [

        // ---- Physique: clean full-body front pose ----
        Sample(
            id: "phys_full_body_lean_v1",
            kind: .physique,
            label: "Lean full-body front pose",
            tags: [.fullBody],
            replayPayload: physiquePayload(
                symmetry: 0.92, swr: 1.62, wsr: 0.62,
                thighHip: 0.62, torsoAspect: 1.22, limbSym: 0.94,
                shoulderTilt: 1.4, coverage: 0.92, confidence: 0.88,
                detectedAngles: 3, navyBF: 12.0
            ),
            expectedScore: 78, scoreTolerance: 4,
            expectedConfidenceMin: 80, expectedConfidenceMax: 100,
            mealDescription: nil, expectedFoodName: nil,
            expectedCalories: nil, calorieTolerance: nil,
            expectedPortionMultiplier: nil, portionTolerance: nil,
            verifiedEngineVersion: "PhysiqueEngine_v1"
        ),

        // ---- Physique: mirror selfie, phone blocks face, torso visible ----
        Sample(
            id: "phys_mirror_phone_occlusion_v1",
            kind: .physique,
            label: "Mirror selfie with phone blocking face",
            tags: [.mirrorSelfie, .phoneOcclusion],
            replayPayload: physiquePayload(
                symmetry: 0.78, swr: 1.48, wsr: 0.68,
                thighHip: 0.58, torsoAspect: 1.18, limbSym: 0.82,
                shoulderTilt: 3.2, coverage: 0.74, confidence: 0.72,
                detectedAngles: 1, navyBF: 16.0
            ),
            expectedScore: 64, scoreTolerance: 6,
            expectedConfidenceMin: 50, expectedConfidenceMax: 78,
            mealDescription: nil, expectedFoodName: nil,
            expectedCalories: nil, calorieTolerance: nil,
            expectedPortionMultiplier: nil, portionTolerance: nil,
            verifiedEngineVersion: "PhysiqueEngine_v1"
        ),

        // ---- Physique: baggy clothing, lower confidence acceptable ----
        Sample(
            id: "phys_baggy_clothing_v1",
            kind: .physique,
            label: "Baggy clothing — silhouette only",
            tags: [.baggyClothing],
            replayPayload: physiquePayload(
                symmetry: 0.70, swr: 1.30, wsr: 0.77,
                thighHip: 0.55, torsoAspect: 1.10, limbSym: 0.70,
                shoulderTilt: 4.0, coverage: 0.68, confidence: 0.55,
                detectedAngles: 1, navyBF: 22.0
            ),
            expectedScore: 52, scoreTolerance: 7,
            expectedConfidenceMin: 35, expectedConfidenceMax: 65,
            mealDescription: nil, expectedFoodName: nil,
            expectedCalories: nil, calorieTolerance: nil,
            expectedPortionMultiplier: nil, portionTolerance: nil,
            verifiedEngineVersion: "PhysiqueEngine_v1"
        ),

        // ---- Physique: cropped (upper body only) ----
        Sample(
            id: "phys_cropped_upper_v1",
            kind: .physique,
            label: "Upper-body crop, legs missing",
            tags: [.croppedBody],
            replayPayload: physiquePayload(
                symmetry: 0.85, swr: 1.55, wsr: 0.65,
                thighHip: 0.0, torsoAspect: 1.20, limbSym: 0.88,
                shoulderTilt: 2.1, coverage: 0.55, confidence: 0.70,
                detectedAngles: 1, navyBF: 15.0
            ),
            expectedScore: 60, scoreTolerance: 6,
            expectedConfidenceMin: 45, expectedConfidenceMax: 72,
            mealDescription: nil, expectedFoodName: nil,
            expectedCalories: nil, calorieTolerance: nil,
            expectedPortionMultiplier: nil, portionTolerance: nil,
            verifiedEngineVersion: "PhysiqueEngine_v1"
        ),

        // ---- Physique: extreme angle ----
        Sample(
            id: "phys_extreme_angle_v1",
            kind: .physique,
            label: "Side / extreme angle",
            tags: [.extremeAngle, .sideProfile],
            replayPayload: physiquePayload(
                symmetry: 0.60, swr: 1.20, wsr: 0.83,
                thighHip: 0.50, torsoAspect: 1.30, limbSym: 0.60,
                shoulderTilt: 8.0, coverage: 0.80, confidence: 0.50,
                detectedAngles: 1, navyBF: 19.0
            ),
            expectedScore: 48, scoreTolerance: 8,
            expectedConfidenceMin: 30, expectedConfidenceMax: 60,
            mealDescription: nil, expectedFoodName: nil,
            expectedCalories: nil, calorieTolerance: nil,
            expectedPortionMultiplier: nil, portionTolerance: nil,
            verifiedEngineVersion: "PhysiqueEngine_v1"
        ),

        // ---- Face: clean front portrait ----
        Sample(
            id: "psl_clean_front_v1",
            kind: .face,
            label: "Clean front portrait",
            tags: [.fullBody],
            replayPayload: facePayload(
                symmetry: 0.93, thirds: 0.90,
                canthalTilt: 6.5, eyeSpacing: 0.46, jawRatio: 0.78,
                sampleCount: 1, consistency: 1.0
            ),
            expectedScore: 76, scoreTolerance: 4,
            expectedConfidenceMin: 80, expectedConfidenceMax: 100,
            mealDescription: nil, expectedFoodName: nil,
            expectedCalories: nil, calorieTolerance: nil,
            expectedPortionMultiplier: nil, portionTolerance: nil,
            verifiedEngineVersion: "PSLEngine_v1"
        ),

        // ---- Face: low light degraded ----
        Sample(
            id: "psl_low_light_v1",
            kind: .face,
            label: "Low-light face capture",
            tags: [.lowLight],
            replayPayload: facePayload(
                symmetry: 0.72, thirds: 0.74,
                canthalTilt: 3.0, eyeSpacing: 0.44, jawRatio: 0.72,
                sampleCount: 1, consistency: 0.7
            ),
            expectedScore: 58, scoreTolerance: 6,
            expectedConfidenceMin: 40, expectedConfidenceMax: 70,
            mealDescription: nil, expectedFoodName: nil,
            expectedCalories: nil, calorieTolerance: nil,
            expectedPortionMultiplier: nil, portionTolerance: nil,
            verifiedEngineVersion: "PSLEngine_v1"
        ),

        // ---- Meal: single ingredient ----
        Sample(
            id: "meal_chicken_breast_v1",
            kind: .meal,
            label: "200g grilled chicken breast",
            tags: [.singleIngredient],
            replayPayload: "",
            expectedScore: nil, scoreTolerance: 0,
            expectedConfidenceMin: 70, expectedConfidenceMax: 100,
            mealDescription: "200g grilled chicken breast",
            expectedFoodName: "chicken breast",
            expectedCalories: 330, calorieTolerance: 60,
            expectedPortionMultiplier: 2.0, portionTolerance: 0.25,
            verifiedEngineVersion: "NutritionEngine_v1"
        ),

        // ---- Meal: mixed plate ----
        Sample(
            id: "meal_chicken_rice_bowl_v1",
            kind: .meal,
            label: "Chicken rice bowl with sauce",
            tags: [.mixedMeal, .restaurantPlate],
            replayPayload: "",
            expectedScore: nil, scoreTolerance: 0,
            expectedConfidenceMin: 55, expectedConfidenceMax: 90,
            mealDescription: "chicken rice bowl with sauce",
            expectedFoodName: "chicken",
            expectedCalories: 650, calorieTolerance: 180,
            expectedPortionMultiplier: 1.0, portionTolerance: 0.5,
            verifiedEngineVersion: "NutritionEngine_v1"
        ),

        // ---- Meal: packaged ----
        Sample(
            id: "meal_protein_shake_v1",
            kind: .meal,
            label: "Protein shake and banana",
            tags: [.packaged, .mixedMeal],
            replayPayload: "",
            expectedScore: nil, scoreTolerance: 0,
            expectedConfidenceMin: 60, expectedConfidenceMax: 95,
            mealDescription: "protein shake and banana",
            expectedFoodName: "shake",
            expectedCalories: 320, calorieTolerance: 120,
            expectedPortionMultiplier: 1.0, portionTolerance: 0.4,
            verifiedEngineVersion: "NutritionEngine_v1"
        ),
    ]

    /// Filter by kind for runners that only target a single engine.
    static func samples(of kind: Kind) -> [Sample] {
        samples.filter { $0.kind == kind }
    }

    /// All samples that carry any of the given tags. Empty `tags` returns all.
    static func samples(taggedAny tags: [EdgeCaseTag]) -> [Sample] {
        guard !tags.isEmpty else { return samples }
        let set = Set(tags)
        return samples.filter { !Set($0.tags).isDisjoint(with: set) }
    }

    // MARK: - Payload builders (frozen helpers)

    /// Build a frozen replay payload JSON for a physique fixture. Encodes
    /// directly to `ReplayPayload` so the format matches what `ScanReplay`
    /// produces in production — same encoder, same key order.
    private static func physiquePayload(
        symmetry: Double, swr: Double, wsr: Double,
        thighHip: Double, torsoAspect: Double, limbSym: Double,
        shoulderTilt: Double, coverage: Double, confidence: Double,
        detectedAngles: Int, navyBF: Double
    ) -> String {
        let payload = ScanReplay.ReplayPayload(
            kind: .physique,
            engineVersion: "PhysiqueEngine_v1",
            calibrationVersion: "calibration_v1",
            calibrationSnapshot: .neutral,
            physique: ScanReplay.ReplayPayload.PhysiqueInputs(
                symmetry: symmetry,
                shoulderWaistRatio: swr,
                waistShoulderRatio: wsr,
                thighHipRatio: thighHip,
                torsoAspect: torsoAspect,
                limbSymmetry: limbSym,
                shoulderTiltDeg: shoulderTilt,
                coverageY: coverage,
                confidence: confidence,
                detectedAngles: detectedAngles,
                navyBodyFatPercent: navyBF
            ),
            face: nil
        )
        return encode(payload)
    }

    private static func facePayload(
        symmetry: Double, thirds: Double,
        canthalTilt: Double, eyeSpacing: Double, jawRatio: Double,
        sampleCount: Int, consistency: Double
    ) -> String {
        let payload = ScanReplay.ReplayPayload(
            kind: .face,
            engineVersion: "PSLEngine_v1",
            calibrationVersion: "calibration_v1",
            calibrationSnapshot: .neutral,
            physique: nil,
            face: ScanReplay.ReplayPayload.FaceInputs(
                symmetry: symmetry,
                thirds: thirds,
                canthalTiltDeg: canthalTilt,
                eyeSpacingRatio: eyeSpacing,
                jawRatio: jawRatio,
                sampleCount: sampleCount,
                consistency: consistency
            )
        )
        return encode(payload)
    }

    private static func encode(_ payload: ScanReplay.ReplayPayload) -> String {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        guard let data = try? enc.encode(payload),
              let str = String(data: data, encoding: .utf8) else { return "" }
        return str
    }
}

extension ScanReplay.ReplayPayload.CalibrationSnapshot {
    static let neutral = ScanReplay.ReplayPayload.CalibrationSnapshot(
        postureBias: 0, symmetryBias: 0, vTaperBias: 0, calorieOffsetPct: 0
    )
}
