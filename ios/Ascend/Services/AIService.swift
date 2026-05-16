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

nonisolated struct MealAnalysis: Codable {
    let name: String
    let calories: Int
    let proteinG: Int
    let carbsG: Int
    let fatsG: Int
    let confidence: Int
    let note: String

    enum CodingKeys: String, CodingKey {
        case name, calories, proteinG, carbsG, fatsG, confidence, note
    }

    init(name: String, calories: Int, proteinG: Int, carbsG: Int, fatsG: Int, confidence: Int, note: String) {
        self.name = name; self.calories = calories
        self.proteinG = proteinG; self.carbsG = carbsG; self.fatsG = fatsG
        self.confidence = confidence; self.note = note
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.name = (try? c.decode(String.self, forKey: .name)) ?? "Meal"
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
    var errorDescription: String? {
        switch self {
        case .missingConfig: "AI service is not configured."
        case .http(let c):   "AI request failed (\(c))."
        case .decode:        "Could not interpret AI response."
        case .empty:         "AI returned an empty response."
        }
    }
}

nonisolated struct AIService {
    static let shared = AIService()

    private var baseURL: String { Config.EXPO_PUBLIC_TOOLKIT_URL }
    private var key: String { Config.EXPO_PUBLIC_RORK_TOOLKIT_SECRET_KEY }
    private let model = "google/gemini-2.5-flash"

    // MARK: - Public APIs

    func analyzePhysique(front: UIImage, side: UIImage, back: UIImage, profile: ProfileSnapshot, history: ScoreHistory? = nil) async throws -> PhysiqueAnalysis {
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
        You are Ascend Life, a precise, encouraging physique-analysis coach. Analyze three photos (front, side, back) of an athlete: \(profile.age) y/o, \(profile.sex), \(Int(profile.heightCm))cm, \(Int(profile.weightKg))kg.

        \(anchorLine)

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
        return try await callJSONVision(prompt: prompt, images: [front, side, back], as: PhysiqueAnalysis.self)
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
        return try await callJSONVision(prompt: prompt, images: images, as: FaceAnalysis.self)
    }

    func analyzeMeal(description: String, image: UIImage?) async throws -> MealAnalysis {
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
        You are Ascend Life's nutrition vision coach. Identify the meal and estimate accurate macros.

        \(descriptionLine)

        Rules:
        - If a photo is provided, look at it first: identify each visible food item, estimate portion sizes from plate / hand / utensil scale, then aggregate.
        - Calories must equal protein*4 + carbs*4 + fats*9 within ±10%.
        - Use realistic single-serving portions unless the photo clearly shows more.
        - Return integers only.
        - Lower the confidence if the photo is blurry, partial, or ambiguous; raise it if the meal is clearly visible.
        - Never ask the user to clarify — always return a best estimate.

        Return ONLY strict JSON:
        {
          "name": short meal name (auto-generated from what you see),
          "calories": integer kcal,
          "proteinG": integer grams,
          "carbsG": integer grams,
          "fatsG": integer grams,
          "confidence": integer 0-100,
          "note": one short nutritional insight
        }
        Output JSON only.
        """
        if let image {
            return try await callJSONVision(prompt: prompt, images: [image], as: MealAnalysis.self)
        }
        return try await callJSONText(prompt: prompt, as: MealAnalysis.self)
    }

    func dailyInsight(profile: ProfileSnapshot, streak: Int, recentScansCount: Int, caloriesAdherence: Double) async throws -> DailyInsight {
        let prompt = """
        You are Ascend, a disciplined yet warm self-improvement OS. Generate one daily insight for an athlete:
        - age \(profile.age), sex \(profile.sex), goals: \(profile.goals.joined(separator: ", "))
        - streak: \(streak) days, scans this month: \(recentScansCount), calories adherence: \(Int(caloriesAdherence*100))%
        Return strict JSON: {"headline": "one short headline (max 8 words)", "detail": "one short coaching sentence"}
        Output JSON only. Never use emojis.
        """
        return try await callJSONText(prompt: prompt, as: DailyInsight.self)
    }

    // MARK: - HTTP

    private func callJSONText<T: Decodable>(prompt: String, as: T.Type) async throws -> T {
        let body: [String: Any] = [
            "model": model,
            "temperature": 0.2,
            "messages": [
                ["role": "system", "content": "You are Ascend. Reply with strict JSON only, no markdown fences. Be deterministic."],
                ["role": "user", "content": prompt]
            ]
        ]
        return try await postChat(body: body)
    }

    private func callJSONVision<T: Decodable>(prompt: String, images: [UIImage], as: T.Type) async throws -> T {
        var parts: [[String: Any]] = [["type": "text", "text": prompt]]
        for img in images {
            let resized = resize(img, maxDim: 1024)
            guard let data = resized.jpegData(compressionQuality: 0.8) else { continue }
            let b64 = data.base64EncodedString()
            parts.append([
                "type": "image_url",
                "image_url": ["url": "data:image/jpeg;base64,\(b64)"]
            ])
        }
        let body: [String: Any] = [
            "model": model,
            "temperature": 0.2,
            "messages": [
                ["role": "system", "content": "You are Ascend. Reply with strict JSON only, no markdown fences. Be deterministic."],
                ["role": "user", "content": parts]
            ]
        ]
        return try await postChat(body: body)
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

nonisolated struct ProfileSnapshot {
    let age: Int
    let sex: String
    let heightCm: Double
    let weightKg: Double
    let goals: [String]
}
