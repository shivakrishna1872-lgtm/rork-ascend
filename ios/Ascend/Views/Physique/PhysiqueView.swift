import SwiftUI
import SwiftData

struct PhysiqueView: View {
    let user: UserProfile
    @Environment(\.modelContext) private var ctx
    @Environment(AppState.self) private var app
    @Query(sort: \PhysiqueScanRecord.date, order: .reverse) private var scans: [PhysiqueScanRecord]

    @State private var showScanFlow = false
    @State private var selected: PhysiqueScanRecord?

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                header.blurFadeIn(delay: 0.0)

                if let latest = scans.first {
                    latestCard(latest).blurFadeIn(delay: 0.1)
                    bodyFatCard(latest).blurFadeIn(delay: 0.14)
                    archetypeCard(latest).blurFadeIn(delay: 0.18)
                    if scans.count >= 2 {
                        trendCard(latest: latest, previous: scans[1]).blurFadeIn(delay: 0.22)
                    }
                    if !latest.recommendations.isEmpty {
                        recommendationsCard(latest).blurFadeIn(delay: 0.26)
                    }
                    insightCard(latest).blurFadeIn(delay: 0.30)
                } else {
                    emptyCard.blurFadeIn(delay: 0.1)
                }

                SectionHeader(title: "Timeline", trailing: scans.count > 0 ? "\(scans.count) scans" : nil)
                    .padding(.horizontal, 4)

                if scans.count <= 1 {
                    Text("Your evolution will appear here.")
                        .font(.aetherBody).foregroundStyle(Theme.textTertiary)
                        .frame(maxWidth: .infinity).padding(.vertical, 30)
                        .glassCard(radius: 18)
                } else {
                    timeline.blurFadeIn(delay: 0.16)
                }

            }
            .padding(.horizontal, 20).padding(.top, 12)
        }
        .scrollIndicators(.hidden)
        .tabBarBottomInset()
        .sheet(isPresented: $showScanFlow) {
            PhysiqueScanFlow(user: user)
        }
        .sheet(item: $selected) { rec in
            PhysiqueResultsView(record: rec, isHistory: true)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Physique Intelligence".uppercased())
                .font(.system(size: 11, weight: .semibold)).tracking(2)
                .foregroundStyle(Theme.textTertiary)
            Text("Scan, analyze, evolve.")
                .font(.aetherTitle).foregroundStyle(Theme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 4)
    }

    private var emptyCard: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle().fill(Theme.accent.opacity(0.10)).frame(width: 110, height: 110)
                    .ambientFloat(amplitude: 4, duration: 3.5)
                Image(systemName: "figure.arms.open")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(Theme.accentGlow)
            }
            VStack(spacing: 4) {
                Text("Begin your first scan")
                    .font(.aetherHeadline)
                Text("Three angles. Cinematic analysis. Two minutes.")
                    .font(.aetherBody).foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            PrimaryButton(title: "Start Scan", icon: "viewfinder") {
                showScanFlow = true
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .glassCard(radius: 22)
    }

    private func latestCard(_ rec: PhysiqueScanRecord) -> some View {
        Button {
            Haptics.tap(); selected = rec
        } label: {
            VStack(spacing: 18) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(rec.archetypeRaw.uppercased())
                            .font(.system(size: 10, weight: .semibold)).tracking(2)
                            .foregroundStyle(Theme.accentGlow)
                        Text("Physique Score")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text(rec.date.formatted(date: .abbreviated, time: .omitted))
                            .font(.aetherCaption).foregroundStyle(Theme.textTertiary)
                    }
                    Spacer()
                    RadialScore(score: rec.physiqueScore, label: "Score", size: 110)
                }

                HStack(spacing: 10) {
                    miniMetric("Symmetry", rec.symmetryScore)
                    miniMetric("Muscle", rec.muscularityScore)
                    miniMetric("Lean", rec.conditioningScore)
                    miniMetric("V-Taper", rec.vTaperScore)
                }

                let calibration = PhysiqueSmoothing.calibration(from: scans)
                if !calibration.isEmpty {
                    HStack {
                        CalibrationBadge(calibration: calibration)
                        Spacer()
                        Text("baseline".uppercased())
                            .font(.system(size: 9, weight: .semibold)).tracking(1.4)
                            .foregroundStyle(Theme.textTertiary)
                    }
                }

                PrimaryButton(title: "New Scan", icon: "plus.viewfinder") {
                    showScanFlow = true
                }
            }
            .padding(20)
            .glassCard(radius: 24)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Extra data cards

    private func bodyFatCard(_ rec: PhysiqueScanRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Body Composition".uppercased())
                        .font(.system(size: 10, weight: .semibold)).tracking(2)
                        .foregroundStyle(Theme.textTertiary)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(String(format: "%.1f", rec.bodyFatPercent))
                            .font(.system(size: 38, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.textPrimary)
                        Text("% body fat")
                            .font(.aetherBody).foregroundStyle(Theme.textSecondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text("CONFIDENCE")
                        .font(.system(size: 9, weight: .semibold)).tracking(1.4)
                        .foregroundStyle(Theme.textTertiary)
                    Text("\(Int(rec.bodyFatConfidence))%")
                        .font(.aetherMono).foregroundStyle(Theme.accentGlow)
                }
            }
            // BF scale bar (5–40%)
            GeometryReader { geo in
                let pct = min(1, max(0, (rec.bodyFatPercent - 5) / 35))
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.line)
                    Capsule()
                        .fill(LinearGradient(
                            colors: [Theme.good, Theme.accentGlow, Theme.warn, Theme.bad],
                            startPoint: .leading, endPoint: .trailing
                        ))
                        .frame(width: geo.size.width)
                        .mask(Rectangle().frame(width: geo.size.width * pct, alignment: .leading)
                              .frame(maxWidth: .infinity, alignment: .leading))
                    Circle().fill(.white)
                        .frame(width: 10, height: 10)
                        .shadow(color: .black.opacity(0.4), radius: 3)
                        .offset(x: geo.size.width * pct - 5)
                }
            }.frame(height: 8)
            HStack {
                Text("5%").font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.textTertiary)
                Spacer()
                Text(bodyFatCategory(rec.bodyFatPercent))
                    .font(.system(size: 10, weight: .bold)).tracking(1.2)
                    .foregroundStyle(Theme.accentGlow)
                Spacer()
                Text("40%").font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(18)
        .glassCard(radius: 20)
    }

    private func bodyFatCategory(_ bf: Double) -> String {
        switch bf {
        case ..<8:  return "COMPETITION LEAN"
        case 8..<12: return "VISIBLY LEAN"
        case 12..<16: return "ATHLETIC"
        case 16..<20: return "FIT"
        case 20..<25: return "AVERAGE"
        default:     return "ABOVE AVERAGE"
        }
    }

    private func archetypeCard(_ rec: PhysiqueScanRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Theme.accent.opacity(0.14))
                        .frame(width: 50, height: 50)
                    Image(systemName: archetypeIcon(rec.archetypeRaw))
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Theme.accentGlow)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("ARCHETYPE")
                        .font(.system(size: 9, weight: .semibold)).tracking(1.5)
                        .foregroundStyle(Theme.textTertiary)
                    Text(rec.archetypeRaw)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                }
                Spacer()
            }
            Text(archetypeBlurb(rec.archetypeRaw))
                .font(.aetherBody)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: 20)
    }

    private func archetypeIcon(_ raw: String) -> String {
        switch raw.lowercased() {
        case let s where s.contains("v-taper"): return "triangle"
        case let s where s.contains("power"): return "bolt.fill"
        case let s where s.contains("swimmer"): return "figure.pool.swim"
        case let s where s.contains("lean"): return "figure.run"
        case let s where s.contains("aesthetic"): return "sparkles"
        default: return "figure.strengthtraining.traditional"
        }
    }

    private func archetypeBlurb(_ raw: String) -> String {
        switch raw.lowercased() {
        case let s where s.contains("v-taper"): return "Wide shoulders tapering into a tight waist — emphasize lateral delts and core to preserve the taper."
        case let s where s.contains("power"): return "Dense, strength-forward frame. Lean into compound lifts and prioritize conditioning to reveal definition."
        case let s where s.contains("swimmer"): return "Long, lean lines with developed lats. Maintain mobility and progressive overload to add quality mass."
        case let s where s.contains("lean athletic"): return "Conditioned and balanced. You're well positioned to chase aesthetic or strength goals — pick a direction."
        case let s where s.contains("aesthetic"): return "Proportional and visually balanced. Focus on conditioning and posture to push toward elite territory."
        default: return "A balanced foundation — small targeted improvements in symmetry and conditioning will pay off fast."
        }
    }

    private func trendCard(latest: PhysiqueScanRecord, previous: PhysiqueScanRecord) -> some View {
        let deltas: [(String, Double)] = [
            ("Physique", latest.physiqueScore - previous.physiqueScore),
            ("Symmetry", latest.symmetryScore - previous.symmetryScore),
            ("Muscle", latest.muscularityScore - previous.muscularityScore),
            ("Lean", latest.conditioningScore - previous.conditioningScore),
            ("V-Taper", latest.vTaperScore - previous.vTaperScore)
        ]
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("vs Last Scan".uppercased())
                    .font(.system(size: 10, weight: .semibold)).tracking(2)
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
                Text(daysAgo(previous.date))
                    .font(.aetherCaption).foregroundStyle(Theme.textTertiary)
            }
            HStack(spacing: 8) {
                ForEach(Array(deltas.enumerated()), id: \.offset) { _, d in
                    deltaPill(label: d.0, delta: d.1)
                }
            }
        }
        .padding(18)
        .glassCard(radius: 20)
    }

    private func deltaPill(label: String, delta: Double) -> some View {
        let up = delta >= 0
        let color: Color = abs(delta) < 0.5 ? Theme.textSecondary : (up ? Theme.good : Theme.bad)
        return VStack(spacing: 4) {
            HStack(spacing: 2) {
                Image(systemName: abs(delta) < 0.5 ? "minus" : (up ? "arrow.up.right" : "arrow.down.right"))
                    .font(.system(size: 9, weight: .bold))
                Text(String(format: "%@%.1f", up && delta >= 0.5 ? "+" : "", delta))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(color)
            Text(label.uppercased())
                .font(.system(size: 8, weight: .semibold)).tracking(1.1)
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.25)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.line, lineWidth: 0.5))
    }

    private func daysAgo(_ date: Date) -> String {
        let days = Calendar.current.dateComponents([.day], from: date, to: .now).day ?? 0
        if days <= 0 { return "Today" }
        if days == 1 { return "Yesterday" }
        return "\(days) days ago"
    }

    private func recommendationsCard(_ rec: PhysiqueScanRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Coaching".uppercased())
                .font(.system(size: 10, weight: .semibold)).tracking(2)
                .foregroundStyle(Theme.textTertiary)
            ForEach(Array(rec.recommendations.enumerated()), id: \.offset) { idx, r in
                HStack(alignment: .top, spacing: 12) {
                    Text("\(idx + 1)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.bg)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Theme.accentGlow))
                    Text(r)
                        .font(.aetherBody)
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: 20)
    }

    private func insightCard(_ rec: PhysiqueScanRecord) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.accentGlow)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text("AI INSIGHT")
                    .font(.system(size: 9, weight: .semibold)).tracking(1.5)
                    .foregroundStyle(Theme.textTertiary)
                Text(rec.insight)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: 20)
    }

    private func miniMetric(_ label: String, _ value: Double) -> some View {
        VStack(spacing: 2) {
            Text("\(Int(value))")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
            Text(label.uppercased())
                .font(.system(size: 8, weight: .semibold)).tracking(1.4)
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.25)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.line, lineWidth: 0.6))
    }

    private var timeline: some View {
        VStack(spacing: 10) {
            ForEach(scans) { rec in
                Button {
                    Haptics.tap(); selected = rec
                } label: {
                    HStack(spacing: 14) {
                        timelineThumb(rec.frontImageData)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(rec.date.formatted(date: .abbreviated, time: .omitted))
                                .font(.aetherCaption).foregroundStyle(Theme.textTertiary)
                            Text("\(Int(rec.physiqueScore)) · \(rec.archetypeRaw)")
                                .font(.system(size: 15, weight: .semibold))
                            HStack(spacing: 8) {
                                Label("\(Int(rec.symmetryScore))", systemImage: "arrow.left.and.right")
                                Label("\(Int(rec.muscularityScore))", systemImage: "figure.strengthtraining.traditional")
                                Label(String(format: "%.1f%%", rec.bodyFatPercent), systemImage: "drop")
                            }
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .padding(12)
                    .glassCard(radius: 16)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func timelineThumb(_ data: Data?) -> some View {
        if let data, let img = UIImage(data: data) {
            Image(uiImage: img)
                .resizable().aspectRatio(contentMode: .fill)
                .frame(width: 56, height: 72)
                .clipShape(.rect(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.line, lineWidth: 0.5))
        } else {
            RoundedRectangle(cornerRadius: 10)
                .fill(Theme.surface)
                .frame(width: 56, height: 72)
                .overlay {
                    Image(systemName: "figure.stand").foregroundStyle(Theme.textTertiary)
                }
        }
    }
}
