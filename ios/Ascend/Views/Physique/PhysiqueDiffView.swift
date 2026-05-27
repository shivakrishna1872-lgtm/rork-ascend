import SwiftUI
import SwiftData

/// Side-by-side comparison of two physique scans. Aligned silhouettes (front
/// images) + delta chips for every numeric metric. Read-only — opened from
/// the Physique hub when 2+ scans exist.
struct PhysiqueDiffView: View {
    let scans: [PhysiqueScanRecord]
    @Environment(\.dismiss) private var dismiss

    /// Defaults: previous → latest. User can swap either side.
    @State private var leftIdx: Int
    @State private var rightIdx: Int

    init(scans: [PhysiqueScanRecord]) {
        self.scans = scans
        let initialLeft = min(1, max(0, scans.count - 1))
        _leftIdx = State(initialValue: initialLeft)
        _rightIdx = State(initialValue: 0)
    }

    private var leftScan: PhysiqueScanRecord? {
        scans.indices.contains(leftIdx) ? scans[leftIdx] : nil
    }
    private var rightScan: PhysiqueScanRecord? {
        scans.indices.contains(rightIdx) ? scans[rightIdx] : nil
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground().ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 18) {
                        photoRow
                        if let l = leftScan, let r = rightScan {
                            scoreCard(left: l, right: r)
                            deltasCard(left: l, right: r)
                            bodyCompCard(left: l, right: r)
                        } else {
                            ContentUnavailableView("Need two scans to compare",
                                                   systemImage: "rectangle.on.rectangle")
                                .padding(.top, 60)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Compare")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Theme.accentGlow)
                }
            }
        }
    }

    // MARK: - Photo row with picker chips

    private var photoRow: some View {
        HStack(alignment: .top, spacing: 12) {
            photoPane(scan: leftScan, label: "BEFORE", isLeft: true)
            photoPane(scan: rightScan, label: "AFTER", isLeft: false)
        }
    }

    private func photoPane(scan: PhysiqueScanRecord?, label: String, isLeft: Bool) -> some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.black.opacity(0.55))
                    .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Theme.lineStrong, lineWidth: 0.6))
                if let data = scan?.frontImageData, let img = UIImage(data: data) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .clipShape(.rect(cornerRadius: 18))
                        .allowsHitTesting(false)
                } else {
                    Image(systemName: "figure.stand")
                        .font(.system(size: 56, weight: .thin))
                        .foregroundStyle(Theme.accent.opacity(0.4))
                }
                VStack {
                    HStack {
                        Text(label)
                            .font(.system(size: 9, weight: .heavy)).tracking(1.6)
                            .foregroundStyle(Theme.textPrimary)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Capsule().fill(Color.black.opacity(0.55)))
                        Spacer()
                    }
                    Spacer()
                    if let s = scan {
                        HStack {
                            Text(s.date.formatted(date: .abbreviated, time: .omitted))
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Capsule().fill(Color.black.opacity(0.55)))
                            Spacer()
                            Text("\(Int(s.physiqueScore))")
                                .font(.system(size: 14, weight: .heavy, design: .rounded))
                                .foregroundStyle(Theme.accentGlow)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Capsule().fill(Color.black.opacity(0.55)))
                        }
                    }
                }
                .padding(10)
            }
            .aspectRatio(0.72, contentMode: .fit)

            Menu {
                ForEach(Array(scans.enumerated()), id: \.offset) { idx, s in
                    Button {
                        if isLeft { leftIdx = idx } else { rightIdx = idx }
                    } label: {
                        Label(s.date.formatted(date: .abbreviated, time: .omitted),
                              systemImage: idx == (isLeft ? leftIdx : rightIdx) ? "checkmark" : "")
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .bold))
                    Text("Change")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(Theme.surface.opacity(0.6)))
                .overlay(Capsule().strokeBorder(Theme.line, lineWidth: 0.5))
            }
        }
    }

    // MARK: - Score card

    private func scoreCard(left: PhysiqueScanRecord, right: PhysiqueScanRecord) -> some View {
        let delta = right.physiqueScore - left.physiqueScore
        let days = Calendar.current.dateComponents([.day], from: left.date, to: right.date).day ?? 0
        return HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("PHYSIQUE SCORE")
                    .font(.system(size: 10, weight: .semibold)).tracking(1.4)
                    .foregroundStyle(Theme.textTertiary)
                Text(String(format: "%+.1f", delta))
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundStyle(delta >= 0 ? Theme.good : Theme.bad)
                Text("\(Int(left.physiqueScore))  →  \(Int(right.physiqueScore))")
                    .font(.aetherCaption).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("SPAN")
                    .font(.system(size: 9, weight: .semibold)).tracking(1.4)
                    .foregroundStyle(Theme.textTertiary)
                Text(days == 0 ? "Same day" : "\(abs(days)) day\(abs(days) == 1 ? "" : "s")")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
            }
        }
        .padding(18)
        .glassCard(radius: 20)
    }

    // MARK: - Deltas grid

    private func deltasCard(left: PhysiqueScanRecord, right: PhysiqueScanRecord) -> some View {
        let rows: [(String, Double, Double)] = [
            ("Symmetry", left.symmetryScore, right.symmetryScore),
            ("Muscle",   left.muscularityScore, right.muscularityScore),
            ("Lean",     left.conditioningScore, right.conditioningScore),
            ("V-Taper",  left.vTaperScore, right.vTaperScore),
            ("Body Fat", left.bodyFatPercent, right.bodyFatPercent)
        ]
        return VStack(alignment: .leading, spacing: 12) {
            Text("METRIC DELTAS")
                .font(.system(size: 10, weight: .semibold)).tracking(1.6)
                .foregroundStyle(Theme.textTertiary)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                let lowerIsBetter = row.0 == "Body Fat"
                let delta = row.2 - row.1
                let improvement = lowerIsBetter ? -delta : delta
                let color: Color = abs(delta) < 0.3 ? Theme.textSecondary
                    : (improvement > 0 ? Theme.good : Theme.bad)
                HStack(spacing: 10) {
                    Text(row.0)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(width: 88, alignment: .leading)
                    GeometryReader { geo in
                        let span = max(8, max(row.1, row.2)) + 6
                        let leftW = CGFloat(row.1 / span) * geo.size.width
                        let rightW = CGFloat(row.2 / span) * geo.size.width
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.line).frame(height: 4)
                            Capsule().fill(Theme.textSecondary.opacity(0.55))
                                .frame(width: max(4, leftW), height: 4)
                            Capsule().fill(Theme.accentGlow)
                                .frame(width: max(4, rightW), height: 4)
                                .offset(y: 8)
                        }
                    }
                    .frame(height: 16)
                    Text(String(format: row.0 == "Body Fat" ? "%+.1f%%" : "%+.1f", delta))
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(color)
                        .frame(width: 56, alignment: .trailing)
                }
            }
            HStack(spacing: 12) {
                legendDot(Theme.textSecondary.opacity(0.55), "Before")
                legendDot(Theme.accentGlow, "After")
                Spacer()
            }
            .padding(.top, 4)
        }
        .padding(18)
        .glassCard(radius: 20)
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 5) {
            Capsule().fill(color).frame(width: 14, height: 3)
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold)).tracking(1.2)
                .foregroundStyle(Theme.textTertiary)
        }
    }

    // MARK: - Lean/Fat mass shift

    private func bodyCompCard(left: PhysiqueScanRecord, right: PhysiqueScanRecord) -> some View {
        // Lean/fat math uses an assumed common body weight (latest) — this
        // card is illustrative only when scans were taken at different weights.
        VStack(alignment: .leading, spacing: 10) {
            Text("BODY FAT")
                .font(.system(size: 10, weight: .semibold)).tracking(1.6)
                .foregroundStyle(Theme.textTertiary)
            HStack(spacing: 18) {
                VStack(spacing: 2) {
                    Text(String(format: "%.1f%%", left.bodyFatPercent))
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                    Text("BEFORE")
                        .font(.system(size: 9, weight: .semibold)).tracking(1.2)
                        .foregroundStyle(Theme.textTertiary)
                }
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.textTertiary)
                VStack(spacing: 2) {
                    Text(String(format: "%.1f%%", right.bodyFatPercent))
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.accentGlow)
                    Text("AFTER")
                        .font(.system(size: 9, weight: .semibold)).tracking(1.2)
                        .foregroundStyle(Theme.textTertiary)
                }
                Spacer()
                let delta = right.bodyFatPercent - left.bodyFatPercent
                VStack(alignment: .trailing, spacing: 2) {
                    Text(String(format: "%+.1f%%", delta))
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .foregroundStyle(delta <= 0 ? Theme.good : Theme.bad)
                    Text("CHANGE")
                        .font(.system(size: 9, weight: .semibold)).tracking(1.2)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: 20)
    }
}
