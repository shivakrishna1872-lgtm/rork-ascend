import Foundation

/// Deterministic nutrition lookup using free public APIs only.
///
/// Priority order:
///  1. In-memory + UserDefaults cache (zero network)
///  2. Open Food Facts — barcode + packaged foods (free, no key)
///  3. USDA FoodData Central — raw + validated nutrition (free, DEMO_KEY)
///
/// This is the "second option" calorie path: never uses AI, never hallucinates,
/// caches aggressively for scale, and degrades to nil instead of fabricating
/// macros.
actor NutritionService {
    static let shared = NutritionService()

    nonisolated struct Macros: Codable, Sendable {
        let name: String
        let kcalPer100g: Double
        let proteinPer100g: Double
        let carbsPer100g: Double
        let fatPer100g: Double
        let source: String   // "off" | "usda" | "cache"
    }

    private var memCache: [String: Macros] = [:]
    private let cachePrefix = "nutrition.cache.v1."

    // MARK: - Public

    /// Look up nutrition by barcode (Open Food Facts).
    func byBarcode(_ code: String) async -> Macros? {
        let key = "barcode:\(code)"
        if let m = readCache(key) { return m }
        guard let url = URL(string: "https://world.openfoodfacts.org/api/v2/product/\(code).json?fields=product_name,nutriments") else { return nil }
        guard let macros = try? await fetchOFF(url: url) else { return nil }
        writeCache(key, macros)
        return macros
    }

    /// Look up nutrition by food name. Tries USDA first (better for raw foods),
    /// then Open Food Facts as fallback for branded items.
    func byName(_ name: String) async -> Macros? {
        let key = "name:\(name.lowercased())"
        if let m = readCache(key) { return m }
        if let m = try? await fetchUSDA(query: name) {
            writeCache(key, m); return m
        }
        if let m = try? await fetchOFFSearch(query: name) {
            writeCache(key, m); return m
        }
        return nil
    }

    // MARK: - Open Food Facts

    private func fetchOFF(url: URL) async throws -> Macros? {
        var req = URLRequest(url: url)
        req.timeoutInterval = 10
        req.setValue("Ascend-iOS/1.0 (deterministic-fallback)", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let product = json["product"] as? [String: Any] else { return nil }
        let name = (product["product_name"] as? String) ?? "Food"
        guard let n = product["nutriments"] as? [String: Any] else { return nil }
        func d(_ key: String) -> Double {
            if let v = n[key] as? Double { return v }
            if let v = n[key] as? Int { return Double(v) }
            if let s = n[key] as? String, let v = Double(s) { return v }
            return 0
        }
        let kcal = d("energy-kcal_100g")
        guard kcal > 0 else { return nil }
        return Macros(
            name: name,
            kcalPer100g: kcal,
            proteinPer100g: d("proteins_100g"),
            carbsPer100g: d("carbohydrates_100g"),
            fatPer100g: d("fat_100g"),
            source: "off"
        )
    }

    private func fetchOFFSearch(query: String) async throws -> Macros? {
        guard let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://world.openfoodfacts.org/cgi/search.pl?search_terms=\(q)&search_simple=1&action=process&json=1&page_size=1") else { return nil }
        return try await fetchOFF(url: url)
    }

    // MARK: - USDA FoodData Central

    private func fetchUSDA(query: String) async throws -> Macros? {
        guard let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://api.nal.usda.gov/fdc/v1/foods/search?api_key=DEMO_KEY&query=\(q)&pageSize=1") else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 10
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let foods = json["foods"] as? [[String: Any]],
              let food = foods.first else { return nil }
        let name = (food["description"] as? String) ?? query
        let nutrients = (food["foodNutrients"] as? [[String: Any]]) ?? []
        func nutrient(_ ids: [Int]) -> Double {
            for n in nutrients {
                if let id = n["nutrientId"] as? Int, ids.contains(id),
                   let v = n["value"] as? Double {
                    return v
                }
            }
            return 0
        }
        let kcal = nutrient([1008])      // Energy kcal
        guard kcal > 0 else { return nil }
        return Macros(
            name: name,
            kcalPer100g: kcal,
            proteinPer100g: nutrient([1003]),
            carbsPer100g: nutrient([1005]),
            fatPer100g: nutrient([1004]),
            source: "usda"
        )
    }

    // MARK: - Cache

    private func readCache(_ key: String) -> Macros? {
        if let m = memCache[key] { return m }
        guard let data = UserDefaults.standard.data(forKey: cachePrefix + key),
              let m = try? JSONDecoder().decode(Macros.self, from: data) else { return nil }
        memCache[key] = m
        return m
    }

    private func writeCache(_ key: String, _ m: Macros) {
        memCache[key] = m
        if let data = try? JSONEncoder().encode(m) {
            UserDefaults.standard.set(data, forKey: cachePrefix + key)
        }
    }
}
