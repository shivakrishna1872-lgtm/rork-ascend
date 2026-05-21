import Foundation
import UIKit

// MARK: - DTOs (nonisolated: decoded on background)

nonisolated struct PhysiqueAnalysis: Codable {
    let physiqueScore: Double
    let symmetry: Double
    let muscularity: Double
    let conditioning: Double
    let vTaper: Double
    let bodyFatPercent: Double
    let bodyFatConfidence: Double
    let archetype: String
    let insight: String
    let recommendations: [String]
}

nonisolated struct FaceAnalysis: Codable {
    let overall: Double
    let symmetry: Double
    let jawline: Double
    let thirds: Double
    let canthalTilt: Double
    let eyeSpacing: Double
    let glowUpPotential: Double
    let insight: String
    let recommendations: [String]
    let hairstyles: [String]
}

nonisolated struct MealIngredient: Codable, Hashable {
    let name: String
    let portion: String

    enum CodingKeys: String, CodingKey { case name, portion }

    init(name: String, portion: String) {
        self.name = name; self.portion = portion
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.name = (try? c.decode(String.self, forKey: .name)) ?? ""
        self.portion = (try? c.decode(String.self, forKey: .portion)) ?? ""
    }
}

nonisolated struct MealAnalysis: Codable {
    let name: String
    let dishType: String
    let ingredients: [MealIngredient]
    let calories: Int
    let proteinG: Int
    let carbsG: Int
    let fatsG: Int
    let confidence: Int
    let note: String

    enum CodingKeys: String, CodingKey {
        case name, dishType, ingredients, calories, proteinG, carbsG, fatsG, confidence, note
    }

    init(name: String, dishType: String = "", ingredients: [MealIngredient] = [], calories: Int, proteinG: Int, carbsG: Int, fatsG: Int, confidence: Int, note: String) {
        self.name = name; self.dishType = dishType; self.ingredients = ingredients
        self.calories = calories
        self.proteinG = proteinG; self.carbsG = carbsG; self.fatsG = fatsG
        self.confidence = confidence; self.note = note
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.name = (try? c.decode(String.self, forKey: .name)) ?? "Meal"
        self.dishType = (try? c.decode(String.self, forKey: .dishType)) ?? ""
        self.ingredients = (try? c.decode([MealIngredient].self, forKey: .ingredients)) ?? []
        self.calories = max(0, min(4000, (try? c.decode(Int.self, forKey: .calories)) ?? 0))
        self.proteinG = max(0, min(300, (try? c.decode(Int.self, forKey: .proteinG)) ?? 0))
        self.carbsG   = max(0, min(500, (try? c.decode(Int.self, forKey: .carbsG)) ?? 0))
        self.fatsG    = max(0, min(300, (try? c.decode(Int.self, forKey: .fatsG)) ?? 0))
        self.confidence = max(0, min(100, (try? c.decode(Int.self, forKey: .confidence)) ?? 70))
        self.note = (try? c.decode(String.self, forKey: .note)) ?? ""
    }
}

nonisolated struct DailyInsight: Codable {
    let headline: String
    let detail: String
}

nonisolated enum AIServiceError: LocalizedError {
    case missingConfig
    case http(Int)
    case decode
    case empty
    case consentDenied
    var errorDescription: String? {
        switch self {
        case .missingConfig: "AI service is not configured."
        case .http(let c):
            switch c {
            case 413: "Photos were too large to send. Try fewer or smaller photos."
            case 408, 504: "The analysis timed out. Please try again."
            case 429: "Too many requests right now. Please wait a moment and retry."
            case 402: "The AI provider is temporarily unavailable. Please try again in a moment."
            case 401, 403: "AI service is not authorized. Please contact support."
            case 500...599: "The AI service is briefly unavailable. Please try again."
            default: "AI request failed (\(c))."
            }
        case .decode:        "Could not interpret AI response."
        case .empty:         "AI returned an empty response."
        case .consentDenied: "AI analysis is turned off. Enable it in Profile → Privacy to score with AI."
        }
    }
}

nonisolated struct AIService {
    static let shared = AIService()

    private var baseURL: String { Config.EXPO_PUBLIC_TOOLKIT_URL }
    private var key: String { Config.EXPO_PUBLIC_RORK_TOOLKIT_SECRET_KEY }
    private let model = "google/gemini-2.5-flash"
    private let fallbackModels = ["openai/gpt-4o-mini", "anthropic/claude-haiku-4.5"]

    // MARK: - Public APIs

    func analyzePhysique(front: UIImage, side: UIImage, back: UIImage, profile: ProfileSnapshot, history: ScoreHistory? = nil, anchors: PhysiqueAnchors? = nil) async throws -> PhysiqueAnalysis {
        let anchorBlock: String = {
            guard let a = anchors else { return "(no on-device pose anchors available)" }
            return """
            ON-DEVICE POSE ANCHORS (MediaPipe/Vision-equivalent, averaged across visible angles — anchor your scores here):
            - measured_symmetry_index: \(Int(a.symmetry * 100))/100 (front+back weighted)
            - shoulder_waist_ratio: \(String(format: "%.2f", a.shoulderWaistRatio)) (>1.5 = strong V-taper)
            - body_coverage_y: \(Int(a.coverageY * 100))% of frame (higher = more body visible)
            - average_landmark_confidence: \(Int(a.confidence * 100))/100
            - angles_with_body_detected: \(a.detectedAngles) of 3
            Use these to anchor symmetry, vTaper, and bodyFatConfidence. Do NOT contradict them by more than 8 points unless the visual evidence is overwhelming.
            """
        }()
        let anchorLine: String = {
            guard let h = history, !h.isEmpty else { return "PERSONAL CALIBRATION: (none — first analysis; rely on photos only)" }
            return """
            PERSONAL CALIBRATION DATA (the model self-trains from this user's prior scans — trust it):
            \(h.summary)
            
            How to use it:
            - The mean ± std is this user's learned baseline. Stay WITHIN ±1 std unless the new photos clearly justify movement.
            - Low std on a metric → high confidence in that baseline → do NOT swing it by more than 2-3 points.
            - High std on a metric → noisier history → you may correct more, but stay anchored to the mean.
            - Honor the recent trend direction — do not flip the sign without strong visual evidence.
            """
        }()
        let prompt = """
        You are Ascend Life, a precise, encouraging physique-analysis coach. Analyze three photos (front, side, back) of an athlete: \(profile.age) y/o, \(profile.sex), \(profile.heightDisplay), \(profile.weightDisplay).

        \(profile.unitsBlock)

        \(anchorLine)

        \(anchorBlock)

        ACCURACY RULES (be GENEROUS about photo quality — never penalize for framing, lighting, distance, or angle):
        - Treat ANY usable photo as normal input. Partial body, waist-up only, cropped legs, side-only, mirror selfies, casual lighting, phone camera angle — ALL acceptable. Do NOT lower scores because of photo quality.
        - Score based on what is visible. If a region isn't shown, infer reasonably from visible regions and the user's BMI/weight/height — do NOT punish the user for it.
        - Anchor body-fat estimate using visible markers: abdominal definition, vascularity, waist taper, deltoid striations, glute-ham separation. Use the user's BMI (\(String(format: "%.1f", profile.weightKg / pow(profile.heightCm/100, 2)))) as a sanity check.
        - Symmetry = compare LEFT vs RIGHT across whatever IS visible (shoulders, arms, lats, legs). Slight rotation/turn is fine.
        - V-taper = shoulder-to-waist ratio from whichever view shows it best.
        - Muscularity = development relative to demographic norms for the user's sex/age/weight.
        - Conditioning = leanness + definition + separation.
        - If a photo is partial, dim, blurry, or oddly angled, STILL produce a confident estimate. Lower bodyFatConfidence slightly (5-15 points) but keep the main scores stable.
        - NEVER refuse to score, never return a placeholder, never tell the user to retake the photo.

        STABILITY: Be deterministic. Identical inputs MUST produce identical outputs. Similar photos must stay within ±3 points of prior rolling average. Do not over-react to lighting, angle, or partial framing.

        Return ONLY strict JSON:
        {
          "physiqueScore": 0-100,
          "symmetry": 0-100,
          "muscularity": 0-100,
          "conditioning": 0-100,
          "vTaper": 0-100,
          "bodyFatPercent": 5-40,
          "bodyFatConfidence": 0-100,
          "archetype": one of ["Lean Athletic","Aesthetic","V-Taper","Power Build","Swimmer Build","Balanced Physique"],
          "insight": one sentence on the dominant strength,
          "recommendations": array of 3 short, action-oriented tips, never insulting
        }

        Output JSON only.
        """
        do {
            return try await callJSONVision(prompt: prompt, images: [front, side, back], as: PhysiqueAnalysis.self)
        } catch let e as AIServiceError {
            // Hard-fail conditions surface to the user.
            if case .consentDenied = e { throw e }
            if case .missingConfig = e { throw e }
            // Transient AI failure (provider down, decode noise, network) → deterministic fallback
            // computed from on-device pose anchors + user BMI. Never hallucinates: it is purely a
            // measurement-driven estimate the user can re-run later.
            return PhysiqueHeuristic.estimate(profile: profile, anchors: anchors)
        }
    }

    func analyzeFace(images: [UIImage], measurements: FaceMeasurements?, sampleCount: Int = 1, consistency: Double = 0.5, history: ScoreHistory? = nil) async throws -> FaceAnalysis {
        let measureLine: String = {
            guard let m = measurements else { return "(no on-device measurements available)" }
            return """
            On-device MediaPipe-style landmark measurements averaged across \(sampleCount) photo(s) (anchor your scores to these — they are angle/lighting-invariant):
            - symmetry_index: \(Int(m.symmetry * 100))/100
            - thirds_balance: \(Int(m.thirds * 100))/100
            - canthal_tilt_deg: \(String(format: "%.1f", m.canthalTiltDeg))
            - eye_spacing_ratio: \(String(format: "%.2f", m.eyeSpacingRatio))
            - jaw_ratio: \(String(format: "%.2f", m.jawRatio))
            - sample_agreement: \(Int(consistency * 100))/100 (higher = more consistent across photos)
            """
        }()
        let anchorLine: String = {
            guard let h = history, !h.isEmpty else { return "PERSONAL CALIBRATION: (none — first analysis; rely on photos + on-device measurements only)" }
            return """
            PERSONAL CALIBRATION DATA (the model self-trains from this user's prior scans — trust it):
            \(h.summary)
            
            How to use it:
            - Mean ± std is this user's learned PSL baseline. Stay WITHIN ±1 std unless the new photos demand it.
            - Low std → confident baseline → cap movement at 2-3 points.
            - High std → noisier; you may correct more, but stay anchored to the mean.
            - Preserve the recent trend direction unless clearly contradicted.
            """
        }()

        let prompt = """
        You are Ascend Life, an empathetic facial-harmony analyst. Analyze the front-facing photo objectively and kindly.

        \(measureLine)

        \(anchorLine)

        ACCURACY RULES — base scores on what IS measurable; be GENEROUS about photo quality:
        - Treat ANY usable selfie as normal input. Slight head turns, glasses, hats, beards, makeup, indoor/outdoor lighting, casual phone selfies — ALL acceptable. Do NOT lower scores because of photo quality, framing, or lighting.
        - If a feature isn't clearly visible, estimate it from the on-device measurements and visible cues — do NOT penalize the user for it.
        - symmetry: derive primarily from the on-device symmetry_index. Mild left/right deviation from head tilt or expression is normal — don't over-penalize.
        - jawline: judge mandibular angle sharpness, gonial angle, chin projection, submental definition. Use jaw_ratio as an anchor (ideal 0.70-0.80). If hidden by beard/angle, estimate from visible cues.
        - thirds: lock to the thirds_balance measurement; perfect = each third near 33%.
        - canthalTilt: positive degrees (upturned) score higher; neutral around 4°. Map canthal_tilt_deg → score (negative ≈ 45, 0° ≈ 62, +4° ≈ 80, +8°+ ≈ 95).
        - eyeSpacing: ideal intercanthal ≈ one eye width (ratio ≈ 1.0). Mild deviation is fine.
        - overall: weighted blend of the five — symmetry 25%, jawline 25%, thirds 15%, canthalTilt 15%, eyeSpacing 10%, plus a 10% adjustment for skin/grooming/posture visible in the photo.
        - glowUpPotential: estimate realistic upside from grooming, body-fat reduction, sleep, posture, skincare. Higher when current overall is mid (50-70), lower when already high.
        - NEVER refuse to score. NEVER return placeholder values. NEVER ask the user to retake the photo.

        MULTI-PHOTO AVERAGING: You are looking at \(images.count) photo(s) of the SAME person. Compute scores for each, then RETURN THE AVERAGE. Do not pick the best or worst photo. The symmetry score must be primarily driven by the on-device symmetry_index above (which is already averaged across all photos) so it stays stable across angles/lighting.

        STABILITY: Be deterministic. Identical inputs MUST produce identical outputs. Similar photos must stay within ±3 points of prior rolling average. Do not over-react to lighting, expression, or camera differences.

        Return ONLY strict JSON:
        {
          "overall": 0-100,
          "symmetry": 0-100,
          "jawline": 0-100,
          "thirds": 0-100,
          "canthalTilt": 0-100,
          "eyeSpacing": 0-100,
          "glowUpPotential": 0-100,
          "insight": one short sentence on the strongest feature,
          "recommendations": array of 3 short, supportive optimization tips,
          "hairstyles": array of 2 hairstyle names appropriate for the face shape
        }
        Output JSON only. Never insult.
        """
        do {
            return try await callJSONVision(prompt: prompt, images: images, as: FaceAnalysis.self)
        } catch let e as AIServiceError {
            if case .consentDenied = e { throw e }
            if case .missingConfig = e { throw e }
            return FaceHeuristic.estimate(measurements: measurements, consistency: consistency)
        }
    }

    func analyzeMeal(description: String, image: UIImage?, unitSystem: String = "Metric") async throws -> MealAnalysis {
        let isImperial = unitSystem.lowercased() == "imperial"
        let calorieUnit = isImperial ? "cal" : "kcal"
        let unitsLine = isImperial
            ? "USER UNITS: IMPERIAL. In the 'note' and any other user-facing strings use food calories as 'cal' (NOT 'kcal'), and use oz/lb for solid portions where natural; grams are still fine for macros. Portions in the 'ingredients' list may use oz, lb, cups, tbsp, or grams as appropriate."
            : "USER UNITS: METRIC. In the 'note' and any other user-facing strings use 'kcal' for food calories, and prefer grams/ml for portions in the 'ingredients' list."
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let descriptionLine: String = {
            if trimmed.isEmpty {
                return image == nil
                    ? "No description provided."
                    : "No description provided — identify the meal directly from the photo (foods, ingredients, portion sizes)."
            }
            return "User description / hint: \"\(trimmed)\"."
        }()

        let prompt = """
        You are Ascend Life's nutrition vision coach. Identify the meal in detail, then estimate accurate macros from the identified ingredients.

        \(descriptionLine)

        \(unitsLine)

        STEP 1 — IDENTIFY THE DISH (the WHAT):
        - Name the dish (e.g. "Chicken burrito bowl", "Margherita pizza", "Caesar salad").
        - Classify dishType into one of: bowl, plate, sandwich/wrap, pizza, salad, pasta, soup, dessert, drink, snack, other.

        STEP 2 — IDENTIFY INGREDIENTS (the WHAT'S INSIDE):
        - Even if the view is partial/covered (e.g. sauce on top, wrap closed, bowl mixed), INFER the likely ingredients from the dish type and visible cues.
        - List every component you can reasonably identify with an estimated portion (e.g. "grilled chicken — 120 g", "white rice — 1 cup", "avocado — 1/4", "olive oil — 1 tbsp").
        - Be thorough: hidden ingredients matter for macros (oil in cooking, dressing on salad, cheese under toppings, sugar in sauces).
        - If something is genuinely ambiguous, pick the most common preparation and lower confidence accordingly.

        STEP 3 — DERIVE MACROS FROM INGREDIENTS:
        - Compute macros by summing each ingredient's contribution using standard USDA values for the stated portions.
        - Calories MUST equal proteinG*4 + carbsG*4 + fatsG*9 within ±10%.
        - Use realistic single-serving portions unless the photo clearly shows more.
        - Return integers only.

        QUALITY:
        - Lower confidence when the photo is blurry, partial, or the dish is ambiguous; raise it when ingredients are clearly visible.
        - NEVER ask the user to clarify — always return a best estimate.
        - NEVER refuse. Even from a description alone, identify likely ingredients and estimate.

        Return ONLY strict JSON:
        {
          "name": short dish name (max 4 words),
          "dishType": one of ["bowl","plate","sandwich","pizza","salad","pasta","soup","dessert","drink","snack","other"],
          "ingredients": [ {"name": "grilled chicken", "portion": "120 g"}, ... ],
          "calories": integer \(calorieUnit) (food calories — same numeric value either way; the label is just what the user sees elsewhere),
          "proteinG": integer grams,
          "carbsG": integer grams,
          "fatsG": integer grams,
          "confidence": integer 0-100,
          "note": one short nutritional insight (e.g. "High protein, moderate carbs — good post-workout choice")
        }
        Output JSON only.
        """
        do {
            if let image {
                return try await callJSONVision(prompt: prompt, images: [image], as: MealAnalysis.self)
            }
            return try await callJSONText(prompt: prompt, as: MealAnalysis.self)
        } catch let e as AIServiceError {
            if case .consentDenied = e { throw e }
            if case .missingConfig = e { throw e }
            return MealHeuristic.estimate(description: description, hasImage: image != nil, unitSystem: unitSystem)
        }
    }

    func dailyInsight(profile: ProfileSnapshot, streak: Int, recentScansCount: Int, caloriesAdherence: Double) async throws -> DailyInsight {
        let prompt = """
        You are Ascend, a disciplined yet warm self-improvement OS. Generate one daily insight for an athlete:
        - age \(profile.age), sex \(profile.sex), goals: \(profile.goals.joined(separator: ", "))
        - streak: \(streak) days, scans this month: \(recentScansCount), calories adherence: \(Int(caloriesAdherence*100))%

        \(profile.unitsBlock)

        Return strict JSON: {"headline": "one short headline (max 8 words)", "detail": "one short coaching sentence"}
        Output JSON only. Never use emojis.
        """
        return try await callJSONText(prompt: prompt, as: DailyInsight.self)
    }

    // MARK: - HTTP

    private func callJSONText<T: Decodable>(prompt: String, as: T.Type) async throws -> T {
        guard await AIConsentService.shared.ensureConsent() else { throw AIServiceError.consentDenied }
        let body: [String: Any] = [
            "model": model,
            "temperature": 0.2,
            "messages": [
                ["role": "system", "content": "You are Ascend. Reply with strict JSON only, no markdown fences. Be deterministic."],
                ["role": "user", "content": prompt]
            ]
        ]
        // Try primary model, then fallbacks on payment/rate/server errors.
        let modelChain = [model] + fallbackModels
        var lastError: Error = AIServiceError.empty
        for modelId in modelChain {
            var b = body
            b["model"] = modelId
            do {
                return try await postChat(body: b)
            } catch AIServiceError.http(let code) where code == 402 || code == 429 || code == 500 || code == 503 {
                lastError = AIServiceError.http(code)
                continue
            } catch {
                throw error
            }
        }
        throw lastError
    }

    private func callJSONVision<T: Decodable>(prompt: String, images: [UIImage], as: T.Type) async throws -> T {
        guard await AIConsentService.shared.ensureConsent() else { throw AIServiceError.consentDenied }
        // Adaptive sizing: scale down if too many images so we stay well under server payload limits (413).
        // Budget ~700KB per image of base64; aim for ~3.5MB total request body max.
        let count = max(1, images.count)
        let attempts: [(maxDim: CGFloat, quality: CGFloat)] = {
            switch count {
            case 1:    return [(1024, 0.75), (768, 0.6), (512, 0.5)]
            case 2:    return [(900, 0.7),  (700, 0.55), (512, 0.45)]
            case 3:    return [(800, 0.65), (640, 0.55), (480, 0.45)]
            default:   return [(640, 0.6),  (512, 0.5),  (384, 0.4)]
            }
        }()

        var lastError: Error = AIServiceError.empty
        let modelChain = [model] + fallbackModels
        for modelId in modelChain {
            for attempt in attempts {
                do {
                    let parts = buildVisionParts(prompt: prompt, images: images, maxDim: attempt.maxDim, quality: attempt.quality)
                    let body: [String: Any] = [
                        "model": modelId,
                        "temperature": 0.2,
                        "messages": [
                            ["role": "system", "content": "You are Ascend. Reply with strict JSON only, no markdown fences. Be deterministic."],
                            ["role": "user", "content": parts]
                        ]
                    ]
                    return try await postChat(body: body)
                } catch AIServiceError.http(let code) where code == 413 || code == 408 || code == 502 || code == 504 {
                    lastError = AIServiceError.http(code)
                    continue // retry smaller
                } catch AIServiceError.http(let code) where code == 402 || code == 429 || code == 500 || code == 503 {
                    lastError = AIServiceError.http(code)
                    break // try next model
                } catch {
                    throw error
                }
            }
        }
        throw lastError
    }

    private func buildVisionParts(prompt: String, images: [UIImage], maxDim: CGFloat, quality: CGFloat) -> [[String: Any]] {
        var parts: [[String: Any]] = [["type": "text", "text": prompt]]
        for img in images {
            let resized = resize(img, maxDim: maxDim)
            guard let data = resized.jpegData(compressionQuality: quality) else { continue }
            let b64 = data.base64EncodedString()
            parts.append([
                "type": "image_url",
                "image_url": ["url": "data:image/jpeg;base64,\(b64)"]
            ])
        }
        return parts
    }

    private func postChat<T: Decodable>(body: [String: Any]) async throws -> T {
        guard !baseURL.isEmpty, !key.isEmpty,
              let url = URL(string: "\(baseURL)/v2/vercel/v1/chat/completions") else {
            throw AIServiceError.missingConfig
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 60
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw AIServiceError.empty }
        guard (200..<300).contains(http.statusCode) else { throw AIServiceError.http(http.statusCode) }

        let wire = try JSONDecoder().decode(ChatWire.self, from: data)
        guard let content = wire.choices.first?.message.content, !content.isEmpty else {
            throw AIServiceError.empty
        }
        let cleaned = stripJSON(content)
        guard let jsonData = cleaned.data(using: .utf8) else { throw AIServiceError.decode }
        do {
            return try JSONDecoder().decode(T.self, from: jsonData)
        } catch {
            throw AIServiceError.decode
        }
    }

    private func stripJSON(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("```") {
            t = t.replacingOccurrences(of: "```json", with: "")
                 .replacingOccurrences(of: "```", with: "")
                 .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let start = t.firstIndex(of: "{"), let end = t.lastIndex(of: "}") {
            return String(t[start...end])
        }
        return t
    }

    private func resize(_ image: UIImage, maxDim: CGFloat) -> UIImage {
        let w = image.size.width, h = image.size.height
        let m = max(w, h)
        if m <= maxDim { return image }
        let scale = maxDim / m
        let newSize = CGSize(width: w*scale, height: h*scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

nonisolated struct ChatWire: Decodable {
    struct Choice: Decodable { struct Msg: Decodable { let content: String? }; let message: Msg }
    let choices: [Choice]
}

/// Compact rolling-average summary of recent scans, passed into AI prompts to
/// anchor scores and reduce fluctuations between similar uploads.
nonisolated struct ScoreHistory {
    let summary: String
    let isEmpty: Bool

    static let none = ScoreHistory(summary: "", isEmpty: true)
}

/// Aggregated on-device pose measurements passed to the AI to anchor scoring.
nonisolated struct PhysiqueAnchors {
    let symmetry: Double            // 0..1
    let shoulderWaistRatio: Double
    let coverageY: Double           // 0..1
    let confidence: Double          // 0..1
    let detectedAngles: Int         // 0...3
}

// MARK: - Deterministic Fallbacks (used only if every AI model fails)
//
// These never hallucinate. Each one returns a conservative, measurement-anchored
// estimate so the app keeps working at scale even when the AI provider is down,
// rate-limited, returns malformed JSON, or hits 402/5xx. The output is marked low
// confidence so users see it's an estimate, and they can re-run when AI returns.

nonisolated enum PhysiqueHeuristic {
    static func estimate(profile: ProfileSnapshot, anchors: PhysiqueAnchors?) -> PhysiqueAnalysis {
        // Derive body fat from BMI + sex (Deurenberg formula, simplified).
        let h = max(1.2, profile.heightCm / 100)
        let bmi = profile.weightKg / (h * h)
        let sexAdj: Double = profile.sex.lowercased().contains("female") ? 5.4 : 0
        var bf = 1.20 * bmi + 0.23 * Double(profile.age) - 16.2 + sexAdj
        bf = max(6, min(38, bf))

        // Symmetry / vTaper from pose anchors when present, otherwise neutral.
        let symmetry = max(40, min(85, (anchors?.symmetry ?? 0.62) * 100))
        let swRatio = anchors?.shoulderWaistRatio ?? 1.35
        let vTaper = max(35, min(85, (swRatio - 1.0) * 110))

        // Muscularity / conditioning from BMI band + bf band.
        let muscularity: Double = {
            switch bmi {
            case ..<19:  return 45
            case 19..<22: return 55
            case 22..<26: return 65
            case 26..<29: return 60
            default:      return 52
            }
        }()
        let conditioning = max(30, min(85, 95 - bf * 1.6))
        let physique = (symmetry + muscularity + conditioning + vTaper) / 4

        let archetype: Archetype = {
            if vTaper > 70 { return .vTaper }
            if conditioning > 70 && muscularity > 60 { return .leanAthletic }
            if muscularity > 65 { return .powerBuild }
            return .balanced
        }()

        return PhysiqueAnalysis(
            physiqueScore: physique,
            symmetry: symmetry,
            muscularity: muscularity,
            conditioning: conditioning,
            vTaper: vTaper,
            bodyFatPercent: bf,
            // Capped low so the UI shows it's an estimate, not an AI reading.
            bodyFatConfidence: min(35, (anchors?.confidence ?? 0.4) * 60),
            archetype: archetype.rawValue,
            insight: "Offline estimate from your measurements — re-run when AI is available for a full read.",
            recommendations: [
                "Re-run the scan in a moment for a full AI breakdown.",
                "Stay consistent with protein at ~1.8–2.2 g/kg bodyweight.",
                "Two compound strength sessions per week protect baseline muscle."
            ]
        )
    }
}

nonisolated enum FaceHeuristic {
    static func estimate(measurements: FaceMeasurements?, consistency: Double) -> FaceAnalysis {
        guard let m = measurements else {
            return FaceAnalysis(overall: 55, symmetry: 55, jawline: 55, thirds: 55,
                                canthalTilt: 55, eyeSpacing: 55, glowUpPotential: 60,
                                insight: "Offline estimate — re-run when AI is available.",
                                recommendations: [
                                    "Re-run the scan in a moment for a full AI read.",
                                    "Hydration, sleep, and posture move scores fastest.",
                                    "Soft front lighting with a neutral expression is ideal."
                                ],
                                hairstyles: [])
        }
        let symmetry = max(35, min(92, m.symmetry * 100))
        let thirds = max(40, min(92, m.thirds * 100))
        // canthal tilt: -2° ≈ 45, 0° ≈ 62, +4° ≈ 80, +8° ≈ 95
        let canthal = max(30, min(95, 62 + m.canthalTiltDeg * 4.5))
        // eye spacing: ideal ratio ≈ 1.0
        let eye = max(35, min(92, 90 - abs(m.eyeSpacingRatio - 1.0) * 70))
        // jaw: ideal jaw ratio 0.70–0.80
        let jaw = max(35, min(92, 92 - abs(m.jawRatio - 0.75) * 160))
        let overall = symmetry * 0.25 + jaw * 0.25 + thirds * 0.15 + canthal * 0.15 + eye * 0.10 + 60 * 0.10
        let glow = max(40, min(95, 100 - overall * 0.55))
        return FaceAnalysis(
            overall: overall,
            symmetry: symmetry,
            jawline: jaw,
            thirds: thirds,
            canthalTilt: canthal,
            eyeSpacing: eye,
            glowUpPotential: glow,
            insight: "Offline estimate from on-device landmarks — re-run when AI is available.",
            recommendations: [
                "Re-run the analysis in a moment for full AI insights.",
                "Skin, hydration and sleep have the largest short-term effect.",
                "Front-facing photo with even lighting boosts accuracy."
            ],
            hairstyles: []
        )
    }
}

nonisolated enum MealHeuristic {
    /// Conservative macros from keyword matching — deliberately under-estimates rather than
    /// invents numbers, and labels itself as an estimate so users can edit.
    static func estimate(description: String, hasImage: Bool, unitSystem: String) -> MealAnalysis {
        let lower = description.lowercased()
        let name: String = description.isEmpty ? "Meal" : description
            .split(separator: "\n").first.map(String.init) ?? "Meal"

        // Tiny rule-based table. If nothing matches we return a sensible average meal.
        let table: [(keyword: String, cal: Int, p: Int, c: Int, f: Int, kind: String)] = [
            ("salad",       350, 25, 18, 18, "salad"),
            ("burrito",     680, 30, 75, 28, "bowl"),
            ("bowl",        560, 35, 55, 20, "bowl"),
            ("pizza",       720, 28, 80, 30, "pizza"),
            ("pasta",       620, 22, 90, 18, "pasta"),
            ("sandwich",    520, 28, 55, 20, "sandwich"),
            ("wrap",        500, 28, 50, 20, "sandwich"),
            ("burger",      720, 35, 55, 38, "sandwich"),
            ("chicken",     420, 38, 30, 14, "plate"),
            ("steak",       560, 45, 12, 36, "plate"),
            ("fish",        380, 35, 18, 16, "plate"),
            ("rice",        480, 18, 75, 10, "bowl"),
            ("eggs",        320, 22, 6, 22,  "plate"),
            ("oatmeal",     360, 14, 55, 9,  "bowl"),
            ("yogurt",      220, 18, 25, 5,  "snack"),
            ("shake",       300, 30, 30, 6,  "drink"),
            ("smoothie",    280, 14, 45, 5,  "drink"),
            ("soup",        260, 14, 28, 9,  "soup"),
            ("sushi",       520, 24, 70, 14, "plate"),
            ("taco",        480, 22, 45, 22, "plate"),
            ("snack",       180, 5, 22, 8,   "snack")
        ]
        let match = table.first { lower.contains($0.keyword) }
        let (cal, p, c, f, kind) = match.map { ($0.cal, $0.p, $0.c, $0.f, $0.kind) }
                                        ?? (500, 25, 50, 20, "plate")
        return MealAnalysis(
            name: name.capitalized,
            dishType: kind,
            ingredients: [],
            calories: cal,
            proteinG: p,
            carbsG: c,
            fatsG: f,
            confidence: hasImage ? 35 : 30,
            note: "Offline estimate — tap to edit, or re-run when AI is back online."
        )
    }
}

nonisolated struct ProfileSnapshot {
    let age: Int
    let sex: String
    let heightCm: Double
    let weightKg: Double
    let goals: [String]
    let unitSystem: String

    init(age: Int, sex: String, heightCm: Double, weightKg: Double, goals: [String], unitSystem: String = "Metric") {
        self.age = age; self.sex = sex; self.heightCm = heightCm; self.weightKg = weightKg
        self.goals = goals; self.unitSystem = unitSystem
    }

    var isImperial: Bool { unitSystem.lowercased() == "imperial" }
    var heightDisplay: String {
        if isImperial {
            let totalIn = heightCm / 2.54
            let ft = Int(totalIn / 12)
            let inches = Int(totalIn.truncatingRemainder(dividingBy: 12).rounded())
            return "\(ft)'\(inches == 12 ? 0 : inches)\""
        }
        return "\(Int(heightCm))cm"
    }
    var weightDisplay: String {
        isImperial ? String(format: "%.0flb", weightKg * 2.2046226218)
                   : "\(Int(weightKg))kg"
    }
    var calorieUnit: String { isImperial ? "cal" : "kcal" }
    var unitsBlock: String {
        isImperial
        ? "USER UNITS: IMPERIAL. In any user-facing strings (insight, recommendations, note), use pounds (lb), inches/feet (ft/in), and food calories as 'cal' (not kcal). Do NOT say cm, kg, or kcal in user-facing copy."
        : "USER UNITS: METRIC. In any user-facing strings (insight, recommendations, note), use kilograms (kg), centimeters (cm), and 'kcal' for food calories. Do NOT use lb, inches, or 'cal'."
    }
}
