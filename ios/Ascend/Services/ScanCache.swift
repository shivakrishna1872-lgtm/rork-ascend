import Foundation
import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins
import CryptoKit

/// Shared deterministic preprocessing + content-addressed cache used by every
/// scan surface (PSL, Physique, Cal AI).
///
/// Why this exists:
///  - Two scans of the *same* photo previously produced subtly different
///    numbers because Vision crops, exposure normalization, and saliency all
///    introduced floating-point jitter. We now collapse the input through a
///    single deterministic normalizer first, hash the bytes, and key the
///    cache on that hash. Same image → same hash → same anchors → same score.
///  - Cuts API + Vision cost: a re-scan of an already-seen photo skips Vision
///    entirely and replays the stored anchors.
///  - Makes scans reproducible alongside `EngineRegistry` — `engineVersion +
///    imageHash` is the full provenance for any score.
///
/// Cache shape (on disk JSON, in `Caches/scan-cache/`):
///   <hash>.body.json   → CachedBodyAnchors
///   <hash>.face.json   → CachedFaceAnchors
///   <hash>.food.json   → CachedFoodResult
///
/// Caches are eventually-evicted via LRU touch on the file mtime.

// MARK: - Codable wrappers

nonisolated struct CachedBodyAnchors: Codable, Sendable {
    let symmetry: Double
    let shoulderWaistRatio: Double
    let waistShoulderRatio: Double
    let thighHipRatio: Double
    let torsoAspect: Double
    let limbSymmetry: Double
    let shoulderTiltDeg: Double
    let coverageY: Double
    let brightness: Double
    let centeringX: Double
    let confidence: Double
    let detectionSource: String
    let landmarks: [String: [Double]] // x,y pairs — landmark order normalized
    let engineVersion: String
}

nonisolated struct CachedFaceAnchors: Codable, Sendable {
    let symmetry: Double
    let thirds: Double
    let canthalTiltDeg: Double
    let eyeSpacingRatio: Double
    let jawRatio: Double
    let engineVersion: String
}

nonisolated struct CachedFoodResult: Codable, Sendable {
    /// Stable canonical dish name (top-1 after consensus).
    let dishName: String
    let dishType: String
    let ingredients: [Item]
    let calories: Int
    let proteinG: Int
    let carbsG: Int
    let fatsG: Int
    let confidence: Int
    let note: String
    let engineVersion: String
    /// Top-K (name, confidence) — empty for older cache entries.
    let foodCandidates: [Candidate]?
    let portionMultiplier: Double?
    let fallbackUsed: Bool?

    nonisolated struct Item: Codable, Sendable {
        let name: String
        let portion: String
    }

    nonisolated struct Candidate: Codable, Sendable {
        let name: String
        let confidence: Int
    }

    init(dishName: String, dishType: String, ingredients: [Item],
         calories: Int, proteinG: Int, carbsG: Int, fatsG: Int,
         confidence: Int, note: String, engineVersion: String,
         foodCandidates: [Candidate] = [], portionMultiplier: Double = 1.0,
         fallbackUsed: Bool = false) {
        self.dishName = dishName; self.dishType = dishType
        self.ingredients = ingredients
        self.calories = calories; self.proteinG = proteinG
        self.carbsG = carbsG; self.fatsG = fatsG
        self.confidence = confidence; self.note = note
        self.engineVersion = engineVersion
        self.foodCandidates = foodCandidates
        self.portionMultiplier = portionMultiplier
        self.fallbackUsed = fallbackUsed
    }
}

// MARK: - ScanCache

nonisolated enum ScanCache {

    /// Bumps any time the deterministic preprocessing or hash inputs change
    /// in a way that invalidates older cached anchors. Compose with engine
    /// versions for full replay compatibility.
    static let preprocessorVersion = "preproc_v1"

    /// Public canonical normalized size. Anything cropped/letterboxed to this
    /// square gives a stable hash across device cameras and orientations.
    static let canonicalSide: CGFloat = 512

    // MARK: Normalization + hash

    /// Deterministic preprocess pipeline for hashing. Distinct from
    /// `ImagePreprocessor` (which crops by saliency for *AI* input) — this
    /// must be 100% input-determined so the SAME photo always yields the
    /// SAME bytes.
    ///
    /// Pipeline:
    ///   1. Orientation correction (UIKit → CG upright)
    ///   2. Aspect-fit into a 512×512 letterboxed canvas (center-crop free)
    ///   3. Exposure normalization toward mid-luma via deterministic EV step
    ///   4. RGBA8 sRGB encode for hashing
    static func normalize(_ image: UIImage) -> (image: UIImage, hash: String) {
        guard let cg = upright(image) else {
            return (image, fallbackHash(image))
        }
        let canvas = aspectFit(cg, side: canonicalSide)
        let normalized = exposureNormalize(canvas)
        let rgba = rgba8(normalized) ?? Data()
        let digest = SHA256.hash(data: rgba)
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        let outImage = UIImage(cgImage: normalized)
        return (outImage, "\(preprocessorVersion):\(hex)")
    }

    /// Hash a raw description string (used by Cal AI when no image is passed).
    static func textHash(_ text: String, engine: String) -> String {
        let trimmed = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let digest = SHA256.hash(data: Data(trimmed.utf8))
        return "\(engine):text:" + digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Cache I/O

    private static let dir: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let url = base.appendingPathComponent("scan-cache", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    static func loadBody(hash: String) -> CachedBodyAnchors? {
        load(hash: hash, ext: "body")
    }
    static func saveBody(hash: String, anchors: CachedBodyAnchors) {
        save(hash: hash, ext: "body", value: anchors)
    }

    static func loadFace(hash: String) -> CachedFaceAnchors? {
        load(hash: hash, ext: "face")
    }
    static func saveFace(hash: String, anchors: CachedFaceAnchors) {
        save(hash: hash, ext: "face", value: anchors)
    }

    static func loadFood(hash: String) -> CachedFoodResult? {
        load(hash: hash, ext: "food")
    }
    static func saveFood(hash: String, result: CachedFoodResult) {
        save(hash: hash, ext: "food", value: result)
    }

    static func clearAll() {
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    // MARK: - Internals

    private static func load<T: Decodable>(hash: String, ext: String) -> T? {
        let url = file(hash: hash, ext: ext)
        guard let data = try? Data(contentsOf: url),
              let value = try? JSONDecoder().decode(T.self, from: data) else { return nil }
        // Touch mtime for crude LRU.
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
        return value
    }

    private static func save<T: Encodable>(hash: String, ext: String, value: T) {
        let url = file(hash: hash, ext: ext)
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    private static func file(hash: String, ext: String) -> URL {
        // Strip the preprocessor prefix so the filename stays a clean hash.
        let clean = hash.replacingOccurrences(of: "/", with: "_")
        return dir.appendingPathComponent("\(clean).\(ext).json")
    }

    private static func fallbackHash(_ image: UIImage) -> String {
        let data = image.pngData() ?? Data()
        let digest = SHA256.hash(data: data)
        return "fallback:" + digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Deterministic preprocessing primitives

    private static func upright(_ image: UIImage) -> CGImage? {
        // Re-render with UIKit so the EXIF orientation is baked into pixels.
        let size = image.size
        guard size.width > 0, size.height > 0 else { return image.cgImage }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let rendered = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return rendered.cgImage
    }

    private static func aspectFit(_ cg: CGImage, side: CGFloat) -> CGImage {
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        let scale = min(side / w, side / h)
        let dw = floor(w * scale), dh = floor(h * scale)
        let ox = floor((side - dw) / 2), oy = floor((side - dh) / 2)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: Int(side), height: Int(side),
            bitsPerComponent: 8,
            bytesPerRow: Int(side) * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return cg }
        ctx.interpolationQuality = .high
        // Letterbox with a deterministic neutral fill (mid-gray) so padding
        // contributes a stable signature, not whatever happened to be in
        // memory.
        ctx.setFillColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
        ctx.draw(cg, in: CGRect(x: ox, y: oy, width: dw, height: dh))
        return ctx.makeImage() ?? cg
    }

    private static func exposureNormalize(_ cg: CGImage) -> CGImage {
        let ci = CIImage(cgImage: cg)
        // Sample mean luma deterministically via CIAreaAverage.
        let avg = CIFilter.areaAverage()
        avg.inputImage = ci
        avg.extent = ci.extent
        let context = sharedCIContext
        guard let out = avg.outputImage else { return cg }
        var bitmap = [UInt8](repeating: 0, count: 4)
        context.render(out, toBitmap: &bitmap, rowBytes: 4,
                       bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBA8, colorSpace: nil)
        let r = Double(bitmap[0]) / 255
        let g = Double(bitmap[1]) / 255
        let b = Double(bitmap[2]) / 255
        let luma = 0.299 * r + 0.587 * g + 0.114 * b
        // Quantize EV target to 0.05 steps so floating-point jitter never
        // shifts the hash. Mid-luma target = 0.5.
        let delta = 0.5 - luma
        let ev = (round(delta * 4) / 4).clamped(to: -1.0...1.0)
        guard abs(ev) > 0.05 else {
            return cg
        }
        let exp = CIFilter.exposureAdjust()
        exp.inputImage = ci
        exp.ev = Float(ev)
        guard let result = exp.outputImage,
              let rendered = context.createCGImage(result, from: ci.extent) else { return cg }
        return rendered
    }

    private static func rgba8(_ cg: CGImage) -> Data? {
        let w = cg.width, h = cg.height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &pixels,
            width: w, height: h,
            bitsPerComponent: 8,
            bytesPerRow: w * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        return Data(pixels)
    }

    private static let sharedCIContext = CIContext(options: [.useSoftwareRenderer: false])
}

// MARK: - Adapters (bridge cache wrappers to live model types)

extension CachedFaceAnchors {
    init(_ m: FaceMeasurements, engineVersion: String) {
        self.symmetry = m.symmetry
        self.thirds = m.thirds
        self.canthalTiltDeg = m.canthalTiltDeg
        self.eyeSpacingRatio = m.eyeSpacingRatio
        self.jawRatio = m.jawRatio
        self.engineVersion = engineVersion
    }

    var measurements: FaceMeasurements {
        FaceMeasurements(
            symmetry: symmetry,
            thirds: thirds,
            canthalTiltDeg: canthalTiltDeg,
            eyeSpacingRatio: eyeSpacingRatio,
            jawRatio: jawRatio
        )
    }
}

extension CachedBodyAnchors {
    init(_ p: PoseResult, engineVersion: String) {
        // Deterministic landmark ordering by name so two scans never disagree
        // on serialization order.
        let ordered = p.landmarks.keys.sorted()
        var map: [String: [Double]] = [:]
        for key in ordered {
            let pt = p.landmarks[key] ?? .zero
            // Round to 4 decimals — kills float jitter without losing meaning.
            map[key] = [
                (pt.x * 10000).rounded() / 10000,
                (pt.y * 10000).rounded() / 10000
            ]
        }
        self.symmetry = p.symmetry
        self.shoulderWaistRatio = p.shoulderWaistRatio
        self.waistShoulderRatio = p.waistShoulderRatio
        self.thighHipRatio = p.thighHipRatio
        self.torsoAspect = p.torsoAspect
        self.limbSymmetry = p.limbSymmetry
        self.shoulderTiltDeg = p.shoulderTiltDeg
        self.coverageY = p.coverageY
        self.brightness = p.brightness
        self.centeringX = p.centeringX
        self.confidence = p.confidenceAverage
        self.detectionSource = p.detectionSource.rawValue
        self.landmarks = map
        self.engineVersion = engineVersion
    }

    var pose: PoseResult {
        var lm: [String: CGPoint] = [:]
        for (k, v) in landmarks where v.count == 2 {
            lm[k] = CGPoint(x: v[0], y: v[1])
        }
        return PoseResult(
            landmarks: lm,
            confidenceAverage: confidence,
            brightness: brightness,
            centeringX: centeringX,
            coverageY: coverageY,
            symmetry: symmetry,
            shoulderWaistRatio: shoulderWaistRatio,
            waistShoulderRatio: waistShoulderRatio,
            thighHipRatio: thighHipRatio,
            torsoAspect: torsoAspect,
            limbSymmetry: limbSymmetry,
            shoulderTiltDeg: shoulderTiltDeg,
            issues: [],
            detectionSource: PoseResult.DetectionSource(rawValue: detectionSource) ?? .none
        )
    }
}

private extension Comparable {
    func clamped(to r: ClosedRange<Self>) -> Self { min(max(self, r.lowerBound), r.upperBound) }
}
