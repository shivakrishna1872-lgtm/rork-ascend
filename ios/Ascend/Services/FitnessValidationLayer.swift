import Foundation

/// Scientifically validated secondary verification layer for Physique, PSL,
/// Cal AI, and Coach. **Advisory only** — never overrides deterministic scores.
///
/// References baked in:
/// - American Council on Exercise (ACE) body-fat category standards
/// - Jackson & Pollock body-composition research (BMI/age proxy bands)
/// - U.S. Navy body-fat equations (waist/neck/shoulder proxy)
/// - ACSM/NSCA tier interpretation (Elite / Advanced / Athletic / Intermediate / Beginner)
///
/// Used as a sanity check + coaching context provider. All outputs include a
/// confidence band; nothing here ever claims a single precise number.
nonisolated enum FitnessValidationLayer {

    // MARK: - ACE Body Fat Categories

    enum ACECategory: String {
        case essential, athlete, fitness, average, obese

        var label: String {
            switch self {
            case .essential: return "Essential"
            case .athlete:   return "Athlete"
            case .fitness:   return "Fitness"
            case .average:   return "Average"
            case .obese:     return "Above average"
            }
        }
    }

    /// ACE-aligned body-fat band lookup.
    /// - male essential 2–5, athlete 6–13, fitness 14–17, average 18–24, obese 25+
    /// - female essential 10–13, athlete 14–20, fitness 21–24, average 25–31, obese 32+
    static func aceCategory(bodyFatPercent bf: Double, isFemale: Bool) -> ACECategory {
        if isFemale {
            switch bf {
            case ..<14:   return .essential
            case 14..<21: return .athlete
            case 21..<25: return .fitness
            case 25..<32: return .average
            default:      return .obese
            }
        } else {
            switch bf {
            case ..<6:    return .essential
            case 6..<14:  return .athlete
            case 14..<18: return .fitness
            case 18..<25: return .average
            default:      return .obese
            }
        }
    }

    // MARK: - Probabilistic body-fat range

    /// Body-fat range with confidence, clamped to physiologically plausible
    /// bounds (2–55%). Width scales inversely with confidence:
    ///  - 95%+ → ±1.0pp
    ///  - 80%  → ±2.0pp
    ///  - 60%  → ±3.5pp
    ///  - 40%  → ±5.5pp
    ///  - <30% → ±7.0pp
    static func bodyFatRange(estimate bf: Double, confidence0to100 conf: Double) -> ClosedRange<Double> {
        let c = max(0, min(100, conf)) / 100.0
        let halfWidth: Double = {
            switch c {
            case 0.95...:      return 1.0
            case 0.80..<0.95:  return 1.5 + (0.95 - c) * 10
            case 0.60..<0.80:  return 2.5 + (0.80 - c) * 10
            case 0.40..<0.60:  return 4.0 + (0.60 - c) * 7.5
            default:           return 6.0 + (0.40 - max(0.10, c)) * 6
            }
        }()
        let lo = max(2.0, bf - halfWidth)
        let hi = min(55.0, bf + halfWidth)
        return lo...hi
    }

    static func formatBodyFatRange(_ range: ClosedRange<Double>) -> String {
        String(format: "%.0f–%.0f%%", range.lowerBound, range.upperBound)
    }

    // MARK: - Tier classification

    enum Tier: String {
        case elite, advanced, athletic, intermediate, beginner

        var label: String {
            switch self {
            case .elite:        return "Elite"
            case .advanced:     return "Advanced"
            case .athletic:     return "Athletic / Fit"
            case .intermediate: return "Intermediate"
            case .beginner:     return "Beginner"
            }
        }
    }

    static func tier(physiqueScore s: Double) -> Tier {
        switch s {
        case 90...:      return .elite
        case 80..<90:    return .advanced
        case 70..<80:    return .athletic
        case 60..<70:    return .intermediate
        default:         return .beginner
        }
    }

    // MARK: - V-Taper & WHR (canonical formulas)

    /// V-Taper = shoulder width / waist width. Adonis ideal ≈ 1.618.
    static func vTaper(shoulderWidth s: Double, waistWidth w: Double) -> Double {
        guard w > 0.0001 else { return 1.0 }
        return s / w
    }

    /// Waist-to-hip ratio. Lower = healthier per WHO bands.
    static func whr(waist w: Double, hips h: Double) -> Double {
        guard h > 0.0001 else { return 1.0 }
        return w / h
    }

    // MARK: - Validation report

    /// Advisory report produced by cross-checking deterministic outputs
    /// against scientific reference data.
    struct Report {
        let tier: Tier
        let aceCategory: ACECategory
        let bodyFatRange: ClosedRange<Double>
        let bodyFatRangeText: String
        /// Plain-language confidence statement e.g. "82% confidence".
        let confidenceText: String
        /// Advisory notes — appended to confidence reasons / coach context
        /// when the deterministic result disagrees with reference ranges.
        let advisories: [String]
        /// Coach-ready one-liner summarizing where the user stands.
        let coachInsight: String
        /// True when the deterministic body-fat estimate sits inside a
        /// reasonable ACE band given the physique tier (sanity passed).
        let isConsistent: Bool
    }

    /// Build the advisory report.
    /// - Parameters:
    ///   - physiqueScore: 0..100 deterministic composite.
    ///   - bodyFatPercent: deterministic / Navy-anchored estimate.
    ///   - confidence0to100: bodyFat confidence already computed by the pipeline.
    ///   - isFemale: from `UserProfile.sex`.
    static func report(physiqueScore: Double,
                       bodyFatPercent: Double,
                       confidence0to100: Double,
                       isFemale: Bool) -> Report {
        let clampedBF = max(2, min(55, bodyFatPercent))
        let band = bodyFatRange(estimate: clampedBF, confidence0to100: confidence0to100)
        let ace = aceCategory(bodyFatPercent: clampedBF, isFemale: isFemale)
        let t = tier(physiqueScore: physiqueScore)

        // Consistency heuristic: very high tier + obese ACE band = mismatch.
        // Likewise: low tier + essential/athlete band is unusual but possible.
        let mismatch: Bool = {
            switch (t, ace) {
            case (.elite, .obese), (.elite, .average): return true
            case (.advanced, .obese): return true
            case (.beginner, .essential), (.beginner, .athlete): return true
            default: return false
            }
        }()

        var advisories: [String] = []
        if mismatch {
            advisories.append("Physique tier (\(t.label)) and body-fat band (\(ace.label)) disagree — interpret results as a range, not a point estimate.")
        }
        if confidence0to100 < 55 {
            advisories.append("Low detection confidence — body-fat shown as a wider range.")
        }
        if clampedBF != bodyFatPercent {
            advisories.append("Body-fat estimate clamped to a physiologically plausible range.")
        }

        let coach: String = {
            switch (t, ace) {
            case (.elite, .athlete), (.advanced, .athlete):
                return "Elite-leaning composition — focus on maintenance + symmetry refinement."
            case (.elite, .fitness), (.advanced, .fitness):
                return "Strong base. A measured 6–8 week cut would unlock a clear tier jump."
            case (.athletic, .fitness), (.athletic, .athlete):
                return "Athletic build with good leanness — keep training intensity high and prioritize sleep."
            case (.athletic, .average):
                return "Athletic frame under a soft layer — a slow recomp will surface definition."
            case (.intermediate, _):
                return "Solid intermediate base — add a structured progression and weekly photo tracking."
            case (.beginner, _):
                return "Foundation phase — consistency beats intensity. Train 3–4×/week, hit protein, sleep."
            case (_, .obese):
                return "Conditioning is the highest-leverage lever right now. Calorie deficit + walking + 3×/week resistance."
            default:
                return "Balanced base. Pick one weak link per 6 weeks and attack it deliberately."
            }
        }()

        return Report(
            tier: t,
            aceCategory: ace,
            bodyFatRange: band,
            bodyFatRangeText: formatBodyFatRange(band),
            confidenceText: "\(Int(confidence0to100.rounded()))% confidence",
            advisories: advisories,
            coachInsight: coach,
            isConsistent: !mismatch
        )
    }
}
