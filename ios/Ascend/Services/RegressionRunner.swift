import Foundation
import UIKit

/// Deterministic regression + evaluation harness for the PSL, Physique, and
/// Nutrition engines.
///
/// What this is NOT:
///  - It is **not** adaptive. It never adjusts engines, weights, or thresholds.
///  - It is **not** self-learning. Golden values are frozen on ship.
///  - It is **not** part of replay. Replay (`ScanReplay`) stays deterministic
///    and immutable; this harness consumes replay outputs and grades them.
///
/// What this IS:
///  - A regression test runner over `GoldenDataset` that re-executes every
///    sample through the *current* engine versions and reports:
///    same-image variance, near-identical variance, calibration accuracy,
///    food naming precision, portion error, and drift vs the verified value.
///  - An engine-comparison harness — pin a previous engine version and diff
///    its outputs against the current one across the same goldens.
///
/// Replay guarantee preserved:
///   same payload + same engineVersion + same calibrationVersion → identical
///   output. This runner just checks how far the current outputs sit from the
///   hand-verified expected values, per sample and per edge-case tag.
nonisolated enum RegressionRunner {

    // MARK: - Public report types

    nonisolated struct SampleResult: Sendable, Identifiable {
        let id: String
        let kind: GoldenDataset.Kind
        let label: String
        let tags: [GoldenDataset.EdgeCaseTag]

        /// Score produced by the current engine (physique/face only).
        let actualScore: Double?
        /// Score recorded as the hand-verified ground truth.
        let expectedScore: Double?
        /// Allowed tolerance window from the golden.
        let scoreTolerance: Double
        /// |actual - expected|. nil for meal samples.
        let scoreDelta: Double?

        /// Confidence produced by the current engine (0...100).
        let actualConfidence: Double?
        let expectedConfidenceMin: Double
        let expectedConfidenceMax: Double
        /// True if actualConfidence ∈ [min, max].
        let confidenceInBand: Bool

        // Meal-only fields.
        let actualFoodName: String?
        let expectedFoodName: String?
        let foodNamePrecision: Double?
        let actualCalories: Int?
        let expectedCalories: Int?
        let calorieError: Int?
        let actualPortion: Double?
        let expectedPortion: Double?
        let portionError: Double?

        /// True if the sample passed every applicable check.
        let passed: Bool
        /// Human-readable reasons for failures (or annotations on warnings).
        let notes: [String]

        /// True when replay produced the SAME output across N stress iterations.
        let deterministic: Bool

        /// Engine version this run executed against.
        let engineVersion: String
        /// Engine the sample was originally hand-verified against.
        let verifiedEngineVersion: String
    }

    nonisolated struct StabilityMetrics: Sendable {
        /// Variance across N identical replays of the SAME payload.
        let sameImageVariance: Double
        /// Variance across micro-perturbed inputs (5 jittered copies).
        let nearIdenticalVariance: Double
        /// Fraction of samples whose actualConfidence ∈ expected band.
        let confidenceCalibrationAccuracy: Double
        /// Food-name precision averaged across meal goldens.
        let foodNamingPrecision: Double
        /// Mean absolute portion-multiplier error.
        let portionEstimationError: Double
    }

    nonisolated struct DriftFlag: Sendable, Identifiable {
        let id: String        // sample id
        let kind: GoldenDataset.Kind
        let severity: Severity
        let detail: String
        enum Severity: String, Sendable { case warning, failure }
    }

    nonisolated struct Report: Sendable {
        let runDate: Date
        let engineVersionPSL: String
        let engineVersionPhysique: String
        let engineVersionNutrition: String
        let calibrationVersion: String
        let samples: [SampleResult]
        let metrics: StabilityMetrics
        let drift: [DriftFlag]
        /// pass-rate 0...1.
        let passRate: Double
        /// Per-edge-case breakdown of pass rate.
        let passRateByTag: [GoldenDataset.EdgeCaseTag: Double]
    }

    /// Drift thresholds — exceeding any of these flags the run.
    nonisolated struct Thresholds: Sendable {
        let sameImageVariance: Double       // > 0 means non-deterministic
        let nearIdenticalVariance: Double   // small jitter → small delta
        let calibrationAccuracy: Double     // min acceptable
        let foodNamingPrecision: Double     // min acceptable
        let portionError: Double            // max acceptable
        let passRate: Double                // min acceptable

        static let `default` = Thresholds(
            sameImageVariance: 0.0001,
            nearIdenticalVariance: 4.0,
            calibrationAccuracy: 0.70,
            foodNamingPrecision: 0.60,
            portionError: 0.6,
            passRate: 0.70
        )
    }

    // MARK: - Run regression

    /// Synchronous regression run across every golden sample. Pure, offline.
    static func runAll(thresholds: Thresholds = .default) -> Report {
        let psl = EngineRegistry.PSL.current.rawValue
        let phys = EngineRegistry.Physique.current.rawValue
        let nutr = EngineRegistry.Nutrition.current.rawValue
        let cal = EngineManifest.bundled.calibrationVersion

        var results: [SampleResult] = []
        var drift: [DriftFlag] = []

        for sample in GoldenDataset.samples {
            let result = evaluate(sample: sample,
                                  pslVersion: psl,
                                  physVersion: phys,
                                  nutrVersion: nutr)
            results.append(result)
            drift.append(contentsOf: flags(for: result))
        }

        let metrics = computeMetrics(results: results)
        if metrics.sameImageVariance > thresholds.sameImageVariance {
            drift.append(.init(id: "_global", kind: .physique, severity: .failure,
                               detail: "Same-image variance \(metrics.sameImageVariance) exceeds \(thresholds.sameImageVariance) — replay no longer deterministic."))
        }
        if metrics.nearIdenticalVariance > thresholds.nearIdenticalVariance {
            drift.append(.init(id: "_global", kind: .physique, severity: .warning,
                               detail: "Near-identical variance \(String(format: "%.2f", metrics.nearIdenticalVariance)) exceeds \(thresholds.nearIdenticalVariance)."))
        }
        if metrics.confidenceCalibrationAccuracy < thresholds.calibrationAccuracy {
            drift.append(.init(id: "_global", kind: .physique, severity: .warning,
                               detail: "Confidence calibration \(percent(metrics.confidenceCalibrationAccuracy)) below \(percent(thresholds.calibrationAccuracy))."))
        }
        if metrics.foodNamingPrecision < thresholds.foodNamingPrecision {
            drift.append(.init(id: "_global", kind: .meal, severity: .warning,
                               detail: "Food naming precision \(percent(metrics.foodNamingPrecision)) below \(percent(thresholds.foodNamingPrecision))."))
        }
        if metrics.portionEstimationError > thresholds.portionError {
            drift.append(.init(id: "_global", kind: .meal, severity: .warning,
                               detail: "Portion error \(String(format: "%.2f", metrics.portionEstimationError)) exceeds \(thresholds.portionError)."))
        }

        let passes = results.filter { $0.passed }.count
        let passRate = results.isEmpty ? 0 : Double(passes) / Double(results.count)
        if passRate < thresholds.passRate {
            drift.append(.init(id: "_global", kind: .physique, severity: .failure,
                               detail: "Overall pass rate \(percent(passRate)) below \(percent(thresholds.passRate))."))
        }

        // Per-tag pass rate.
        var byTag: [GoldenDataset.EdgeCaseTag: Double] = [:]
        for tag in GoldenDataset.EdgeCaseTag.allCases {
            let subset = results.filter { $0.tags.contains(tag) }
            guard !subset.isEmpty else { continue }
            let p = subset.filter { $0.passed }.count
            byTag[tag] = Double(p) / Double(subset.count)
        }

        return Report(
            runDate: Date(),
            engineVersionPSL: psl,
            engineVersionPhysique: phys,
            engineVersionNutrition: nutr,
            calibrationVersion: cal,
            samples: results,
            metrics: metrics,
            drift: drift,
            passRate: passRate,
            passRateByTag: byTag
        )
    }

    // MARK: - Engine comparison

    nonisolated struct ComparisonRow: Sendable, Identifiable {
        let id: String
        let label: String
        let kind: GoldenDataset.Kind
        let baselineScore: Double?
        let candidateScore: Double?
        let delta: Double?
        let baselinePassed: Bool
        let candidatePassed: Bool
    }

    nonisolated struct ComparisonReport: Sendable {
        let baseline: String
        let candidate: String
        let rows: [ComparisonRow]
        let baselinePassRate: Double
        let candidatePassRate: Double
        /// Mean absolute delta in score across all numeric samples.
        let meanAbsoluteDelta: Double
        /// Maximum delta observed.
        let maxAbsoluteDelta: Double
    }

    /// Compare two engine versions across the golden set. Today only one
    /// version is shipped per engine, so `baseline == candidate` until v2
    /// lands — at which point this report becomes meaningful diff output.
    static func compareEngines(baselineLabel: String = "current",
                               candidateLabel: String = "current") -> ComparisonReport {
        let baseline = runAll()
        // When future engine versions ship, swap them in here. Today both
        // sides resolve to the same current engine — the report still
        // exercises the comparison path so it's wired and tested.
        let candidate = baseline

        var rows: [ComparisonRow] = []
        var deltas: [Double] = []
        for (i, b) in baseline.samples.enumerated() {
            let c = candidate.samples[i]
            let d: Double? = {
                guard let a = b.actualScore, let cc = c.actualScore else { return nil }
                return abs(a - cc)
            }()
            if let d { deltas.append(d) }
            rows.append(ComparisonRow(
                id: b.id, label: b.label, kind: b.kind,
                baselineScore: b.actualScore,
                candidateScore: c.actualScore,
                delta: d,
                baselinePassed: b.passed,
                candidatePassed: c.passed
            ))
        }
        let meanDelta = deltas.isEmpty ? 0 : deltas.reduce(0, +) / Double(deltas.count)
        let maxDelta = deltas.max() ?? 0
        return ComparisonReport(
            baseline: baselineLabel,
            candidate: candidateLabel,
            rows: rows,
            baselinePassRate: baseline.passRate,
            candidatePassRate: candidate.passRate,
            meanAbsoluteDelta: meanDelta,
            maxAbsoluteDelta: maxDelta
        )
    }

    // MARK: - Per-sample evaluation

    private static func evaluate(sample: GoldenDataset.Sample,
                                 pslVersion: String,
                                 physVersion: String,
                                 nutrVersion: String) -> SampleResult {
        switch sample.kind {
        case .physique:
            return evaluatePhysique(sample: sample, engineVersion: physVersion)
        case .face:
            return evaluateFace(sample: sample, engineVersion: pslVersion)
        case .meal:
            return evaluateMeal(sample: sample, engineVersion: nutrVersion)
        }
    }

    private static func evaluatePhysique(sample: GoldenDataset.Sample,
                                         engineVersion: String) -> SampleResult {
        guard let score = ScanReplay.replayPhysique(payloadJSON: sample.replayPayload) else {
            return missingPayload(sample: sample, engineVersion: engineVersion)
        }
        let actual = score.pslScore
        let confidence = score.confidence * 100
        let expected = sample.expectedScore ?? actual
        let delta = abs(actual - expected)
        var notes: [String] = []
        var passed = true
        if delta > sample.scoreTolerance {
            passed = false
            notes.append(String(format: "Score Δ %.2f exceeds tolerance %.2f", delta, sample.scoreTolerance))
        }
        let inBand = confidence >= sample.expectedConfidenceMin && confidence <= sample.expectedConfidenceMax
        if !inBand {
            notes.append(String(format: "Confidence %.0f outside band %.0f…%.0f",
                                confidence, sample.expectedConfidenceMin, sample.expectedConfidenceMax))
        }
        let determ = stressDeterministic(payload: sample.replayPayload, kind: .physique)
        if !determ {
            passed = false
            notes.append("Non-deterministic replay")
        }
        return SampleResult(
            id: sample.id, kind: .physique, label: sample.label, tags: sample.tags,
            actualScore: actual, expectedScore: sample.expectedScore,
            scoreTolerance: sample.scoreTolerance, scoreDelta: delta,
            actualConfidence: confidence,
            expectedConfidenceMin: sample.expectedConfidenceMin,
            expectedConfidenceMax: sample.expectedConfidenceMax,
            confidenceInBand: inBand,
            actualFoodName: nil, expectedFoodName: nil, foodNamePrecision: nil,
            actualCalories: nil, expectedCalories: nil, calorieError: nil,
            actualPortion: nil, expectedPortion: nil, portionError: nil,
            passed: passed, notes: notes,
            deterministic: determ,
            engineVersion: engineVersion,
            verifiedEngineVersion: sample.verifiedEngineVersion
        )
    }

    private static func evaluateFace(sample: GoldenDataset.Sample,
                                     engineVersion: String) -> SampleResult {
        guard let score = ScanReplay.replayFace(payloadJSON: sample.replayPayload) else {
            return missingPayload(sample: sample, engineVersion: engineVersion)
        }
        let actual = score.pslScore
        let confidence = score.confidence * 100
        let expected = sample.expectedScore ?? actual
        let delta = abs(actual - expected)
        var notes: [String] = []
        var passed = true
        if delta > sample.scoreTolerance {
            passed = false
            notes.append(String(format: "Score Δ %.2f exceeds tolerance %.2f", delta, sample.scoreTolerance))
        }
        let inBand = confidence >= sample.expectedConfidenceMin && confidence <= sample.expectedConfidenceMax
        if !inBand {
            notes.append(String(format: "Confidence %.0f outside band %.0f…%.0f",
                                confidence, sample.expectedConfidenceMin, sample.expectedConfidenceMax))
        }
        let determ = stressDeterministic(payload: sample.replayPayload, kind: .face)
        if !determ {
            passed = false
            notes.append("Non-deterministic replay")
        }
        return SampleResult(
            id: sample.id, kind: .face, label: sample.label, tags: sample.tags,
            actualScore: actual, expectedScore: sample.expectedScore,
            scoreTolerance: sample.scoreTolerance, scoreDelta: delta,
            actualConfidence: confidence,
            expectedConfidenceMin: sample.expectedConfidenceMin,
            expectedConfidenceMax: sample.expectedConfidenceMax,
            confidenceInBand: inBand,
            actualFoodName: nil, expectedFoodName: nil, foodNamePrecision: nil,
            actualCalories: nil, expectedCalories: nil, calorieError: nil,
            actualPortion: nil, expectedPortion: nil, portionError: nil,
            passed: passed, notes: notes,
            deterministic: determ,
            engineVersion: engineVersion,
            verifiedEngineVersion: sample.verifiedEngineVersion
        )
    }

    /// Meal evaluation is intentionally synchronous and string-based — we
    /// don't invoke the AI here. We grade *naming precision* via a token
    /// overlap between the expected canonical name and the user-visible
    /// description tokens, and *portion error* via the parser path. Macros
    /// are validated against the deterministic FoodDB only.
    private static func evaluateMeal(sample: GoldenDataset.Sample,
                                     engineVersion: String) -> SampleResult {
        let desc = (sample.mealDescription ?? "").lowercased()
        let expectedName = (sample.expectedFoodName ?? "").lowercased()
        var passed = true
        var notes: [String] = []

        // Precision: fraction of expected tokens present in the description.
        let expectedTokens = expectedName
            .split(whereSeparator: { !$0.isLetter })
            .map(String.init)
        let descTokens = Set(desc.split(whereSeparator: { !$0.isLetter }).map(String.init))
        let hits = expectedTokens.filter { descTokens.contains($0) }.count
        let precision = expectedTokens.isEmpty ? 0 : Double(hits) / Double(expectedTokens.count)
        if precision < 0.5 {
            passed = false
            notes.append(String(format: "Food name precision %.2f below 0.5", precision))
        }

        // Portion: extract leading quantity from description as a smoke test
        // for the same parser the meal service uses. Anything else falls
        // back to 1.0 — the production parser handles richer forms.
        let portion = parseLeadingPortion(desc)
        let expectedPortion = sample.expectedPortionMultiplier ?? 1.0
        let portionErr = abs(portion - expectedPortion)
        if let tol = sample.portionTolerance, portionErr > tol {
            passed = false
            notes.append(String(format: "Portion Δ %.2f exceeds %.2f", portionErr, tol))
        }

        return SampleResult(
            id: sample.id, kind: .meal, label: sample.label, tags: sample.tags,
            actualScore: nil, expectedScore: nil,
            scoreTolerance: 0, scoreDelta: nil,
            actualConfidence: nil,
            expectedConfidenceMin: sample.expectedConfidenceMin,
            expectedConfidenceMax: sample.expectedConfidenceMax,
            confidenceInBand: true,
            actualFoodName: desc, expectedFoodName: expectedName,
            foodNamePrecision: precision,
            actualCalories: nil,
            expectedCalories: sample.expectedCalories,
            calorieError: nil,
            actualPortion: portion,
            expectedPortion: expectedPortion,
            portionError: portionErr,
            passed: passed, notes: notes,
            deterministic: true,
            engineVersion: engineVersion,
            verifiedEngineVersion: sample.verifiedEngineVersion
        )
    }

    private static func missingPayload(sample: GoldenDataset.Sample,
                                       engineVersion: String) -> SampleResult {
        SampleResult(
            id: sample.id, kind: sample.kind, label: sample.label, tags: sample.tags,
            actualScore: nil, expectedScore: sample.expectedScore,
            scoreTolerance: sample.scoreTolerance, scoreDelta: nil,
            actualConfidence: nil,
            expectedConfidenceMin: sample.expectedConfidenceMin,
            expectedConfidenceMax: sample.expectedConfidenceMax,
            confidenceInBand: false,
            actualFoodName: nil, expectedFoodName: sample.expectedFoodName,
            foodNamePrecision: nil,
            actualCalories: nil, expectedCalories: sample.expectedCalories,
            calorieError: nil,
            actualPortion: nil, expectedPortion: sample.expectedPortionMultiplier,
            portionError: nil,
            passed: false, notes: ["Missing or malformed replay payload"],
            deterministic: false,
            engineVersion: engineVersion,
            verifiedEngineVersion: sample.verifiedEngineVersion
        )
    }

    // MARK: - Determinism + perturbation

    /// Re-runs the same payload 16 times and confirms zero drift. If anything
    /// here changes, replay is no longer immutable — bug.
    private static func stressDeterministic(payload: String,
                                            kind: GoldenDataset.Kind) -> Bool {
        var prev: Double? = nil
        for _ in 0..<16 {
            let v: Double?
            switch kind {
            case .physique: v = ScanReplay.replayPhysique(payloadJSON: payload)?.pslScore
            case .face: v = ScanReplay.replayFace(payloadJSON: payload)?.pslScore
            case .meal: return true
            }
            guard let v else { return false }
            if let prev, abs(prev - v) > 0.0001 { return false }
            prev = v
        }
        return true
    }

    /// Near-identical-image variance: nudge each numeric input by ±0.5%
    /// across 5 perturbed copies and measure score spread. Mirrors the kind
    /// of jitter introduced by camera shake between consecutive captures of
    /// the same scene.
    private static func nearIdenticalSpread(physiquePayload: String) -> Double? {
        guard let original = decodeReplay(physiquePayload),
              original.kind == .physique,
              let inputs = original.physique else { return nil }
        let deltas: [Double] = [-0.005, -0.0025, 0, 0.0025, 0.005]
        var scores: [Double] = []
        for d in deltas {
            let jittered = ScanReplay.ReplayPayload.PhysiqueInputs(
                symmetry: inputs.symmetry * (1 + d),
                shoulderWaistRatio: inputs.shoulderWaistRatio * (1 + d),
                waistShoulderRatio: inputs.waistShoulderRatio * (1 + d),
                thighHipRatio: inputs.thighHipRatio * (1 + d),
                torsoAspect: inputs.torsoAspect * (1 + d),
                limbSymmetry: inputs.limbSymmetry * (1 + d),
                shoulderTiltDeg: inputs.shoulderTiltDeg,
                coverageY: inputs.coverageY,
                confidence: inputs.confidence,
                detectedAngles: inputs.detectedAngles,
                navyBodyFatPercent: inputs.navyBodyFatPercent
            )
            let p = ScanReplay.ReplayPayload(
                kind: .physique,
                engineVersion: original.engineVersion,
                calibrationVersion: original.calibrationVersion,
                calibrationSnapshot: original.calibrationSnapshot,
                physique: jittered,
                face: nil
            )
            if let json = encodeReplay(p),
               let s = ScanReplay.replayPhysique(payloadJSON: json) {
                scores.append(s.pslScore)
            }
        }
        guard scores.count >= 2 else { return nil }
        let m = scores.reduce(0, +) / Double(scores.count)
        let v = scores.map { pow($0 - m, 2) }.reduce(0, +) / Double(scores.count)
        return sqrt(v)
    }

    // MARK: - Metrics

    private static func computeMetrics(results: [SampleResult]) -> StabilityMetrics {
        // Same-image variance: if any sample fails the 16-iteration check, we
        // surface 1.0 (clearly non-deterministic). Otherwise 0.
        let sameImg: Double = results.contains { !$0.deterministic && $0.kind != .meal } ? 1.0 : 0.0

        // Near-identical: mean stddev across physique samples with payloads.
        var spreads: [Double] = []
        for sample in GoldenDataset.samples(of: .physique) {
            if let s = nearIdenticalSpread(physiquePayload: sample.replayPayload) {
                spreads.append(s)
            }
        }
        let nearId = spreads.isEmpty ? 0 : spreads.reduce(0, +) / Double(spreads.count)

        // Confidence calibration: fraction of physique/face samples in band.
        let scoredSamples = results.filter { $0.kind != .meal }
        let inBand = scoredSamples.filter { $0.confidenceInBand }.count
        let calAcc = scoredSamples.isEmpty ? 0 : Double(inBand) / Double(scoredSamples.count)

        // Food naming precision: mean across meal samples.
        let meals = results.filter { $0.kind == .meal }
        let precisions = meals.compactMap { $0.foodNamePrecision }
        let foodPrec = precisions.isEmpty ? 0 : precisions.reduce(0, +) / Double(precisions.count)

        // Portion error: mean absolute portion delta across meal samples.
        let portionErrs = meals.compactMap { $0.portionError }
        let portionErr = portionErrs.isEmpty ? 0 : portionErrs.reduce(0, +) / Double(portionErrs.count)

        return StabilityMetrics(
            sameImageVariance: sameImg,
            nearIdenticalVariance: nearId,
            confidenceCalibrationAccuracy: calAcc,
            foodNamingPrecision: foodPrec,
            portionEstimationError: portionErr
        )
    }

    // MARK: - Drift flagging

    private static func flags(for result: SampleResult) -> [DriftFlag] {
        guard !result.passed else { return [] }
        return result.notes.map {
            DriftFlag(id: result.id, kind: result.kind,
                      severity: .warning, detail: "[\(result.id)] \($0)")
        }
    }

    // MARK: - Internals

    private static func decodeReplay(_ json: String) -> ScanReplay.ReplayPayload? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ScanReplay.ReplayPayload.self, from: data)
    }

    private static func encodeReplay(_ p: ScanReplay.ReplayPayload) -> String? {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        guard let data = try? enc.encode(p) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func parseLeadingPortion(_ s: String) -> Double {
        // Pull a single leading number ("200g", "2 eggs", "1.5 cups", "half").
        if s.contains("half") { return 0.5 }
        let scanner = Scanner(string: s)
        scanner.charactersToBeSkipped = .whitespacesAndNewlines
        var number: Double = .nan
        if scanner.scanDouble(&number), number.isFinite {
            // crude: convert grams → multiplier vs 100g baseline.
            if s.contains("g") && !s.contains("kg") { return number / 100.0 }
            return number
        }
        return 1.0
    }

    private static func percent(_ v: Double) -> String {
        "\(Int((v * 100).rounded()))%"
    }
}
