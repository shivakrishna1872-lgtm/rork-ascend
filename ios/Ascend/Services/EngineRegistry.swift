import Foundation
import CryptoKit

/// Versioned registry for the deterministic scoring engines.
///
/// Every shipped engine is **immutable**. To change a formula, ship a new
/// version (`PSLEngine_v2`) — never edit an existing one. This keeps past
/// scans reproducible forever and gives the analytics pipeline a stable
/// reference frame.
///
/// Every `ScanResult` persisted to disk must include:
/// - `engineVersion`   — which engine produced the numbers
/// - `calibrationVersion` — which calibration profile was applied
/// - `inputHash`       — sha256 of the Vision anchors (reproducibility key)
///
/// AI models live OUTSIDE this registry; they can never modify scores.
nonisolated enum EngineRegistry {

    // MARK: - Engine identifiers (frozen)
    //
    // Append new versions here. Never rename or remove an existing one —
    // past scans reference these strings.
    enum PSL: String, CaseIterable {
        case v1 = "PSLEngine_v1"
        static var current: PSL { .v1 }
    }

    enum Physique: String, CaseIterable {
        case v1 = "PhysiqueEngine_v1"
        static var current: Physique { .v1 }
    }

    enum Nutrition: String, CaseIterable {
        case v1 = "NutritionEngine_v1"
        static var current: Nutrition { .v1 }
    }

    // MARK: - Input hashing (provenance)

    /// SHA-256 of the deterministic input. Same anchors → same hash → same score.
    static func hash(_ values: [Double]) -> String {
        // Round to 4 decimals so floating-point jitter doesn't change the hash.
        let normalized = values.map { (round($0 * 10_000) / 10_000).description }
        let joined = normalized.joined(separator: "|")
        let digest = SHA256.hash(data: Data(joined.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func hashPhysiqueAnchors(_ a: PhysiqueAnchors) -> String {
        hash([
            a.symmetry, a.shoulderWaistRatio, a.waistShoulderRatio,
            a.thighHipRatio, a.torsoAspect, a.limbSymmetry,
            a.shoulderTiltDeg, a.coverageY, a.confidence,
            Double(a.detectedAngles), a.navyBodyFatPercent
        ])
    }

    static func hashFaceMeasurements(_ m: FaceMeasurements, sampleCount: Int) -> String {
        hash([
            m.symmetry, m.thirds, m.canthalTiltDeg,
            m.eyeSpacingRatio, m.jawRatio, Double(sampleCount)
        ])
    }
}

// MARK: - Engine Manifest

/// Signed manifest describing the active engine versions. Loaded at launch.
///
/// Rules:
/// - Bundled default ships with the app and is always usable offline.
/// - Optional remote manifest (signed JSON) can OVERRIDE which version is
///   active, but never ships new code — every version it can select must
///   already be compiled into the app.
/// - No remote code execution. Ever.
nonisolated struct EngineManifest: Codable, Equatable {
    let psl: String
    let physique: String
    let nutrition: String
    let calibrationVersion: String
    let revision: Int
    let signature: String?

    static let bundled = EngineManifest(
        psl: EngineRegistry.PSL.current.rawValue,
        physique: EngineRegistry.Physique.current.rawValue,
        nutrition: EngineRegistry.Nutrition.current.rawValue,
        calibrationVersion: "calibration_v1",
        revision: 1,
        signature: nil
    )

    /// Returns the resolved engine ID, or the bundled default if the manifest
    /// references a version that isn't compiled into this binary.
    var resolvedPSL: EngineRegistry.PSL {
        EngineRegistry.PSL(rawValue: psl) ?? .current
    }
    var resolvedPhysique: EngineRegistry.Physique {
        EngineRegistry.Physique(rawValue: physique) ?? .current
    }
    var resolvedNutrition: EngineRegistry.Nutrition {
        EngineRegistry.Nutrition(rawValue: nutrition) ?? .current
    }
}

/// Loads, caches, and validates the engine manifest. Falls back silently.
@MainActor
final class EngineManifestStore {
    static let shared = EngineManifestStore()

    private let defaultsKey = "ascend.engineManifest.v1"
    private(set) var current: EngineManifest = .bundled

    init() { load() }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode(EngineManifest.self, from: data)
        else {
            current = .bundled
            return
        }
        current = decoded
    }

    /// Persist a manifest. In production this would verify `signature` against
    /// a bundled public key; today we accept locally-cached manifests only.
    func update(_ manifest: EngineManifest) {
        guard manifest.revision >= current.revision else { return }
        current = manifest
        if let data = try? JSONEncoder().encode(manifest) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    func reset() {
        current = .bundled
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }
}
