import Foundation
import SwiftData

/// Append-only feedback log. Events are **immutable** once written and feed
/// the bounded calibration update pipeline.
///
/// Rules:
/// - Never edit or delete an event (only insert).
/// - AI cannot create or modify events — only direct user actions can.
/// - Used exclusively to nudge `CalibrationProfile`; never to modify scores
///   directly or to retrain anything in production.
@Model
final class FeedbackEvent {
    /// Free-form key linking the event back to its source scan, if any.
    var scanResultId: String?
    /// Metric the user is giving feedback on.
    var metricRaw: String
    /// Kind of feedback (accurate / inaccurate / correction).
    var kindRaw: String
    /// Optional user-supplied correction value (interpreted per metric).
    var correctionValue: Double
    /// Engine version active when this event was created.
    var engineVersion: String
    /// Calibration version active when this event was created.
    var calibrationVersion: String
    var createdAt: Date

    init(
        scanResultId: String? = nil,
        metric: FeedbackMetric,
        kind: FeedbackKind,
        correctionValue: Double = 0,
        engineVersion: String,
        calibrationVersion: String,
        createdAt: Date = .now
    ) {
        self.scanResultId = scanResultId
        self.metricRaw = metric.rawValue
        self.kindRaw = kind.rawValue
        self.correctionValue = correctionValue
        self.engineVersion = engineVersion
        self.calibrationVersion = calibrationVersion
        self.createdAt = createdAt
    }

    var metric: FeedbackMetric { FeedbackMetric(rawValue: metricRaw) ?? .posture }
    var kind: FeedbackKind { FeedbackKind(rawValue: kindRaw) ?? .accurate }
}

nonisolated enum FeedbackKind: String, Codable {
    case accurate
    case inaccurate
    case correction
}

/// Single entry point for converting a user feedback event into a bounded
/// calibration nudge. Lives here so the rules are colocated with the model.
@MainActor
enum FeedbackPipeline {
    /// Record a feedback event and fold it into the user's calibration.
    /// The event itself is append-only; the calibration update is bounded.
    static func record(
        scanResultId: String?,
        metric: FeedbackMetric,
        kind: FeedbackKind,
        correctionValue: Double = 0,
        userKey: String,
        in ctx: ModelContext
    ) {
        let calibration = CalibrationResolver.resolve(for: userKey, in: ctx)
        let event = FeedbackEvent(
            scanResultId: scanResultId,
            metric: metric,
            kind: kind,
            correctionValue: correctionValue,
            engineVersion: activeEngineVersion(for: metric),
            calibrationVersion: calibration.version
        )
        ctx.insert(event)

        // Translate the feedback into a bounded EMA nudge.
        let delta: Double = {
            switch kind {
            case .accurate:    return 0
            case .inaccurate:  return correctionValue == 0 ? -0.04 : correctionValue
            case .correction:  return correctionValue
            }
        }()
        if delta != 0 {
            calibration.ingest(metric: metric, delta: delta)
        }
        try? ctx.save()
    }

    private static func activeEngineVersion(for metric: FeedbackMetric) -> String {
        switch metric {
        case .posture, .symmetry, .vTaper:
            return EngineRegistry.Physique.current.rawValue
        case .calories:
            return EngineRegistry.Nutrition.current.rawValue
        }
    }
}
