import Foundation
import UIKit
import CoreImage

/// Top-K consensus selector for food candidates.
///
/// Goal: never commit to a single Vision label until we cross-check it against
/// other on-image signals. Same image must produce the same dish name, and
/// near-duplicate labels (e.g. "chicken biryani" vs "fried rice" vs "jambalaya")
/// must be reconciled by ingredients/color/texture rather than coin-flipping
/// on the raw classifier score.
nonisolated enum FoodConsensus {

    /// Aggregate weight per food key from a candidate list. Source priority
    /// (OCR > text > whole-image vision > region vision) is encoded directly
    /// so deterministic order is preserved.
    static func score(_ matches: [FoodMatch], image: UIImage?) -> [(key: String, displayName: String, score: Double)] {
        guard !matches.isEmpty else { return [] }

        // Bucket by canonical key — duplicate hits from multiple sources stack.
        var buckets: [String: (display: String, score: Double, sources: Set<String>)] = [:]
        for m in matches {
            let sw = sourceWeight(m.source)
            let s = Double(m.score) * sw
            if var existing = buckets[m.rawKey] {
                existing.score += s
                existing.sources.insert(sourceName(m.source))
                buckets[m.rawKey] = existing
            } else {
                buckets[m.rawKey] = (m.displayName, s, [sourceName(m.source)])
            }
        }

        // Bonus when multiple independent sources agree on the same food.
        for (k, v) in buckets {
            let agreementBonus = max(0, Double(v.sources.count) - 1) * 0.18
            buckets[k] = (v.display, v.score + agreementBonus, v.sources)
        }

        // Color/texture priors (cheap, deterministic) — pulled from the
        // normalized image so they're hash-stable.
        let priors = colorPriors(image: image)
        for (k, v) in buckets {
            let bonus = priors[k] ?? 0
            buckets[k] = (v.display, v.score + bonus, v.sources)
        }

        // Ingredient overlap penalty: if two candidates share the same major
        // ingredient family, leave only the higher-scoring one in the final
        // pick (e.g. "fried rice" vs "biryani" → keep one).
        let ordered = buckets.sorted { lhs, rhs in
            if lhs.value.score == rhs.value.score { return lhs.key < rhs.key }
            return lhs.value.score > rhs.value.score
        }
        var seenFamily: Set<String> = []
        var result: [(String, String, Double)] = []
        for (k, v) in ordered {
            let family = ingredientFamily(k)
            if family.isEmpty || !seenFamily.contains(family) {
                if !family.isEmpty { seenFamily.insert(family) }
                result.append((k, v.display, v.score))
            }
        }
        return result
    }

    /// Confidence that the top-1 pick is a *grounded* match (high source
    /// agreement + clear gap to second place + non-trivial absolute score).
    static func confidence(top: [(key: String, displayName: String, score: Double)]) -> Double {
        guard let first = top.first else { return 0 }
        let second = top.dropFirst().first?.score ?? 0
        let gap = max(0, first.score - second)
        let normGap = min(1, gap / max(0.5, first.score))
        let absoluteAnchor = min(1, first.score / 1.4)
        return min(1, 0.55 * absoluteAnchor + 0.45 * normGap)
    }

    // MARK: - Internals

    private static func sourceWeight(_ s: FoodMatch.Source) -> Double {
        switch s {
        case .ocr:          return 1.30 // brand/menu — strongest possible signal
        case .text:         return 1.10
        case .vision:       return 1.00
        case .visionRegion: return 0.85
        }
    }

    private static func sourceName(_ s: FoodMatch.Source) -> String {
        switch s {
        case .ocr: return "ocr"
        case .text: return "text"
        case .vision: return "vision"
        case .visionRegion: return "region"
        }
    }

    /// Coarse ingredient family used to suppress near-duplicate dishes.
    /// Conservative — only collapses when the dishes overlap heavily.
    private static func ingredientFamily(_ key: String) -> String {
        if ["fried rice", "rice", "biryani", "jambalaya"].contains(key) { return "rice-bowl" }
        if ["spaghetti", "pasta", "noodle", "ramen"].contains(key) { return "noodle-bowl" }
        if ["burger", "hamburger", "cheeseburger", "big mac", "quarter pounder", "whopper", "baconator"].contains(key) { return "burger" }
        if ["pizza"].contains(key) { return "pizza" }
        if ["chicken sandwich", "mcchicken"].contains(key) { return "chicken-sandwich" }
        if ["latte", "cappuccino", "frappuccino", "coffee"].contains(key) { return "coffee" }
        return ""
    }

    /// Sample the image's average color in a couple regions and add tiny
    /// bonuses to candidates whose typical color matches. This nudges
    /// reconciliation without overriding strong Vision signals.
    private static func colorPriors(image: UIImage?) -> [String: Double] {
        guard let cg = image?.cgImage else { return [:] }
        let ci = CIImage(cgImage: cg)
        let context = CIContext(options: [.useSoftwareRenderer: false])
        var bitmap = [UInt8](repeating: 0, count: 4)
        let avg = CIFilter(name: "CIAreaAverage")
        avg?.setValue(ci, forKey: "inputImage")
        avg?.setValue(CIVector(cgRect: ci.extent), forKey: "inputExtent")
        guard let out = avg?.outputImage else { return [:] }
        context.render(out, toBitmap: &bitmap, rowBytes: 4,
                       bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBA8, colorSpace: nil)
        let r = Double(bitmap[0]) / 255
        let g = Double(bitmap[1]) / 255
        let b = Double(bitmap[2]) / 255
        let warmth = r - b              // > 0 = warm (browns/oranges)
        let greenness = g - (r + b) / 2 // > 0 = greens
        let darkness = 1 - (r + g + b) / 3

        var priors: [String: Double] = [:]
        // Tiny biases — never enough to overrule a strong Vision/OCR hit.
        if warmth > 0.06 {
            for k in ["fried chicken", "burger", "pizza", "fries", "taco", "burrito", "steak", "donut"] {
                priors[k, default: 0] += 0.10
            }
        }
        if greenness > 0.04 {
            for k in ["salad", "broccoli", "spinach", "kale", "avocado"] {
                priors[k, default: 0] += 0.12
            }
        }
        if darkness > 0.55 {
            for k in ["coffee", "chocolate", "steak", "beer"] {
                priors[k, default: 0] += 0.08
            }
        }
        return priors
    }
}
