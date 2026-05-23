import Foundation
import UIKit
import CryptoKit

/// Global async request gate. Bounds concurrent in-flight AI calls so a burst
/// of users tapping "Scan" doesn't stampede the proxy, and deduplicates
/// identical in-flight requests (perceptual image hash + prompt hash) so two
/// identical scans submitted back-to-back only hit the model once.
///
/// Designed to handle very high concurrency: the actor only holds two small
/// dictionaries (in-flight task handles and current concurrency count); the
/// actual model calls run on detached tasks so the actor never blocks.
actor RequestQueue {
    static let shared = RequestQueue()

    /// Cap concurrent provider calls. Tuned for mobile — keeps the device cool
    /// and avoids burning credits when many features fire at once.
    private let maxConcurrent = 4
    private var inFlight = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    /// Map of dedup-key → in-flight task. Subsequent requests with the same
    /// key await the same Task.
    private var dedup: [String: Task<Any, Error>] = [:]

    /// Run a unique request body. If another caller is already running a
    /// request with the same `key`, this returns the same result instead of
    /// firing a duplicate call.
    func run<T: Sendable>(key: String, _ body: @Sendable @escaping () async throws -> T) async throws -> T {
        if let existing = dedup[key] {
            let any = try await existing.value
            if let v = any as? T { return v }
        }
        let task = Task<Any, Error> { [weak self] in
            await self?.acquire()
            defer { Task { [weak self] in await self?.release() } }
            return try await body() as Any
        }
        dedup[key] = task
        defer { dedup[key] = nil }
        let any = try await task.value
        guard let v = any as? T else { throw RequestQueueError.typeMismatch }
        return v
    }

    private func acquire() async {
        if inFlight < maxConcurrent {
            inFlight += 1
            return
        }
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            waiters.append(c)
        }
        inFlight += 1
    }

    private func release() {
        inFlight = max(0, inFlight - 1)
        if !waiters.isEmpty {
            let c = waiters.removeFirst()
            c.resume()
        }
    }
}

enum RequestQueueError: Error { case typeMismatch }

/// Stable perceptual-ish hash for images so visually identical photos
/// dedupe across re-encodes and minor resize. Cheap: downsample to 16x16
/// grayscale and SHA over the bytes.
nonisolated enum ImageDedupHash {
    static func hash(_ images: [UIImage]) -> String {
        var hasher = SHA256()
        for img in images {
            let bytes = downsample(img)
            hasher.update(data: Data(bytes))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func downsample(_ image: UIImage) -> [UInt8] {
        let size = CGSize(width: 16, height: 16)
        UIGraphicsBeginImageContextWithOptions(size, true, 1)
        defer { UIGraphicsEndImageContext() }
        image.draw(in: CGRect(origin: .zero, size: size))
        guard let cg = UIGraphicsGetImageFromCurrentImageContext()?.cgImage else { return [] }
        let width = cg.width, height = cg.height
        var buf = [UInt8](repeating: 0, count: width * height * 4)
        let cs = CGColorSpaceCreateDeviceRGB()
        if let ctx = CGContext(data: &buf, width: width, height: height, bitsPerComponent: 8,
                               bytesPerRow: width * 4, space: cs,
                               bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        // Reduce to grayscale ints to absorb tiny color/jpeg noise.
        var gray: [UInt8] = []
        gray.reserveCapacity(width * height)
        var i = 0
        while i + 2 < buf.count {
            let g = (Int(buf[i]) * 30 + Int(buf[i+1]) * 59 + Int(buf[i+2]) * 11) / 100
            gray.append(UInt8(g & 0xFC)) // drop low 2 bits to absorb compression noise
            i += 4
        }
        return gray
    }
}
