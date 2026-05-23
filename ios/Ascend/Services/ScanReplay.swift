import Foundation

/// Deterministic replay system.
///
/// Every scan persists a `ReplayPayload` (the exact engine inputs + version)
/// alongside the result. Calling `ScanReplay.replay(_:)` feeds those inputs
/// back through the same engine version and MUST produce identical numbers.
///
/// This is the debugging + trust backbone:
/// - Score changes can be audited (same inputs, different engine version)
/// - Engine bugs can be reproduced from a single payload
/// - Users can be shown "here is exactly why this score is what it is"
///
/// Replay is offline, deterministic, and free. It never calls AI.
nonisolated enum ScanReplay {

    // MARK: - Payload

    /// Self-contained payload sufficient to recompute any scan offline.
    /// Encoded as JSON and stored on the scan record's `inputPayload` column.
    nonisolated struct ReplayPayload: Codable, Equatable {
        let kind: Kind
        let engineVersion: String
        let calibrationVersion: String
        /// Calibration biases captured at scan time (not the live profile, so
        /// replay is stable even after the profile updates).
        let calibrationSnapshot: CalibrationSnapshot
        let physique: PhysiqueInputs?
        let face: FaceInputs?

        enum Kind: String, Codable { case physique, face }

        nonisolated struct CalibrationSnapshot: Codable, Equatable {
            let postureBias: Double
            let symmetryBias: Double
            let vTaperBias: Double
            let calorieOffsetPct: Double
        }

        nonisolated struct PhysiqueInputs: Codable, Equatable {
            let symmetry: Double
            let shoulderWaistRatio: Double
            let waistShoulderRatio: Double
            let thighHipRatio: Double
            let torsoAspect: Double
            let limbSymmetry: Double
            let shoulderTiltDeg: Double
            let coverageY: Double
            let confidence: Double
            let detectedAngles: Int
            let navyBodyFatPercent: Double
        }

        nonisolated struct FaceInputs: Codable, Equatable {
            let symmetry: Double
            let thirds: Double
            let canthalTiltDeg: Double
            let eyeSpacingRatio: Double
            let jawRatio: Double
            let sampleCount: Int
            let consistency: Double
        }
    }

    // MARK: - Capture

    static func capture(anchors: PhysiqueAnchors, calibration: CalibrationProfile) -> String {
        let payload = ReplayPayload(
            kind: .physique,
            engineVersion: EngineRegistry.Physique.current.rawValue,
            calibrationVersion: calibration.version,
            calibrationSnapshot: snapshot(of: calibration),
            physique: ReplayPayload.PhysiqueInputs(
                symmetry: anchors.symmetry,
                shoulderWaistRatio: anchors.shoulderWaistRatio,
                waistShoulderRatio: anchors.waistShoulderRatio,
                thighHipRatio: anchors.thighHipRatio,
                torsoAspect: anchors.torsoAspect,
                limbSymmetry: anchors.limbSymmetry,
                shoulderTiltDeg: anchors.shoulderTiltDeg,
                coverageY: anchors.coverageY,
                confidence: anchors.confidence,
                detectedAngles: anchors.detectedAngles,
                navyBodyFatPercent: anchors.navyBodyFatPercent
            ),
            face: nil
        )
        return encode(payload)
    }

    static func capture(measurements: FaceMeasurements, sampleCount: Int, consistency: Double,
                        calibration: CalibrationProfile) -> String {
        let payload = ReplayPayload(
            kind: .face,
            engineVersion: EngineRegistry.PSL.current.rawValue,
            calibrationVersion: calibration.version,
            calibrationSnapshot: snapshot(of: calibration),
            physique: nil,
            face: ReplayPayload.FaceInputs(
                symmetry: measurements.symmetry,
                thirds: measurements.thirds,
                canthalTiltDeg: measurements.canthalTiltDeg,
                eyeSpacingRatio: measurements.eyeSpacingRatio,
                jawRatio: measurements.jawRatio,
                sampleCount: sampleCount,
                consistency: consistency
            )
        )
        return encode(payload)
    }

    // MARK: - Replay

    /// Reproduces a physique scan from its stored payload. Returns `nil` if
    /// the payload is empty / malformed / wrong kind.
    static func replayPhysique(payloadJSON: String) -> DeterministicScoring.Score? {
        guard let p = decode(payloadJSON), p.kind == .physique, let inputs = p.physique else { return nil }
        let anchors = PhysiqueAnchors(
            symmetry: inputs.symmetry,
            shoulderWaistRatio: inputs.shoulderWaistRatio,
            waistShoulderRatio: inputs.waistShoulderRatio,
            thighHipRatio: inputs.thighHipRatio,
            torsoAspect: inputs.torsoAspect,
            limbSymmetry: inputs.limbSymmetry,
            shoulderTiltDeg: inputs.shoulderTiltDeg,
            coverageY: inputs.coverageY,
            confidence: inputs.confidence,
            detectedAngles: inputs.detectedAngles,
            navyBodyFatPercent: inputs.navyBodyFatPercent
        )
        return DeterministicScoring.shared.score(anchors: anchors)
    }

    /// Reproduces a face/PSL scan from its stored payload.
    static func replayFace(payloadJSON: String) -> DeterministicFaceScoring.Score? {
        guard let p = decode(payloadJSON), p.kind == .face, let inputs = p.face else { return nil }
        let m = FaceMeasurements(
            symmetry: inputs.symmetry,
            thirds: inputs.thirds,
            canthalTiltDeg: inputs.canthalTiltDeg,
            eyeSpacingRatio: inputs.eyeSpacingRatio,
            jawRatio: inputs.jawRatio
        )
        return DeterministicFaceScoring.shared.score(
            measurements: m,
            sampleCount: inputs.sampleCount,
            consistency: inputs.consistency
        )
    }

    // MARK: - Verification

    /// True if replaying produces the same `psl_score` (within rounding) as
    /// the value stored on the scan. Used for self-tests / debugging.
    static func verifyPhysique(payloadJSON: String, expected: Double, tolerance: Double = 0.15) -> Bool {
        guard let s = replayPhysique(payloadJSON: payloadJSON) else { return false }
        return abs(s.pslScore - expected) <= tolerance
    }

    static func verifyFace(payloadJSON: String, expected: Double, tolerance: Double = 0.15) -> Bool {
        guard let s = replayFace(payloadJSON: payloadJSON) else { return false }
        return abs(s.pslScore - expected) <= tolerance
    }

    // MARK: - Internals

    private static func snapshot(of c: CalibrationProfile) -> ReplayPayload.CalibrationSnapshot {
        ReplayPayload.CalibrationSnapshot(
            postureBias: c.postureBias,
            symmetryBias: c.symmetryBias,
            vTaperBias: c.vTaperBias,
            calorieOffsetPct: c.calorieOffsetPct
        )
    }

    private static func encode(_ payload: ReplayPayload) -> String {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        guard let data = try? enc.encode(payload),
              let str = String(data: data, encoding: .utf8) else { return "" }
        return str
    }

    private static func decode(_ json: String) -> ReplayPayload? {
        guard !json.isEmpty, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ReplayPayload.self, from: data)
    }
}
