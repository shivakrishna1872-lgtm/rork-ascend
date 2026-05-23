import Foundation
import UIKit
import Vision
import CryptoKit
import CoreImage

/// On-device meal analyzer — the FIRST priority for Cal AI.
///
/// Pipeline (no AI credits used unless we fall through):
/// 1. Image preprocessing — auto-orient, denoise, white-balance, contrast normalize.
/// 2. Multi-signal recognition, run in parallel:
///    a. `VNClassifyImageRequest` on the whole image (broad food labels).
///    b. `VNGenerateObjectnessBasedSaliencyImageRequest` → crop each salient region
///       and classify it separately (catches multiple foods on the same plate).
///    c. `VNRecognizeTextRequest` reads any visible text — brand names, menu items,
///       packaging, restaurant logos — which is the strongest possible signal for
///       fast-food / packaged / restaurant meals.
/// 3. Text-description parsing complements vision (and works alone for "describe it").
/// 4. Macro resolution: curated branded/restaurant DB → curated whole-food DB →
///    Open Food Facts (free, branded coverage) → USDA FoodData Central. All cached.
/// 5. Portion estimation: saliency area + per-food typical grams.
///
/// Returns `nil` only when nothing recognizable surfaces — `AIService.analyzeMeal`
/// then routes the photo to the cloud vision model.
nonisolated struct OnDeviceMealService {
    static let shared = OnDeviceMealService()

    private let minVisionConfidence: Float = 0.06
    private let openFoodFactsBase = "https://world.openfoodfacts.org"
    private let usdaBase = "https://api.nal.usda.gov/fdc/v1"
    private let usdaKey = "DEMO_KEY"

    // MARK: - Public

    func analyze(description: String, image: UIImage?, unitSystem: String) async -> MealAnalysis? {
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        var matches: [FoodMatch] = []
        var ocrTextHits: [String] = []
        var hadImage = false

        // Deterministic content-addressed cache: identical photo → identical
        // result, no Vision re-runs, no AI variance.
        let engineVersion = EngineRegistry.Nutrition.current.rawValue
        let cacheKey: String? = {
            if let image {
                return ScanCache.normalize(image).hash + "|" + engineVersion
            }
            if !trimmed.isEmpty {
                return ScanCache.textHash(trimmed, engine: engineVersion)
            }
            return nil
        }()
        if let key = cacheKey, let cached = ScanCache.loadFood(hash: key) {
            return MealAnalysis(
                name: cached.dishName,
                dishType: cached.dishType,
                ingredients: cached.ingredients.map { MealIngredient(name: $0.name, portion: $0.portion) },
                calories: cached.calories,
                proteinG: cached.proteinG,
                carbsG: cached.carbsG,
                fatsG: cached.fatsG,
                confidence: cached.confidence,
                note: cached.note
            )
        }

        if let image {
            hadImage = true
            // Lightweight preprocessing for better Vision recall under poor lighting / blur.
            let prepped = preprocess(image)
            async let labels = classify(image: prepped)
            async let regional = regionalClassify(image: prepped)
            async let ocr = readText(image: prepped)
            let (l, r, o) = await (labels, regional, ocr)
            matches.append(contentsOf: l)
            matches.append(contentsOf: r)
            // OCR is a very strong signal: anything we recognize from text gets a
            // confidence floor of 0.85 because the user literally photographed the
            // brand / menu label.
            let (brandMatches, hits) = parseOCR(o)
            matches.append(contentsOf: brandMatches)
            ocrTextHits = hits
        }
        if !trimmed.isEmpty {
            matches.append(contentsOf: parseText(trimmed))
        }
        matches = dedupe(matches)

        // If we got nothing but had an image, keep the best raw labels even below
        // threshold — vision rarely returns nothing useful; we'll still gate on
        // resolution success later.
        guard !matches.isEmpty else { return nil }

        // Top-K consensus: cross-check texture / color / shape / ingredient
        // family before locking in a name. Ensures "chicken biryani" vs
        // "fried rice" vs "jambalaya" resolves the same way every scan.
        let ranked = FoodConsensus.score(matches, image: image)
        let consensusKeys = Set(ranked.prefix(8).map(\.key))
        let orderedMatches: [FoodMatch] = ranked.prefix(8).compactMap { entry in
            matches.first { $0.rawKey == entry.key }
        }
        matches = orderedMatches.isEmpty ? matches : (orderedMatches + matches.filter { !consensusKeys.contains($0.rawKey) })

        // Resolve each match to macros (local DB → Open Food Facts → USDA).
        // Nutrition values ALWAYS come from the deterministic databases —
        // AI never gets to author calorie numbers directly.
        var ingredients: [ResolvedIngredient] = []
        for m in matches.prefix(8) {
            if let resolved = await resolve(match: m) {
                ingredients.append(resolved)
            }
        }
        guard !ingredients.isEmpty else { return nil }

        // Portion estimate (uses image saliency when available).
        let totalGrams = portionGrams(matches: matches, image: image)
        let scale = totalGrams / max(1, ingredients.reduce(0) { $0 + $1.defaultGrams })

        var kcal = 0.0, p = 0.0, c = 0.0, f = 0.0
        var ing: [MealIngredient] = []
        for r in ingredients {
            let grams = r.defaultGrams * scale
            kcal += r.kcalPer100g * grams / 100
            p    += r.proteinPer100g * grams / 100
            c    += r.carbsPer100g * grams / 100
            f    += r.fatsPer100g * grams / 100
            ing.append(MealIngredient(name: r.displayName, portion: formatPortion(grams: grams, unitSystem: unitSystem)))
        }

        // Confidence model
        // - Strong base when OCR caught a brand/menu name (we know exactly what it is).
        // - Otherwise base from average vision/text score, lifted by coverage.
        // - Floor pinned high (88) when OCR hit, (82) otherwise so the UI reads as confident.
        let avgScore = matches.prefix(ingredients.count).map { Double($0.score) }.reduce(0, +) / Double(max(1, ingredients.count))
        let coverageBoost = min(0.18, Double(ingredients.count) * 0.04)
        let textBoost = matches.contains(where: { $0.source == .text }) ? 0.05 : 0
        let ocrBoost = matches.contains(where: { $0.source == .ocr }) ? 0.12 : 0
        let raw = avgScore * 100 + coverageBoost * 100 + textBoost * 100 + ocrBoost * 100
        let floor: Double = ocrBoost > 0 ? 88 : (hadImage ? 84 : 82)
        let confidence = Int(max(floor, min(98, raw + 60)).rounded())

        // Prefer consensus winner for the display name. OCR brand hits are
        // already weighted highest inside FoodConsensus, so this also covers
        // the "photographed the menu" path.
        let dishName: String = {
            if let top = ranked.first { return top.displayName }
            if let ocrHit = matches.first(where: { $0.source == .ocr }) { return ocrHit.displayName }
            return matches.first?.displayName.capitalizedDishName ?? "Meal"
        }()
        let dishType = inferDishType(from: matches)

        // Confidence floor adapts to consensus strength so the UI never reads
        // an artificially high score when the top candidate is shaky.
        let consensusConf = FoodConsensus.confidence(top: Array(ranked.prefix(3)))
        let consensusAdjusted = Int(max(Double(confidence) * 0.85, Double(confidence) * 0.55 + consensusConf * 45).rounded())
        let finalConfidence = min(98, max(50, consensusAdjusted))

        let analysis = MealAnalysis(
            name: dishName,
            dishType: dishType,
            ingredients: ing,
            calories: Int(kcal.rounded()),
            proteinG: Int(p.rounded()),
            carbsG: Int(c.rounded()),
            fatsG: Int(f.rounded()),
            confidence: finalConfidence,
            note: noteFor(kcal: kcal, p: p, c: c, f: f, ocrHits: ocrTextHits, unitSystem: unitSystem)
        )

        if let key = cacheKey {
            ScanCache.saveFood(hash: key, result: CachedFoodResult(
                dishName: analysis.name,
                dishType: analysis.dishType,
                ingredients: analysis.ingredients.map { CachedFoodResult.Item(name: $0.name, portion: $0.portion) },
                calories: analysis.calories,
                proteinG: analysis.proteinG,
                carbsG: analysis.carbsG,
                fatsG: analysis.fatsG,
                confidence: analysis.confidence,
                note: analysis.note,
                engineVersion: engineVersion
            ))
        }
        return analysis
    }

    // MARK: - Preprocessing (lightweight, meal-tuned)

    private func preprocess(_ image: UIImage) -> UIImage {
        guard let cg = image.cgImage else { return image }
        let ci = CIImage(cgImage: cg)
        var out = ci

        // White-balance / temperature neutral
        let tt = CIFilter(name: "CITemperatureAndTint")
        tt?.setValue(out, forKey: kCIInputImageKey)
        tt?.setValue(CIVector(x: 6500, y: 0), forKey: "inputNeutral")
        tt?.setValue(CIVector(x: 6500, y: 0), forKey: "inputTargetNeutral")
        if let r = tt?.outputImage { out = r }

        // Auto-contrast / saturation pop so food colours read better
        let cc = CIFilter(name: "CIColorControls")
        cc?.setValue(out, forKey: kCIInputImageKey)
        cc?.setValue(1.08, forKey: kCIInputSaturationKey)
        cc?.setValue(1.06, forKey: kCIInputContrastKey)
        cc?.setValue(0.02, forKey: kCIInputBrightnessKey)
        if let r = cc?.outputImage { out = r }

        // Mild sharpen — helps Vision classifier on slightly blurry phone shots
        let sh = CIFilter(name: "CISharpenLuminance")
        sh?.setValue(out, forKey: kCIInputImageKey)
        sh?.setValue(0.35, forKey: "inputSharpness")
        if let r = sh?.outputImage { out = r }

        let ctx = CIContext(options: [.useSoftwareRenderer: false])
        guard let outCG = ctx.createCGImage(out, from: out.extent) else { return image }
        return UIImage(cgImage: outCG, scale: image.scale, orientation: image.imageOrientation)
    }

    // MARK: - Vision classification (whole image)

    private func classify(image: UIImage) async -> [FoodMatch] {
        guard let cg = image.cgImage else { return [] }
        return await withCheckedContinuation { (cont: CheckedContinuation<[FoodMatch], Never>) in
            let req = VNClassifyImageRequest { request, _ in
                let observations = (request.results as? [VNClassificationObservation]) ?? []
                let foods: [FoodMatch] = observations
                    .filter { $0.confidence >= self.minVisionConfidence }
                    .prefix(30)
                    .compactMap { obs in
                        let key = obs.identifier.lowercased()
                        if let canonical = FoodDB.canonicalKey(for: key) {
                            return FoodMatch(rawKey: canonical, displayName: FoodDB.displayName(for: canonical), score: obs.confidence, source: .vision)
                        }
                        return nil
                    }
                cont.resume(returning: foods)
            }
            let handler = VNImageRequestHandler(cgImage: cg, orientation: .up, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                do { try handler.perform([req]) }
                catch { cont.resume(returning: []) }
            }
        }
    }

    // MARK: - Multi-region (catch mixed plates with several foods)

    private func regionalClassify(image: UIImage) async -> [FoodMatch] {
        guard let cg = image.cgImage else { return [] }
        let regions = await objectnessRegions(cg: cg)
        guard !regions.isEmpty else { return [] }
        var out: [FoodMatch] = []
        for bbox in regions.prefix(4) {
            guard let cropCG = crop(cg: cg, normalized: bbox) else { continue }
            let cropUI = UIImage(cgImage: cropCG)
            let labels = await classify(image: cropUI)
            // Slightly down-weight regional hits so they don't outvote the whole-image label.
            for l in labels.prefix(3) {
                out.append(FoodMatch(rawKey: l.rawKey, displayName: l.displayName, score: max(0.12, l.score * 0.85), source: .visionRegion))
            }
        }
        return out
    }

    private func objectnessRegions(cg: CGImage) async -> [CGRect] {
        await withCheckedContinuation { (cont: CheckedContinuation<[CGRect], Never>) in
            let req = VNGenerateObjectnessBasedSaliencyImageRequest { request, _ in
                guard let obs = (request.results as? [VNSaliencyImageObservation])?.first,
                      let salient = obs.salientObjects else {
                    cont.resume(returning: []); return
                }
                let rects = salient
                    .sorted(by: { $0.confidence > $1.confidence })
                    .prefix(6)
                    .map { $0.boundingBox }
                cont.resume(returning: Array(rects))
            }
            let handler = VNImageRequestHandler(cgImage: cg, orientation: .up, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                do { try handler.perform([req]) }
                catch { cont.resume(returning: []) }
            }
        }
    }

    private func crop(cg: CGImage, normalized: CGRect) -> CGImage? {
        // Vision bboxes are normalized with origin bottom-left.
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        let rect = CGRect(
            x: max(0, normalized.minX * w),
            y: max(0, (1 - normalized.maxY) * h),
            width: min(w, normalized.width * w),
            height: min(h, normalized.height * h)
        ).integral
        guard rect.width > 32, rect.height > 32 else { return nil }
        return cg.cropping(to: rect)
    }

    // MARK: - OCR (brand / menu / packaging detection)

    private func readText(image: UIImage) async -> [String] {
        guard let cg = image.cgImage else { return [] }
        return await withCheckedContinuation { (cont: CheckedContinuation<[String], Never>) in
            let req = VNRecognizeTextRequest { request, _ in
                let obs = (request.results as? [VNRecognizedTextObservation]) ?? []
                let strings = obs.compactMap { $0.topCandidates(1).first?.string }
                cont.resume(returning: strings)
            }
            req.recognitionLevel = .accurate
            req.usesLanguageCorrection = true
            req.recognitionLanguages = ["en-US"]
            let handler = VNImageRequestHandler(cgImage: cg, orientation: .up, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                do { try handler.perform([req]) }
                catch { cont.resume(returning: []) }
            }
        }
    }

    private func parseOCR(_ strings: [String]) -> (matches: [FoodMatch], hits: [String]) {
        guard !strings.isEmpty else { return ([], []) }
        let joined = strings.joined(separator: " ").lowercased()
        var matches: [FoodMatch] = []
        var hits: [String] = []
        // Brand / restaurant items get matched first — the strongest signal.
        for (alias, key) in FoodDB.brandAliases {
            if joined.contains(alias) {
                matches.append(FoodMatch(rawKey: key, displayName: FoodDB.displayName(for: key), score: 0.95, source: .ocr))
                hits.append(alias)
            }
        }
        // Whole-food keywords also benefit from OCR (e.g. menu items).
        for key in FoodDB.allKeys {
            if joined.contains(key) {
                matches.append(FoodMatch(rawKey: key, displayName: FoodDB.displayName(for: key), score: 0.85, source: .ocr))
            }
        }
        return (matches, hits)
    }

    // MARK: - Text parsing

    private func parseText(_ text: String) -> [FoodMatch] {
        let lower = text.lowercased()
        var matches: [FoodMatch] = []
        for (alias, key) in FoodDB.brandAliases {
            if lower.contains(alias) {
                matches.append(FoodMatch(rawKey: key, displayName: FoodDB.displayName(for: key), score: 0.9, source: .text))
            }
        }
        for key in FoodDB.allKeys {
            if lower.contains(key) {
                matches.append(FoodMatch(rawKey: key, displayName: FoodDB.displayName(for: key), score: 0.75, source: .text))
            }
        }
        return matches
    }

    private func dedupe(_ matches: [FoodMatch]) -> [FoodMatch] {
        var seen = Set<String>()
        var out: [FoodMatch] = []
        for m in matches.sorted(by: { $0.score > $1.score }) {
            if seen.insert(m.rawKey).inserted { out.append(m) }
        }
        return out
    }

    // MARK: - Resolution (local DB → Open Food Facts → USDA)

    private func resolve(match: FoodMatch) async -> ResolvedIngredient? {
        if let local = FoodDB.macros(for: match.rawKey) {
            return ResolvedIngredient(
                displayName: match.displayName,
                kcalPer100g: local.kcal,
                proteinPer100g: local.protein,
                carbsPer100g: local.carbs,
                fatsPer100g: local.fats,
                defaultGrams: local.typicalGrams
            )
        }
        if let off = await openFoodFactsLookup(query: match.rawKey) {
            return off
        }
        if let usda = await usdaLookup(query: match.rawKey) {
            return usda
        }
        return nil
    }

    // MARK: - Open Food Facts

    private struct OFFCacheEntry: Codable {
        let kcal: Double; let protein: Double; let carbs: Double; let fats: Double; let name: String
    }

    private func openFoodFactsLookup(query: String) async -> ResolvedIngredient? {
        let cacheKey = "off.cache." + SHA256.hash(data: Data(query.utf8)).map { String(format: "%02x", $0) }.joined()
        if let data = UserDefaults.standard.data(forKey: cacheKey),
           let cached = try? JSONDecoder().decode(OFFCacheEntry.self, from: data) {
            return ResolvedIngredient(
                displayName: cached.name,
                kcalPer100g: cached.kcal,
                proteinPer100g: cached.protein,
                carbsPer100g: cached.carbs,
                fatsPer100g: cached.fats,
                defaultGrams: 150
            )
        }
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        guard let url = URL(string: "\(openFoodFactsBase)/cgi/search.pl?search_terms=\(encoded)&search_simple=1&action=process&json=1&page_size=3&sort_by=unique_scans_n") else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 6
        req.setValue("Ascend-iOS/1.0", forHTTPHeaderField: "User-Agent")
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
            let wire = try JSONDecoder().decode(OFFWire.self, from: data)
            // Pick the first product that actually has kcal info.
            guard let product = wire.products.first(where: { ($0.nutriments?.energyKcal_100g ?? 0) > 0 || ($0.nutriments?.energy_100g ?? 0) > 0 }),
                  let n = product.nutriments else { return nil }
            let kcal = n.energyKcal_100g ?? ((n.energy_100g ?? 0) / 4.184)
            let protein = n.proteins_100g ?? 0
            let carbs = n.carbohydrates_100g ?? 0
            let fats = n.fat_100g ?? 0
            guard kcal > 0 else { return nil }
            let name = product.product_name ?? product.generic_name ?? query.capitalized
            let entry = OFFCacheEntry(kcal: kcal, protein: protein, carbs: carbs, fats: fats, name: name)
            if let data = try? JSONEncoder().encode(entry) {
                UserDefaults.standard.set(data, forKey: cacheKey)
            }
            return ResolvedIngredient(
                displayName: name,
                kcalPer100g: kcal,
                proteinPer100g: protein,
                carbsPer100g: carbs,
                fatsPer100g: fats,
                defaultGrams: 150
            )
        } catch {
            return nil
        }
    }

    // MARK: - USDA

    private struct USDACacheEntry: Codable {
        let kcal: Double; let protein: Double; let carbs: Double; let fats: Double; let name: String
    }

    private func usdaLookup(query: String) async -> ResolvedIngredient? {
        let cacheKey = "usda.cache." + SHA256.hash(data: Data(query.utf8)).map { String(format: "%02x", $0) }.joined()
        if let data = UserDefaults.standard.data(forKey: cacheKey),
           let cached = try? JSONDecoder().decode(USDACacheEntry.self, from: data) {
            return ResolvedIngredient(
                displayName: cached.name,
                kcalPer100g: cached.kcal,
                proteinPer100g: cached.protein,
                carbsPer100g: cached.carbs,
                fatsPer100g: cached.fats,
                defaultGrams: 150
            )
        }
        guard let url = URL(string: "\(usdaBase)/foods/search?api_key=\(usdaKey)&pageSize=1&query=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query)") else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 6
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
            let wire = try JSONDecoder().decode(USDAWire.self, from: data)
            guard let food = wire.foods.first else { return nil }
            let nutrients = Dictionary(uniqueKeysWithValues: food.foodNutrients.compactMap { n -> (String, Double)? in
                guard let name = n.nutrientName, let v = n.value else { return nil }
                return (name.lowercased(), v)
            })
            let kcal = nutrients["energy"] ?? nutrients["energy (kcal)"] ?? 0
            let protein = nutrients["protein"] ?? 0
            let carbs = nutrients["carbohydrate, by difference"] ?? 0
            let fats = nutrients["total lipid (fat)"] ?? 0
            guard kcal > 0 else { return nil }

            let entry = USDACacheEntry(kcal: kcal, protein: protein, carbs: carbs, fats: fats, name: food.description ?? query.capitalized)
            if let encoded = try? JSONEncoder().encode(entry) {
                UserDefaults.standard.set(encoded, forKey: cacheKey)
            }
            return ResolvedIngredient(
                displayName: entry.name,
                kcalPer100g: kcal,
                proteinPer100g: protein,
                carbsPer100g: carbs,
                fatsPer100g: fats,
                defaultGrams: 150
            )
        } catch {
            return nil
        }
    }

    // MARK: - Portion estimation

    private func portionGrams(matches: [FoodMatch], image: UIImage?) -> Double {
        let baseline = matches.prefix(8).reduce(0.0) { acc, m in
            acc + (FoodDB.macros(for: m.rawKey)?.typicalGrams ?? 150)
        }
        guard let image, let cg = image.cgImage else { return baseline }

        var fill: Double = 1.0
        let req = VNGenerateAttentionBasedSaliencyImageRequest()
        let handler = VNImageRequestHandler(cgImage: cg, orientation: .up, options: [:])
        do {
            try handler.perform([req])
            if let obs = req.results?.first as? VNSaliencyImageObservation,
               let salient = obs.salientObjects?.first {
                let bb = salient.boundingBox
                let area = max(0.05, bb.width * bb.height)
                fill = (0.6 + area * 1.2).clamped(to: 0.7...1.5)
            }
        } catch { }
        return baseline * fill
    }

    // MARK: - Helpers

    private func formatPortion(grams: Double, unitSystem: String) -> String {
        if unitSystem.lowercased() == "imperial" {
            let oz = grams / 28.3495
            return String(format: "%.1f oz", oz)
        }
        return "\(Int(grams.rounded())) g"
    }

    private func inferDishType(from matches: [FoodMatch]) -> String {
        let keys = matches.map { $0.rawKey }.joined(separator: " ")
        if keys.contains("pizza") { return "pizza" }
        if keys.contains("salad") { return "salad" }
        if keys.contains("burger") || keys.contains("sandwich") || keys.contains("wrap") { return "sandwich" }
        if keys.contains("pasta") || keys.contains("spaghetti") || keys.contains("noodle") { return "pasta" }
        if keys.contains("soup") { return "soup" }
        if keys.contains("rice") || keys.contains("bowl") || keys.contains("burrito") { return "bowl" }
        if keys.contains("cake") || keys.contains("cookie") || keys.contains("ice cream") || keys.contains("donut") { return "dessert" }
        if keys.contains("coffee") || keys.contains("juice") || keys.contains("smoothie") || keys.contains("latte") || keys.contains("soda") { return "drink" }
        if keys.contains("chip") || keys.contains("popcorn") || keys.contains("nut") { return "snack" }
        return "plate"
    }

    private func noteFor(kcal: Double, p: Double, c: Double, f: Double, ocrHits: [String], unitSystem: String) -> String {
        let unit = unitSystem.lowercased() == "imperial" ? "cal" : "kcal"
        if let brand = ocrHits.first {
            return "Recognized \(brand.capitalized) — \(Int(kcal)) \(unit), \(Int(p))g protein."
        }
        if p / max(1, kcal/100) > 0.20 || p > 30 {
            return "High protein, \(Int(kcal)) \(unit) — solid building block."
        }
        if c > 60 && p < 20 {
            return "Carb-leaning meal, \(Int(kcal)) \(unit) — pair with protein at the next meal."
        }
        if f > 30 {
            return "Fat-dominant meal, \(Int(kcal)) \(unit) — watch portion if cutting."
        }
        return "Balanced macros, \(Int(kcal)) \(unit)."
    }
}

// MARK: - Wire types

private struct OFFWire: Decodable {
    struct Product: Decodable {
        let product_name: String?
        let generic_name: String?
        let nutriments: Nutriments?
    }
    struct Nutriments: Decodable {
        let energyKcal_100g: Double?
        let energy_100g: Double?
        let proteins_100g: Double?
        let carbohydrates_100g: Double?
        let fat_100g: Double?
        enum CodingKeys: String, CodingKey {
            case energyKcal_100g = "energy-kcal_100g"
            case energy_100g = "energy_100g"
            case proteins_100g = "proteins_100g"
            case carbohydrates_100g = "carbohydrates_100g"
            case fat_100g = "fat_100g"
        }
    }
    let products: [Product]
}

private struct USDAWire: Decodable {
    struct Food: Decodable {
        let description: String?
        let foodNutrients: [Nutrient]
    }
    struct Nutrient: Decodable {
        let nutrientName: String?
        let value: Double?
    }
    let foods: [Food]
}

// MARK: - Match / Resolved types

nonisolated struct FoodMatch {
    enum Source { case vision, visionRegion, ocr, text }
    let rawKey: String
    let displayName: String
    let score: Float
    let source: Source
}

nonisolated struct ResolvedIngredient {
    let displayName: String
    let kcalPer100g: Double
    let proteinPer100g: Double
    let carbsPer100g: Double
    let fatsPer100g: Double
    let defaultGrams: Double
}

// MARK: - Curated food database (USDA-aligned, per 100g)

nonisolated enum FoodDB {
    struct Macros { let kcal: Double; let protein: Double; let carbs: Double; let fats: Double; let typicalGrams: Double }

    static func macros(for key: String) -> Macros? { entries[key] }
    static func displayName(for key: String) -> String { displayNames[key] ?? key.capitalized }
    static func isFood(_ key: String) -> Bool { entries[key] != nil || displayNames[key] != nil }
    static var allKeys: [String] { Array(entries.keys) }

    /// Map a noisy Vision label (e.g. "cheeseburger sandwich", "pizza, slice") to
    /// our canonical key.
    static func canonicalKey(for raw: String) -> String? {
        let cleaned = raw.lowercased()
        if entries[cleaned] != nil { return cleaned }
        // Substring match — Vision labels often contain extra words.
        for key in entries.keys where cleaned.contains(key) {
            return key
        }
        for (alias, key) in brandAliases where cleaned.contains(alias) {
            return key
        }
        return nil
    }

    /// Brand / restaurant aliases → canonical key. OCR or description matches
    /// against these get the highest confidence.
    static let brandAliases: [(alias: String, key: String)] = [
        ("big mac", "big mac"),
        ("mcdouble", "cheeseburger"),
        ("quarter pounder", "quarter pounder"),
        ("mcchicken", "mcchicken"),
        ("mcnugget", "chicken nuggets"),
        ("chicken nugget", "chicken nuggets"),
        ("filet-o-fish", "filet o fish"),
        ("egg mcmuffin", "egg mcmuffin"),
        ("whopper", "whopper"),
        ("baconator", "baconator"),
        ("dave's single", "burger"),
        ("frosty", "frosty"),
        ("chipotle", "burrito bowl"),
        ("burrito bowl", "burrito bowl"),
        ("chick-fil-a", "chicken sandwich"),
        ("chick fil a", "chicken sandwich"),
        ("starbucks", "latte"),
        ("latte", "latte"),
        ("cappuccino", "cappuccino"),
        ("frappuccino", "frappuccino"),
        ("subway", "sub sandwich"),
        ("footlong", "sub sandwich"),
        ("six inch", "sub sandwich"),
        ("domino", "pizza"),
        ("papa john", "pizza"),
        ("pizza hut", "pizza"),
        ("kfc", "fried chicken"),
        ("popeyes", "fried chicken"),
        ("fried chicken", "fried chicken"),
        ("taco bell", "taco"),
        ("crunchwrap", "crunchwrap"),
        ("chalupa", "taco"),
        ("quesadilla", "quesadilla"),
        ("panera", "soup"),
        ("five guys", "burger"),
        ("in-n-out", "burger"),
        ("shake shack", "burger"),
        ("coca-cola", "soda"),
        ("coca cola", "soda"),
        ("pepsi", "soda"),
        ("sprite", "soda"),
        ("red bull", "energy drink"),
        ("monster", "energy drink"),
        ("gatorade", "sports drink"),
        ("powerade", "sports drink"),
        ("protein bar", "protein bar"),
        ("clif bar", "protein bar"),
        ("rxbar", "protein bar"),
        ("oreo", "cookie"),
        ("doritos", "chip"),
        ("lay's", "chip"),
        ("pringles", "chip"),
        ("cheerios", "cereal"),
        ("oatmeal", "oatmeal"),
        ("kind bar", "protein bar")
    ]

    private static let displayNames: [String: String] = [
        "pizza": "Pizza slice",
        "hamburger": "Burger",
        "cheeseburger": "Cheeseburger",
        "burrito": "Burrito",
        "burrito bowl": "Burrito bowl",
        "sushi": "Sushi",
        "salad": "Salad",
        "spaghetti": "Spaghetti",
        "pasta": "Pasta",
        "ramen": "Ramen",
        "noodle": "Noodles",
        "rice": "Rice",
        "fried rice": "Fried rice",
        "chicken": "Chicken",
        "chicken breast": "Grilled chicken",
        "fried chicken": "Fried chicken",
        "chicken nuggets": "Chicken nuggets",
        "chicken sandwich": "Chicken sandwich",
        "steak": "Steak",
        "beef": "Beef",
        "pork": "Pork",
        "bacon": "Bacon",
        "salmon": "Salmon",
        "tuna": "Tuna",
        "shrimp": "Shrimp",
        "egg": "Eggs",
        "omelette": "Omelette",
        "pancake": "Pancakes",
        "waffle": "Waffles",
        "toast": "Toast",
        "bread": "Bread",
        "bagel": "Bagel",
        "sandwich": "Sandwich",
        "sub sandwich": "Sub sandwich",
        "wrap": "Wrap",
        "taco": "Taco",
        "burger": "Burger",
        "big mac": "Big Mac",
        "quarter pounder": "Quarter Pounder",
        "mcchicken": "McChicken",
        "filet o fish": "Filet-O-Fish",
        "egg mcmuffin": "Egg McMuffin",
        "whopper": "Whopper",
        "baconator": "Baconator",
        "frosty": "Frosty",
        "crunchwrap": "Crunchwrap",
        "quesadilla": "Quesadilla",
        "hotdog": "Hot dog",
        "fries": "French fries",
        "potato": "Potato",
        "sweet potato": "Sweet potato",
        "broccoli": "Broccoli",
        "carrot": "Carrots",
        "spinach": "Spinach",
        "kale": "Kale",
        "avocado": "Avocado",
        "tomato": "Tomato",
        "cucumber": "Cucumber",
        "apple": "Apple",
        "banana": "Banana",
        "orange": "Orange",
        "berry": "Berries",
        "strawberry": "Strawberries",
        "blueberry": "Blueberries",
        "grape": "Grapes",
        "yogurt": "Yogurt",
        "greek yogurt": "Greek yogurt",
        "milk": "Milk",
        "cheese": "Cheese",
        "butter": "Butter",
        "olive oil": "Olive oil",
        "almond": "Almonds",
        "peanut": "Peanuts",
        "peanut butter": "Peanut butter",
        "oatmeal": "Oatmeal",
        "cereal": "Cereal",
        "granola": "Granola",
        "smoothie": "Smoothie",
        "protein shake": "Protein shake",
        "protein bar": "Protein bar",
        "coffee": "Coffee",
        "latte": "Latte",
        "cappuccino": "Cappuccino",
        "frappuccino": "Frappuccino",
        "tea": "Tea",
        "juice": "Juice",
        "soda": "Soda",
        "energy drink": "Energy drink",
        "sports drink": "Sports drink",
        "beer": "Beer",
        "wine": "Wine",
        "chocolate": "Chocolate",
        "cake": "Cake",
        "cookie": "Cookie",
        "ice cream": "Ice cream",
        "donut": "Donut",
        "muffin": "Muffin",
        "chip": "Chips",
        "popcorn": "Popcorn",
        "nut": "Nuts",
        "soup": "Soup",
        "stew": "Stew",
        "curry": "Curry",
        "dumpling": "Dumplings",
        "quinoa": "Quinoa",
        "lentil": "Lentils",
        "bean": "Beans",
        "tofu": "Tofu"
    ]

    private static let entries: [String: Macros] = [
        "pizza":         .init(kcal: 266, protein: 11, carbs: 33, fats: 10, typicalGrams: 130),
        "hamburger":     .init(kcal: 295, protein: 17, carbs: 24, fats: 14, typicalGrams: 230),
        "cheeseburger":  .init(kcal: 303, protein: 15, carbs: 28, fats: 15, typicalGrams: 240),
        "burrito":       .init(kcal: 215, protein: 10, carbs: 28, fats: 7,  typicalGrams: 320),
        "burrito bowl":  .init(kcal: 165, protein: 11, carbs: 18, fats: 6,  typicalGrams: 480),
        "sushi":         .init(kcal: 150, protein: 6,  carbs: 30, fats: 0.7,typicalGrams: 200),
        "salad":         .init(kcal: 130, protein: 5,  carbs: 9,  fats: 9,  typicalGrams: 250),
        "spaghetti":     .init(kcal: 158, protein: 6,  carbs: 31, fats: 1,  typicalGrams: 250),
        "pasta":         .init(kcal: 165, protein: 6,  carbs: 32, fats: 1.5,typicalGrams: 250),
        "ramen":         .init(kcal: 130, protein: 5,  carbs: 19, fats: 4,  typicalGrams: 450),
        "noodle":        .init(kcal: 138, protein: 5,  carbs: 25, fats: 2,  typicalGrams: 220),
        "rice":          .init(kcal: 130, protein: 2.7,carbs: 28, fats: 0.3,typicalGrams: 180),
        "fried rice":    .init(kcal: 174, protein: 5,  carbs: 24, fats: 6,  typicalGrams: 220),
        "chicken":       .init(kcal: 165, protein: 31, carbs: 0,  fats: 3.6,typicalGrams: 150),
        "chicken breast":.init(kcal: 165, protein: 31, carbs: 0,  fats: 3.6,typicalGrams: 150),
        "fried chicken": .init(kcal: 246, protein: 19, carbs: 8,  fats: 16, typicalGrams: 150),
        "chicken nuggets":.init(kcal: 297, protein: 15, carbs: 18, fats: 19, typicalGrams: 100),
        "chicken sandwich":.init(kcal: 280, protein: 18, carbs: 30, fats: 11, typicalGrams: 200),
        "steak":         .init(kcal: 271, protein: 25, carbs: 0,  fats: 19, typicalGrams: 180),
        "beef":          .init(kcal: 250, protein: 26, carbs: 0,  fats: 17, typicalGrams: 150),
        "pork":          .init(kcal: 242, protein: 27, carbs: 0,  fats: 14, typicalGrams: 150),
        "bacon":         .init(kcal: 541, protein: 37, carbs: 1.4,fats: 42, typicalGrams: 40),
        "salmon":        .init(kcal: 208, protein: 20, carbs: 0,  fats: 13, typicalGrams: 150),
        "tuna":          .init(kcal: 132, protein: 28, carbs: 0,  fats: 1,  typicalGrams: 120),
        "shrimp":        .init(kcal: 99,  protein: 24, carbs: 0.2,fats: 0.3,typicalGrams: 100),
        "egg":           .init(kcal: 155, protein: 13, carbs: 1.1,fats: 11, typicalGrams: 100),
        "omelette":      .init(kcal: 154, protein: 11, carbs: 1,  fats: 12, typicalGrams: 150),
        "pancake":       .init(kcal: 227, protein: 6,  carbs: 28, fats: 10, typicalGrams: 170),
        "waffle":        .init(kcal: 291, protein: 8,  carbs: 33, fats: 14, typicalGrams: 100),
        "toast":         .init(kcal: 313, protein: 9,  carbs: 54, fats: 6,  typicalGrams: 60),
        "bread":         .init(kcal: 265, protein: 9,  carbs: 49, fats: 3.2,typicalGrams: 60),
        "bagel":         .init(kcal: 250, protein: 10, carbs: 49, fats: 1.5,typicalGrams: 100),
        "sandwich":      .init(kcal: 250, protein: 12, carbs: 28, fats: 10, typicalGrams: 250),
        "sub sandwich":  .init(kcal: 230, protein: 13, carbs: 27, fats: 8,  typicalGrams: 250),
        "wrap":          .init(kcal: 245, protein: 11, carbs: 30, fats: 9,  typicalGrams: 250),
        "taco":          .init(kcal: 226, protein: 9,  carbs: 21, fats: 13, typicalGrams: 100),
        "burger":        .init(kcal: 295, protein: 17, carbs: 24, fats: 14, typicalGrams: 230),
        "big mac":       .init(kcal: 257, protein: 13, carbs: 21, fats: 13, typicalGrams: 215),
        "quarter pounder":.init(kcal: 240, protein: 14, carbs: 18, fats: 12, typicalGrams: 200),
        "mcchicken":     .init(kcal: 230, protein: 10, carbs: 28, fats: 10, typicalGrams: 180),
        "filet o fish":  .init(kcal: 235, protein: 10, carbs: 25, fats: 10, typicalGrams: 140),
        "egg mcmuffin":  .init(kcal: 230, protein: 14, carbs: 22, fats: 9,  typicalGrams: 135),
        "whopper":       .init(kcal: 230, protein: 11, carbs: 19, fats: 13, typicalGrams: 290),
        "baconator":     .init(kcal: 290, protein: 17, carbs: 13, fats: 19, typicalGrams: 330),
        "frosty":        .init(kcal: 110, protein: 3,  carbs: 19, fats: 3,  typicalGrams: 230),
        "crunchwrap":    .init(kcal: 240, protein: 8,  carbs: 28, fats: 11, typicalGrams: 254),
        "quesadilla":    .init(kcal: 280, protein: 12, carbs: 22, fats: 16, typicalGrams: 200),
        "hotdog":        .init(kcal: 290, protein: 10, carbs: 22, fats: 17, typicalGrams: 100),
        "fries":         .init(kcal: 312, protein: 3.4,carbs: 41, fats: 15, typicalGrams: 120),
        "potato":        .init(kcal: 87,  protein: 1.9,carbs: 20, fats: 0.1,typicalGrams: 170),
        "sweet potato":  .init(kcal: 86,  protein: 1.6,carbs: 20, fats: 0.1,typicalGrams: 170),
        "broccoli":      .init(kcal: 35,  protein: 2.4,carbs: 7,  fats: 0.4,typicalGrams: 90),
        "carrot":        .init(kcal: 41,  protein: 0.9,carbs: 10, fats: 0.2,typicalGrams: 80),
        "spinach":       .init(kcal: 23,  protein: 2.9,carbs: 3.6,fats: 0.4,typicalGrams: 60),
        "kale":          .init(kcal: 49,  protein: 4.3,carbs: 9,  fats: 0.9,typicalGrams: 60),
        "avocado":       .init(kcal: 160, protein: 2,  carbs: 9,  fats: 15, typicalGrams: 70),
        "tomato":        .init(kcal: 18,  protein: 0.9,carbs: 3.9,fats: 0.2,typicalGrams: 80),
        "cucumber":      .init(kcal: 16,  protein: 0.7,carbs: 3.6,fats: 0.1,typicalGrams: 80),
        "apple":         .init(kcal: 52,  protein: 0.3,carbs: 14, fats: 0.2,typicalGrams: 180),
        "banana":        .init(kcal: 89,  protein: 1.1,carbs: 23, fats: 0.3,typicalGrams: 120),
        "orange":        .init(kcal: 47,  protein: 0.9,carbs: 12, fats: 0.1,typicalGrams: 150),
        "berry":         .init(kcal: 57,  protein: 0.7,carbs: 14, fats: 0.3,typicalGrams: 80),
        "strawberry":    .init(kcal: 32,  protein: 0.7,carbs: 8,  fats: 0.3,typicalGrams: 100),
        "blueberry":     .init(kcal: 57,  protein: 0.7,carbs: 14, fats: 0.3,typicalGrams: 80),
        "grape":         .init(kcal: 69,  protein: 0.7,carbs: 18, fats: 0.2,typicalGrams: 100),
        "yogurt":        .init(kcal: 61,  protein: 3.5,carbs: 4.7,fats: 3.3,typicalGrams: 170),
        "greek yogurt":  .init(kcal: 97,  protein: 9,  carbs: 4,  fats: 5,  typicalGrams: 170),
        "milk":          .init(kcal: 42,  protein: 3.4,carbs: 5,  fats: 1,  typicalGrams: 240),
        "cheese":        .init(kcal: 402, protein: 25, carbs: 1.3,fats: 33, typicalGrams: 30),
        "butter":        .init(kcal: 717, protein: 0.9,carbs: 0.1,fats: 81, typicalGrams: 10),
        "olive oil":     .init(kcal: 884, protein: 0,  carbs: 0,  fats: 100,typicalGrams: 14),
        "almond":        .init(kcal: 579, protein: 21, carbs: 22, fats: 50, typicalGrams: 30),
        "peanut":        .init(kcal: 567, protein: 26, carbs: 16, fats: 49, typicalGrams: 30),
        "peanut butter": .init(kcal: 588, protein: 25, carbs: 20, fats: 50, typicalGrams: 32),
        "oatmeal":       .init(kcal: 71,  protein: 2.5,carbs: 12, fats: 1.5,typicalGrams: 230),
        "cereal":        .init(kcal: 379, protein: 7,  carbs: 84, fats: 4,  typicalGrams: 50),
        "granola":       .init(kcal: 471, protein: 10, carbs: 64, fats: 20, typicalGrams: 60),
        "smoothie":      .init(kcal: 80,  protein: 2,  carbs: 17, fats: 0.5,typicalGrams: 350),
        "protein shake": .init(kcal: 100, protein: 20, carbs: 4,  fats: 1,  typicalGrams: 350),
        "protein bar":   .init(kcal: 360, protein: 30, carbs: 38, fats: 10, typicalGrams: 60),
        "coffee":        .init(kcal: 2,   protein: 0.3,carbs: 0,  fats: 0,  typicalGrams: 240),
        "latte":         .init(kcal: 56,  protein: 3,  carbs: 5.5,fats: 2,  typicalGrams: 360),
        "cappuccino":    .init(kcal: 35,  protein: 2,  carbs: 3,  fats: 1.5,typicalGrams: 240),
        "frappuccino":   .init(kcal: 170, protein: 3,  carbs: 30, fats: 4,  typicalGrams: 360),
        "tea":           .init(kcal: 1,   protein: 0,  carbs: 0.3,fats: 0,  typicalGrams: 240),
        "juice":         .init(kcal: 45,  protein: 0.7,carbs: 11, fats: 0.2,typicalGrams: 250),
        "soda":          .init(kcal: 41,  protein: 0,  carbs: 11, fats: 0,  typicalGrams: 330),
        "energy drink":  .init(kcal: 45,  protein: 0,  carbs: 11, fats: 0,  typicalGrams: 250),
        "sports drink":  .init(kcal: 25,  protein: 0,  carbs: 6,  fats: 0,  typicalGrams: 330),
        "beer":          .init(kcal: 43,  protein: 0.5,carbs: 3.6,fats: 0,  typicalGrams: 355),
        "wine":          .init(kcal: 83,  protein: 0.1,carbs: 2.6,fats: 0,  typicalGrams: 150),
        "chocolate":     .init(kcal: 546, protein: 4.9,carbs: 61, fats: 31, typicalGrams: 40),
        "cake":          .init(kcal: 350, protein: 5,  carbs: 50, fats: 15, typicalGrams: 100),
        "cookie":        .init(kcal: 488, protein: 5,  carbs: 64, fats: 24, typicalGrams: 30),
        "ice cream":     .init(kcal: 207, protein: 3.5,carbs: 24, fats: 11, typicalGrams: 100),
        "donut":         .init(kcal: 452, protein: 5,  carbs: 51, fats: 25, typicalGrams: 60),
        "muffin":        .init(kcal: 377, protein: 6,  carbs: 50, fats: 17, typicalGrams: 100),
        "chip":          .init(kcal: 536, protein: 7,  carbs: 53, fats: 34, typicalGrams: 30),
        "popcorn":       .init(kcal: 387, protein: 12, carbs: 78, fats: 5,  typicalGrams: 30),
        "nut":           .init(kcal: 607, protein: 20, carbs: 21, fats: 54, typicalGrams: 30),
        "soup":          .init(kcal: 56,  protein: 3,  carbs: 8,  fats: 1.5,typicalGrams: 350),
        "stew":          .init(kcal: 90,  protein: 7,  carbs: 9,  fats: 3,  typicalGrams: 350),
        "curry":         .init(kcal: 150, protein: 8,  carbs: 12, fats: 8,  typicalGrams: 300),
        "dumpling":      .init(kcal: 230, protein: 8,  carbs: 30, fats: 8,  typicalGrams: 150),
        "quinoa":        .init(kcal: 120, protein: 4.4,carbs: 21, fats: 1.9,typicalGrams: 185),
        "lentil":        .init(kcal: 116, protein: 9,  carbs: 20, fats: 0.4,typicalGrams: 200),
        "bean":          .init(kcal: 127, protein: 9,  carbs: 23, fats: 0.5,typicalGrams: 180),
        "tofu":          .init(kcal: 76,  protein: 8,  carbs: 1.9,fats: 4.8,typicalGrams: 120)
    ]
}

// MARK: - small utils

private extension Comparable {
    func clamped(to r: ClosedRange<Self>) -> Self { min(max(self, r.lowerBound), r.upperBound) }
}

nonisolated private extension String {
    var capitalizedDishName: String {
        guard let first = self.first else { return self }
        return first.uppercased() + self.dropFirst()
    }
}
