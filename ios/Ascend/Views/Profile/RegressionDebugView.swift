import SwiftUI

/// Hidden debug screen behind a long-press on the profile header. Runs the
/// deterministic `RegressionRunner` over the bundled `GoldenDataset` and
/// renders pass-rate, per-tag bars, stability metrics, drift flags, and the
/// per-sample list. Read-only — never mutates engines or calibration.
struct RegressionDebugView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var report: RegressionRunner.Report?
    @State private var running: Bool = false

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground().ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 18) {
                        if let r = report {
                            headerCard(r)
                            metricsCard(r)
                            if !r.passRateByTag.isEmpty { tagsCard(r) }
                            if !r.drift.isEmpty { driftCard(r) }
                            samplesCard(r)
                        } else if running {
                            ProgressView("Running regression…")
                                .tint(Theme.accent)
                                .frame(maxWidth: .infinity, minHeight: 200)
                        } else {
                            emptyState
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 40)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Regression Debug")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Haptics.tap()
                        run()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(running)
                }
            }
            .task { if report == nil { run() } }
        }
    }

    // MARK: - Run

    private func run() {
        running = true
        Task.detached(priority: .userInitiated) {
            let r = RegressionRunner.runAll()
            await MainActor.run {
                report = r
                running = false
                Haptics.success()
            }
        }
    }

    // MARK: - Cards

    private func headerCard(_ r: RegressionRunner.Report) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("OVERALL")
                    .font(.system(size: 10, weight: .semibold)).tracking(1.4)
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
                Text(percent(r.passRate))
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(passColor(r.passRate))
            }
            ProgressView(value: r.passRate)
                .tint(passColor(r.passRate))
            HStack(spacing: 14) {
                versionPill("PSL", r.engineVersionPSL)
                versionPill("PHY", r.engineVersionPhysique)
                versionPill("NUT", r.engineVersionNutrition)
            }
            Text("Calibration \(r.calibrationVersion) · \(r.samples.count) samples")
                .font(.system(size: 10)).foregroundStyle(Theme.textTertiary)
        }
        .padding(16)
        .glassCard(radius: 18)
    }

    private func metricsCard(_ r: RegressionRunner.Report) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Stability")
            VStack(spacing: 10) {
                metricRow("Same-image variance",
                          String(format: "%.4f", r.metrics.sameImageVariance),
                          ok: r.metrics.sameImageVariance <= 0.0001)
                metricRow("Near-identical variance",
                          String(format: "%.3f", r.metrics.nearIdenticalVariance),
                          ok: r.metrics.nearIdenticalVariance <= 4.0)
                metricRow("Confidence calibration",
                          percent(r.metrics.confidenceCalibrationAccuracy),
                          ok: r.metrics.confidenceCalibrationAccuracy >= 0.70)
                metricRow("Food naming precision",
                          percent(r.metrics.foodNamingPrecision),
                          ok: r.metrics.foodNamingPrecision >= 0.60)
                metricRow("Portion error",
                          String(format: "%.2f", r.metrics.portionEstimationError),
                          ok: r.metrics.portionEstimationError <= 0.6)
            }
            .padding(14)
            .glassCard(radius: 16)
        }
    }

    private func tagsCard(_ r: RegressionRunner.Report) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Pass rate by edge case")
            VStack(spacing: 10) {
                ForEach(sortedTags(r.passRateByTag), id: \.0) { tag, rate in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(tag.rawValue.replacingOccurrences(of: "_", with: " "))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                            Text(percent(rate))
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(passColor(rate))
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Theme.line)
                                Capsule().fill(passColor(rate))
                                    .frame(width: geo.size.width * rate)
                            }
                        }
                        .frame(height: 5)
                    }
                }
            }
            .padding(14)
            .glassCard(radius: 16)
        }
    }

    private func driftCard(_ r: RegressionRunner.Report) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Drift flags")
            VStack(alignment: .leading, spacing: 8) {
                ForEach(r.drift) { flag in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: flag.severity == .failure ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(flag.severity == .failure ? Theme.bad : Theme.warn)
                        Text(flag.detail)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(14)
            .glassCard(radius: 16)
        }
    }

    private func samplesCard(_ r: RegressionRunner.Report) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Samples (\(r.samples.count))")
            VStack(spacing: 0) {
                ForEach(Array(r.samples.enumerated()), id: \.offset) { idx, s in
                    sampleRow(s)
                    if idx < r.samples.count - 1 {
                        Divider().overlay(Theme.line)
                    }
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 14)
            .glassCard(radius: 16)
        }
    }

    private func sampleRow(_ s: RegressionRunner.SampleResult) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Circle().fill(s.passed ? Theme.good : Theme.bad).frame(width: 7, height: 7)
                Text(s.label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text(s.kind.rawValue)
                    .font(.system(size: 9, weight: .semibold)).tracking(1.0)
                    .foregroundStyle(Theme.textTertiary)
            }
            HStack(spacing: 8) {
                if let a = s.actualScore {
                    chip("score", String(format: "%.1f", a))
                }
                if let c = s.actualConfidence {
                    chip("conf", "\(Int(c))%")
                }
                if let p = s.foodNamePrecision {
                    chip("precision", String(format: "%.2f", p))
                }
                if let pe = s.portionError {
                    chip("Δportion", String(format: "%.2f", pe))
                }
                if !s.deterministic {
                    chip("non-det", "!")
                }
            }
            if !s.notes.isEmpty {
                Text(s.notes.joined(separator: " · "))
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 10)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "ladybug")
                .font(.system(size: 28))
                .foregroundStyle(Theme.textTertiary)
            Text("No report yet.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    // MARK: - Bits

    private func metricRow(_ label: String, _ value: String, ok: Bool) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(ok ? Theme.good : Theme.warn)
        }
    }

    private func versionPill(_ label: String, _ v: String) -> some View {
        VStack(spacing: 1) {
            Text(label).font(.system(size: 9, weight: .semibold)).tracking(1.0)
                .foregroundStyle(Theme.textTertiary)
            Text(v).font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Capsule().fill(Theme.surface.opacity(0.5)))
        .overlay(Capsule().strokeBorder(Theme.line, lineWidth: 0.5))
    }

    private func chip(_ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 8, weight: .semibold)).tracking(0.9)
                .foregroundStyle(Theme.textTertiary)
            Text(value)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(Capsule().fill(Theme.surface.opacity(0.5)))
    }

    private func percent(_ v: Double) -> String {
        "\(Int((v * 100).rounded()))%"
    }

    private func passColor(_ v: Double) -> Color {
        v >= 0.75 ? Theme.good : (v >= 0.5 ? Theme.warn : Theme.bad)
    }

    private func sortedTags(_ dict: [GoldenDataset.EdgeCaseTag: Double]) -> [(GoldenDataset.EdgeCaseTag, Double)] {
        dict.map { ($0.key, $0.value) }
            .sorted { $0.1 < $1.1 }
    }
}
