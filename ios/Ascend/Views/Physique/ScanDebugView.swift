import SwiftUI
import SwiftData

/// Replay + stress-test harness for a single physique scan.
///
/// Opens from a long-press on the date label in `PhysiqueResultsView`.
/// Lets us verify deterministic replay (`imageHash + engineVersion → identical
/// result`) over N iterations and inspect every grounded input the scoring
/// engine consumed.
struct ScanDebugView: View {
    let record: PhysiqueScanRecord
    @Environment(\.dismiss) private var dismiss

    @State private var iterations: Int = 100
    @State private var stressResult: StressResult?
    @State private var running: Bool = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    provenanceCard
                    partialityCard
                    reasonsCard
                    payloadCard
                    stressCard
                    Color.clear.frame(height: 40)
                }
                .padding(16)
            }
            .scrollIndicators(.hidden)
            .background(AmbientBackground().ignoresSafeArea())
            .navigationTitle("Scan Debug")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Provenance

    private var provenanceCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            header("Provenance")
            kv("Engine", record.engineVersion)
            kv("Calibration", record.calibrationVersion)
            kv("Input Hash", record.inputHash.isEmpty ? "—" : String(record.inputHash.prefix(16)) + "…")
            kv("Date", record.date.formatted(date: .abbreviated, time: .shortened))
            kv("Score", String(format: "%.1f", record.physiqueScore))
            kv("Confidence", "\(Int(record.bodyFatConfidence))%")
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: 16)
    }

    private var partialityCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            header("Partiality")
            HStack(spacing: 8) {
                Image(systemName: partialityIcon)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(partialityColor)
                Text(record.partialityRaw.uppercased())
                    .font(.system(size: 12, weight: .bold)).tracking(1.4)
                    .foregroundStyle(partialityColor)
                Spacer()
                if record.isUncertaintyEvent {
                    Text("UNCERTAINTY EVENT")
                        .font(.system(size: 9, weight: .bold)).tracking(1.2)
                        .foregroundStyle(Theme.warn)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(Theme.warn.opacity(0.15)))
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: 16)
    }

    private var partialityIcon: String {
        switch record.partialityRaw {
        case "full": "checkmark.seal.fill"
        case "torsoOnly": "person.crop.rectangle"
        case "upperOnly": "person.crop.circle"
        case "obstructed": "eye.slash.fill"
        default: "questionmark.circle.fill"
        }
    }

    private var partialityColor: Color {
        record.partialityRaw == "full" ? Theme.good : Theme.warn
    }

    private var reasonsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            header("Confidence Reasons (\(record.confidenceReasons.count))")
            if record.confidenceReasons.isEmpty {
                Text("None — clean scan.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
            } else {
                ForEach(Array(record.confidenceReasons.enumerated()), id: \.offset) { _, r in
                    Text("• \(r)")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: 16)
    }

    private var payloadCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            header("Replay Payload")
            if record.inputPayload.isEmpty {
                Text("Empty — pre-replay scan.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
            } else {
                Text(record.inputPayload)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.35)))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: 16)
    }

    // MARK: - Stress test

    private var stressCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            header("Determinism Stress Test")

            HStack {
                Text("Iterations")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                ForEach([10, 100, 1000], id: \.self) { n in
                    Button {
                        Haptics.soft()
                        iterations = n
                    } label: {
                        Text("\(n)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(iterations == n ? Theme.bg : Theme.textPrimary)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Capsule().fill(iterations == n ? Theme.accentGlow : Color.white.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                }
            }

            Button {
                Haptics.medium()
                runStress()
            } label: {
                HStack(spacing: 8) {
                    if running {
                        ProgressView().controlSize(.small).tint(Theme.bg)
                    } else {
                        Image(systemName: "play.fill")
                            .font(.system(size: 13, weight: .bold))
                    }
                    Text(running ? "Running…" : "Run stress test")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(Theme.bg)
                .frame(maxWidth: .infinity).frame(height: 44)
                .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.95)))
            }
            .buttonStyle(.plain)
            .disabled(running || record.inputPayload.isEmpty)

            if let r = stressResult {
                stressResultView(r)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: 16)
    }

    private func stressResultView(_ r: StressResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: r.deterministic ? "checkmark.seal.fill" : "xmark.octagon.fill")
                    .foregroundStyle(r.deterministic ? Theme.good : Theme.bad)
                Text(r.deterministic ? "Deterministic" : "DRIFT DETECTED")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(r.deterministic ? Theme.good : Theme.bad)
            }
            kv("Iterations", "\(r.iterations)")
            kv("Min score", String(format: "%.4f", r.minScore))
            kv("Max score", String(format: "%.4f", r.maxScore))
            kv("Max delta", String(format: "%.4f", r.maxScore - r.minScore))
            kv("Replay vs stored", String(format: "Δ %.4f", r.replayDelta))
            kv("Elapsed", String(format: "%.1f ms", r.elapsedMs))
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.35)))
    }

    // MARK: - Helpers

    private func header(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold)).tracking(2)
            .foregroundStyle(Theme.textTertiary)
    }

    private func kv(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
            Spacer()
            Text(v).font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
                .textSelection(.enabled)
        }
    }

    private func runStress() {
        guard !record.inputPayload.isEmpty else { return }
        running = true
        let payload = record.inputPayload
        let expected = record.physiqueScore
        let n = iterations
        Task.detached {
            let result = ScanReplayHarness.stress(payload: payload, expected: expected, iterations: n)
            await MainActor.run {
                self.stressResult = result
                self.running = false
                Haptics.success()
            }
        }
    }
}

// MARK: - Harness

nonisolated struct StressResult: Sendable {
    let iterations: Int
    let minScore: Double
    let maxScore: Double
    let deterministic: Bool
    let replayDelta: Double
    let elapsedMs: Double
}

/// Pure, offline stress harness for the deterministic scoring engines.
/// Re-runs `ScanReplay.replayPhysique` N times on the stored payload and
/// reports min/max drift. A working build must always read `deterministic =
/// true` with `maxDelta == 0`.
nonisolated enum ScanReplayHarness {
    static func stress(payload: String, expected: Double, iterations: Int) -> StressResult {
        let start = Date()
        var minScore = Double.infinity
        var maxScore = -Double.infinity
        var lastScore: Double = .nan
        for _ in 0..<max(1, iterations) {
            guard let s = ScanReplay.replayPhysique(payloadJSON: payload) else {
                return StressResult(iterations: iterations, minScore: 0, maxScore: 0,
                                    deterministic: false, replayDelta: .nan,
                                    elapsedMs: Date().timeIntervalSince(start) * 1000)
            }
            minScore = min(minScore, s.pslScore)
            maxScore = max(maxScore, s.pslScore)
            lastScore = s.pslScore
        }
        let elapsed = Date().timeIntervalSince(start) * 1000
        let deterministic = (maxScore - minScore) < 0.0001
        let replayDelta = abs(lastScore - expected)
        return StressResult(iterations: iterations, minScore: minScore, maxScore: maxScore,
                            deterministic: deterministic, replayDelta: replayDelta,
                            elapsedMs: elapsed)
    }
}
