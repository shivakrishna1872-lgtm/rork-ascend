import Foundation

/// Final safety gate between AI responses and the deterministic core.
///
/// The AI is **only** allowed to produce text (insight, recommendations,
/// archetype label, coaching copy). This validator rejects any AI payload
/// that smuggles in numeric fields or structured score-like data.
///
/// Authority hierarchy reminder:
/// ```
/// Deterministic Engine > Vision Anchors > Calibration > Cache > AI
/// ```
/// `AISchemaLock` enforces "AI is the weakest layer" at the boundary.
nonisolated enum AISchemaLock {

    /// Field names the AI must NEVER attempt to set. Matched case-insensitively
    /// against both raw JSON keys and free text on its own line.
    static let forbiddenScoreFields: Set<String> = [
        "psl_score", "pslscore", "psl",
        "physique_score", "physiquescore",
        "symmetry_score", "symmetry",
        "posture_score", "posture",
        "body_balance", "bodybalance",
        "body_composition", "bodycomposition",
        "muscularity", "muscularity_score",
        "conditioning", "conditioning_score",
        "leanness", "v_taper", "vtaper", "v_taper_score",
        "body_fat", "bodyfat", "body_fat_percent", "bf_percent",
        "jawline", "jawline_score",
        "thirds", "thirds_score",
        "canthal_tilt", "canthaltilt",
        "eye_spacing", "eyespacing",
        "glow_up", "glow_up_potential",
        "confidence", "confidence_score",
        "calories", "calorie_estimate", "kcal",
        "protein_g", "carbs_g", "fats_g",
        "calibration", "calibration_bias",
        "posturebias", "symmetrybias", "vtaperbias",
        "calorieoffsetpct"
    ]

    /// Outcome of validating an AI text payload.
    nonisolated enum Outcome: Equatable {
        /// Safe — AI produced only narrative text. Use as-is.
        case clean(String)
        /// AI tried to output scores. Forbidden fields were stripped; safe
        /// remainder returned. Calling code should ignore numeric content.
        case sanitized(String, removed: [String])
        /// Payload is too compromised (mostly structured numeric output) to
        /// salvage. Caller must discard and fall back to deterministic copy.
        case rejected(reason: String)
    }

    // MARK: - Public API

    /// Validate a free-text AI response (insight, recommendation, etc.).
    /// - Returns: `.clean` for safe text, `.sanitized` if score lines were
    ///   stripped, `.rejected` if the response is mostly score smuggling.
    static func validateText(_ raw: String) -> Outcome {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .rejected(reason: "empty") }

        // If the AI returned a JSON object, parse it and check keys.
        if let jsonOutcome = validateAsJSON(trimmed) { return jsonOutcome }

        // Otherwise scrub line-by-line for `field: 87` style score smuggling.
        var kept: [String] = []
        var removed: [String] = []
        let lines = trimmed.components(separatedBy: .newlines)
        for line in lines {
            if let field = forbiddenFieldOnLine(line) {
                removed.append(field)
            } else {
                kept.append(line)
            }
        }

        let keptText = kept.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        if removed.isEmpty { return .clean(keptText) }

        // If more than half the lines were score lines, reject entirely.
        if removed.count > lines.count / 2 || keptText.count < 20 {
            return .rejected(reason: "score-smuggling: \(removed.joined(separator: ","))")
        }
        return .sanitized(keptText, removed: removed)
    }

    /// Validate an array of short strings (e.g. recommendations). Drops any
    /// item containing a forbidden field or a numeric-only score line.
    static func validateList(_ items: [String]) -> [String] {
        items.compactMap { item in
            switch validateText(item) {
            case .clean(let t): return t.isEmpty ? nil : t
            case .sanitized(let t, _): return t.isEmpty ? nil : t
            case .rejected: return nil
            }
        }
    }

    /// Validate a short archetype/label string. Labels must be alphabetic.
    static func validateLabel(_ raw: String) -> String? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, t.count <= 40 else { return nil }
        // Labels are words. Reject anything with digits or score punctuation.
        if t.rangeOfCharacter(from: .decimalDigits) != nil { return nil }
        if t.contains(":") || t.contains("=") || t.contains("{") { return nil }
        return t
    }

    // MARK: - Internals

    private static func validateAsJSON(_ raw: String) -> Outcome? {
        guard raw.hasPrefix("{") || raw.hasPrefix("[") else { return nil }
        guard let data = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) else { return nil }

        var removed: [String] = []
        func scan(_ any: Any) {
            if let dict = any as? [String: Any] {
                for (k, v) in dict {
                    if forbiddenScoreFields.contains(k.lowercased()) {
                        removed.append(k)
                    }
                    scan(v)
                }
            } else if let arr = any as? [Any] {
                for item in arr { scan(item) }
            }
        }
        scan(obj)
        if removed.isEmpty { return .clean(raw) }
        return .rejected(reason: "structured score output: \(removed.joined(separator: ","))")
    }

    /// Returns the forbidden field name if the line looks like `field: number`
    /// or `"field": number`. Free-prose mentions ("your symmetry looks good")
    /// are allowed.
    private static func forbiddenFieldOnLine(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        // Require a key:value or key=value shape with a number on the RHS.
        let separators: [Character] = [":", "="]
        guard let sepIdx = trimmed.firstIndex(where: { separators.contains($0) }) else { return nil }
        let key = trimmed[..<sepIdx]
            .trimmingCharacters(in: CharacterSet(charactersIn: " \t\"'-•*"))
            .lowercased()
        let value = trimmed[trimmed.index(after: sepIdx)...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard forbiddenScoreFields.contains(key) else { return nil }
        // RHS must look numeric (a digit somewhere in the first 8 chars) for
        // this to be score smuggling — "Recommendation: walk more" is fine.
        let head = value.prefix(8)
        guard head.contains(where: { $0.isNumber }) else { return nil }
        return key
    }
}
