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

    func analyzePhysique(front: UIImage, side: UIImage, back: UIImage, profile: ProfileSnapshot) async throws -> PhysiqueAnalysis {
        let prompt = """
        You are Ascend, a precise, encouraging physique-analysis coach. Analyze three photos (front, side, back) of an athlete: \(profile.age) y/o, \(profile.sex), \(Int(profile.heightCm))cm, \(Int(profile.weightKg))kg.

        IMPORTANT: Be deterministic. Use ONLY visible evidence. Identical inputs MUST produce identical outputs. Do not guess randomly — if uncertain, anchor estimates to the demographic baseline and lower the confidence.

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

        Use side view for posture, back for symmetry, front for proportions. Output JSON only.
        """
        return try await callJSONVision(prompt: prompt, images: [front, side, back], as: PhysiqueAnalysis.self)
    }

    func analyzeFace(image: UIImage, measurements: FaceMeasurements?) async throws -> FaceAnalysis {
        let measureLine: String = {
            guard let m = measurements else { return "(no on-device measurements available)" }
            return """
            On-device landmark measurements (anchor your scores to these):
            - symmetry_index: \(Int(m.symmetry * 100))/100
            - thirds_balance: \(Int(m.thirds * 100))/100
            - canthal_tilt_deg: \(String(format: "%.1f", m.canthalTiltDeg))
            - eye_spacing_ratio: \(String(format: "%.2f", m.eyeSpacingRatio))
            - jaw_ratio: \(String(format: "%.2f", m.jawRatio))
            """
        }()

        let prompt = """
        You are Ascend, an empathetic facial-harmony analyst. Analyze the front-facing photo objectively and kindly.

        \(measureLine)

        IMPORTANT: Be deterministic. Base scores on the measurements above plus visible evidence. Identical inputs MUST produce identical outputs.

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
        return try await callJSONVision(prompt: prompt, images: [image], as: FaceAnalysis.self)
    }

    func analyzeMeal(description: String, image: UIImage?) async throws -> MealAnalysis {
        let prompt = """
        You are Ascend's nutrition coach. Estimate macros for this meal: "\(description)".

        Rules:
        - Calories must equal protein*4 + carbs*4 + fats*9 within ±10%.
        - Use realistic portion sizes for a single serving unless described otherwise.
        - Return integers only.
        - If the description is vague, lower the confidence value.

        Return ONLY strict JSON:
        {
          "name": short meal name,
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

nonisolated struct ProfileSnapshot {
    let age: Int
    let sex: String
    let heightCm: Double
    let weightKg: Double
    let goals: [String]
}
