import Foundation
#if canImport(HealthKit)
import HealthKit
#endif

/// Reads HealthKit HRV + sleep + resting HR and produces a deterministic
/// recovery score (0-100). All math is rule-based; no AI involvement.
///
/// Recovery score = 50 baseline
///     + HRV vs 7-day baseline (±25 pts)
///     + sleep last night vs 8h target (±15 pts)
///     + resting HR vs 7-day baseline (±10 pts)
/// Clamped 0-100. Missing inputs reduce confidence, not score.
@MainActor
@Observable
final class RecoveryService {
    static let shared = RecoveryService()

    enum Status: String, Sendable {
        case unavailable, denied, ok
    }

    struct Reading: Equatable, Sendable {
        let score: Int            // 0-100
        let confidence: Double    // 0-1, how many signals were available
        let hrvMs: Double?        // last reading in ms
        let sleepHours: Double?
        let restingHR: Int?
        let label: String         // "TRAIN HARD" / "MODERATE" / "DELOAD"
        let recommendation: String

        static let placeholder = Reading(
            score: 70, confidence: 0,
            hrvMs: nil, sleepHours: nil, restingHR: nil,
            label: "TRAIN HARD",
            recommendation: "Connect Health to personalise your recovery score."
        )
    }

    private(set) var status: Status = .unavailable
    private(set) var latest: Reading = .placeholder

    #if canImport(HealthKit)
    private let store = HKHealthStore()
    private var inflight = false

    private var readTypes: Set<HKObjectType> {
        var set: Set<HKObjectType> = []
        if let hrv = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN) { set.insert(hrv) }
        if let rhr = HKObjectType.quantityType(forIdentifier: .restingHeartRate) { set.insert(rhr) }
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { set.insert(sleep) }
        return set
    }
    #endif

    /// Request authorization once. Safe to call repeatedly.
    func requestAccess() async {
        #if canImport(HealthKit)
        guard HKHealthStore.isHealthDataAvailable() else {
            status = .unavailable
            return
        }
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
            status = .ok
            await refresh()
        } catch {
            status = .denied
        }
        #else
        status = .unavailable
        #endif
    }

    /// Pull latest signals and recompute the score.
    func refresh() async {
        #if canImport(HealthKit)
        guard HKHealthStore.isHealthDataAvailable() else { return }
        if inflight { return }
        inflight = true
        defer { inflight = false }

        async let hrvNow = sampleAverage(.heartRateVariabilitySDNN, since: hoursAgo(48), unit: .secondUnit(with: .milli))
        async let hrvBase = sampleAverage(.heartRateVariabilitySDNN, since: hoursAgo(24 * 7), unit: .secondUnit(with: .milli))
        async let rhrNow = sampleAverage(.restingHeartRate, since: hoursAgo(48), unit: HKUnit.count().unitDivided(by: .minute()))
        async let rhrBase = sampleAverage(.restingHeartRate, since: hoursAgo(24 * 7), unit: HKUnit.count().unitDivided(by: .minute()))
        async let sleepHrs = sleepHoursLastNight()

        let hrv = await hrvNow
        let hrvBaseline = await hrvBase
        let rhr = await rhrNow
        let rhrBaseline = await rhrBase
        let sleep = await sleepHrs

        latest = compute(hrv: hrv, hrvBase: hrvBaseline, sleep: sleep, rhr: rhr, rhrBase: rhrBaseline)
        #endif
    }

    // MARK: - Pure scoring

    /// Pure deterministic scoring — same inputs always produce the same output.
    nonisolated static func score(
        hrv: Double?, hrvBase: Double?,
        sleep: Double?,
        rhr: Double?, rhrBase: Double?
    ) -> Reading {
        var pts = 50.0
        var signals = 0.0
        var totalSignals = 0.0

        // HRV: higher than baseline = recovered.
        totalSignals += 1
        if let h = hrv, let b = hrvBase, b > 0 {
            let delta = (h - b) / b  // -1...+1+
            pts += max(-25, min(25, delta * 60))
            signals += 1
        }
        // Sleep: 8h target.
        totalSignals += 1
        if let s = sleep {
            let delta = (s - 8.0) / 8.0
            pts += max(-15, min(15, delta * 25))
            signals += 1
        }
        // Resting HR: LOWER than baseline = recovered.
        totalSignals += 1
        if let r = rhr, let b = rhrBase, b > 0 {
            let delta = (b - r) / b
            pts += max(-10, min(10, delta * 40))
            signals += 1
        }
        let clamped = max(0, min(100, Int(pts.rounded())))
        let conf = totalSignals > 0 ? signals / totalSignals : 0
        let label: String
        let rec: String
        switch clamped {
        case 75...:
            label = "TRAIN HARD"
            rec = "Body's fresh — push hard on your top sets today."
        case 50..<75:
            label = "MODERATE"
            rec = "Decent recovery — train as planned, leave a rep in reserve."
        default:
            label = "DELOAD"
            rec = "Recovery low — drop intensity 10% or take an easy day."
        }
        return Reading(
            score: clamped, confidence: conf,
            hrvMs: hrv, sleepHours: sleep, restingHR: rhr.map { Int($0.rounded()) },
            label: label, recommendation: rec
        )
    }

    private nonisolated func compute(
        hrv: Double?, hrvBase: Double?,
        sleep: Double?, rhr: Double?, rhrBase: Double?
    ) -> Reading {
        Self.score(hrv: hrv, hrvBase: hrvBase, sleep: sleep, rhr: rhr, rhrBase: rhrBase)
    }

    // MARK: - HealthKit plumbing

    #if canImport(HealthKit)
    private nonisolated func hoursAgo(_ h: Int) -> Date {
        Date().addingTimeInterval(-Double(h) * 3600)
    }

    private nonisolated func sampleAverage(
        _ id: HKQuantityTypeIdentifier,
        since: Date,
        unit: HKUnit
    ) async -> Double? {
        guard let type = HKObjectType.quantityType(forIdentifier: id) else { return nil }
        return await withCheckedContinuation { cont in
            let pred = HKQuery.predicateForSamples(withStart: since, end: nil, options: .strictStartDate)
            let q = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: pred,
                options: .discreteAverage
            ) { _, stats, _ in
                let v = stats?.averageQuantity()?.doubleValue(for: unit)
                cont.resume(returning: v)
            }
            HKHealthStore().execute(q)
        }
    }

    private nonisolated func sleepHoursLastNight() async -> Double? {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return nil }
        let cal = Calendar.current
        let endRef = Date()
        // Window: yesterday 6pm → today noon
        let start = cal.date(byAdding: .hour, value: -24, to: endRef) ?? endRef.addingTimeInterval(-86400)
        let pred = HKQuery.predicateForSamples(withStart: start, end: endRef, options: .strictStartDate)
        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: pred, limit: 200, sortDescriptors: nil) { _, samples, _ in
                guard let cats = samples as? [HKCategorySample] else { cont.resume(returning: nil); return }
                let asleep = cats.filter { sample in
                    let v = sample.value
                    // iOS 16+: asleepCore/Deep/REM/Unspecified; older: asleep
                    return v == HKCategoryValueSleepAnalysis.asleepCore.rawValue
                        || v == HKCategoryValueSleepAnalysis.asleepDeep.rawValue
                        || v == HKCategoryValueSleepAnalysis.asleepREM.rawValue
                        || v == HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue
                }
                let total = asleep.reduce(0.0) { acc, s in
                    acc + s.endDate.timeIntervalSince(s.startDate)
                }
                let hours = total / 3600
                cont.resume(returning: hours > 0 ? hours : nil)
            }
            HKHealthStore().execute(q)
        }
    }
    #endif
}
