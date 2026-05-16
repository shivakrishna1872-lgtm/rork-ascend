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
                    bodyCompCard(latest).blurFadeIn(delay: 0.16)
                    radarCard(latest).blurFadeIn(delay: 0.18)
                    strengthCard(latest).blurFadeIn(delay: 0.20)
                    archetypeCard(latest).blurFadeIn(delay: 0.22)
                    if scans.count >= 2 {
                        sparklineCard(scans).blurFadeIn(delay: 0.24)
                        trendCard(latest: latest, previous: scans[1]).blurFadeIn(delay: 0.26)
                    }
                    goalProjectionCard(latest).blurFadeIn(delay: 0.28)
                    if !latest.recommendations.isEmpty {
                        recommendationsCard(latest).blurFadeIn(delay: 0.30)
                    }
                    insightCard(latest).blurFadeIn(delay: 0.34)
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

    // MARK: - New: Lean / Fat mass composition

    private func bodyCompCard(_ rec: PhysiqueScanRecord) -> some View {
        let weight = max(40, user.weightKg) // kg
        let bf = max(3, min(45, rec.bodyFatPercent))
        let fatMass = weight * bf / 100
        let leanMass = weight - fatMass
        let leanPct = (leanMass / weight)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Mass Breakdown".uppercased())
                    .font(.system(size: 10, weight: .semibold)).tracking(2)
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
                Text(String(format: "%.1f kg total", weight))
                    .font(.aetherCaption).foregroundStyle(Theme.textTertiary)
            }
            GeometryReader { geo in
                HStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(LinearGradient(colors: [Theme.accentGlow, Theme.accent], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(20, geo.size.width * leanPct))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Theme.warn.opacity(0.55))
                }
            }
            .frame(height: 14)
            HStack(spacing: 14) {
                massPill(label: "LEAN", value: leanMass, color: Theme.accentGlow)
                massPill(label: "FAT", value: fatMass, color: Theme.warn)
                VStack(alignment: .leading, spacing: 3) {
                    Text("FFMI")
                        .font(.system(size: 9, weight: .semibold)).tracking(1.4)
                        .foregroundStyle(Theme.textTertiary)
                    let h = max(1.2, user.heightCm / 100)
                    let ffmi = leanMass / (h * h)
                    Text(String(format: "%.1f", ffmi))
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(18)
        .glassCard(radius: 20)
    }

    private func massPill(label: String, value: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(label)
                    .font(.system(size: 9, weight: .semibold)).tracking(1.4)
                    .foregroundStyle(Theme.textTertiary)
            }
            Text(String(format: "%.1f kg", value))
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - New: Radar chart of physique metrics

    private func radarCard(_ rec: PhysiqueScanRecord) -> some View {
        let metrics: [(String, Double)] = [
            ("SYM", rec.symmetryScore),
            ("MUS", rec.muscularityScore),
            ("LEAN", rec.conditioningScore),
            ("V-T", rec.vTaperScore),
            ("BAL", balanceScore(rec))
        ]
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Composition Radar".uppercased())
                    .font(.system(size: 10, weight: .semibold)).tracking(2)
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
                Text("5-axis")
                    .font(.aetherCaption).foregroundStyle(Theme.textTertiary)
            }
            RadarChartView(metrics: metrics)
                .frame(height: 200)
                .frame(maxWidth: .infinity)
        }
        .padding(18)
        .glassCard(radius: 20)
    }

    private func balanceScore(_ rec: PhysiqueScanRecord) -> Double {
        // Penalize spread between metrics — high balance = consistent across axes.
        let v = [rec.symmetryScore, rec.muscularityScore, rec.conditioningScore, rec.vTaperScore]
        let m = v.reduce(0, +) / Double(v.count)
        let std = sqrt(v.map { pow($0 - m, 2) }.reduce(0, +) / Double(v.count))
        return max(0, min(100, 100 - std * 2.2))
    }

    // MARK: - New: Strength projection

    private func strengthCard(_ rec: PhysiqueScanRecord) -> some View {
        // Rough strength estimate from lean mass + muscularity score.
        let bf = max(3, min(45, rec.bodyFatPercent))
        let weight = max(40, user.weightKg)
        let lean = weight * (1 - bf / 100)
        let mus = rec.muscularityScore / 100
        // multipliers calibrated to natural intermediate lifters
        let bench = lean * (0.85 + mus * 0.85)
        let squat = lean * (1.10 + mus * 1.05)
        let dead  = lean * (1.30 + mus * 1.20)
        let total = bench + squat + dead
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Strength Projection".uppercased())
                    .font(.system(size: 10, weight: .semibold)).tracking(2)
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
                Text(String(format: "Total ≈ %.0f kg", total))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.accentGlow)
            }
            HStack(spacing: 10) {
                liftEstimate("Bench", bench, icon: "figure.strengthtraining.functional")
                liftEstimate("Squat", squat, icon: "figure.cross.training")
                liftEstimate("Dead",  dead,  icon: "figure.strengthtraining.traditional")
            }
            Text("Estimated potential 1RM based on lean mass and muscularity score. Drug-free intermediate range.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: 20)
    }

    private func liftEstimate(_ label: String, _ kg: Double, icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.accentGlow)
            Text(String(format: "%.0f", kg))
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
            Text("\(label.uppercased()) · KG")
                .font(.system(size: 8, weight: .semibold)).tracking(1.2)
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.25)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.line, lineWidth: 0.6))
    }

    // MARK: - New: Sparkline of physique score across scans

    private func sparklineCard(_ scans: [PhysiqueScanRecord]) -> some View {
        // scans are newest-first; chart oldest → newest
        let series = scans.prefix(12).reversed().map { $0.physiqueScore }
        let arr = Array(series)
        let mn = arr.min() ?? 0
        let mx = arr.max() ?? 100
        let range = max(1, mx - mn)
        let latest = arr.last ?? 0
        let first  = arr.first ?? latest
        let delta = latest - first
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Evolution".uppercased())
                    .font(.system(size: 10, weight: .semibold)).tracking(2)
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                    Text(String(format: "%+.1f over %d scans", delta, arr.count))
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(delta >= 0 ? Theme.good : Theme.bad)
            }
            GeometryReader { geo in
                let stepX = arr.count > 1 ? geo.size.width / CGFloat(arr.count - 1) : geo.size.width
                ZStack {
                    // Filled area
                    Path { p in
                        guard !arr.isEmpty else { return }
                        p.move(to: CGPoint(x: 0, y: geo.size.height))
                        for (i, v) in arr.enumerated() {
                            let x = CGFloat(i) * stepX
                            let y = geo.size.height - CGFloat((v - mn) / range) * geo.size.height
                            p.addLine(to: CGPoint(x: x, y: y))
                        }
                        p.addLine(to: CGPoint(x: CGFloat(arr.count - 1) * stepX, y: geo.size.height))
                        p.closeSubpath()
                    }
                    .fill(LinearGradient(colors: [Theme.accentGlow.opacity(0.35), Theme.accentGlow.opacity(0.0)], startPoint: .top, endPoint: .bottom))
                    // Line
                    Path { p in
                        for (i, v) in arr.enumerated() {
                            let x = CGFloat(i) * stepX
                            let y = geo.size.height - CGFloat((v - mn) / range) * geo.size.height
                            if i == 0 { p.move(to: CGPoint(x: x, y: y)) }
                            else { p.addLine(to: CGPoint(x: x, y: y)) }
                        }
                    }
                    .stroke(Theme.accentGlow, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    // End dot
                    if let last = arr.last {
                        let x = CGFloat(arr.count - 1) * stepX
                        let y = geo.size.height - CGFloat((last - mn) / range) * geo.size.height
                        Circle().fill(Theme.accentGlow).frame(width: 8, height: 8)
                            .position(x: x, y: y)
                            .shadow(color: Theme.accentGlow.opacity(0.6), radius: 6)
                    }
                }
            }
            .frame(height: 70)
            HStack {
                Text("min \(Int(mn))").font(.system(size: 9)).foregroundStyle(Theme.textTertiary)
                Spacer()
                Text("now \(Int(latest))")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.accentGlow)
                Spacer()
                Text("max \(Int(mx))").font(.system(size: 9)).foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(18)
        .glassCard(radius: 20)
    }

    // MARK: - New: Goal projection

    private func goalProjectionCard(_ rec: PhysiqueScanRecord) -> some View {
        let bf = rec.bodyFatPercent
        // Define next milestone toward leaner / more muscular.
        let targetBF: Double = bf > 20 ? 18 : (bf > 15 ? 12 : (bf > 10 ? 8 : 6))
        let weight = max(40, user.weightKg)
        let fatToLose = max(0, weight * (bf - targetBF) / 100)
        // ~0.5 kg fat loss per week sustainable rate
        let weeks = max(2, Int((fatToLose / 0.5).rounded()))
        let targetScore = min(100, rec.physiqueScore + 6)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Next Milestone".uppercased())
                    .font(.system(size: 10, weight: .semibold)).tracking(2)
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
                Text("\(weeks) weeks")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.accentGlow)
            }
            HStack(spacing: 14) {
                projectionTile(top: String(format: "%.1f%%", targetBF), bottom: "TARGET BF", icon: "drop")
                projectionTile(top: String(format: "%.1fkg", fatToLose), bottom: "FAT TO LOSE", icon: "flame")
                projectionTile(top: "\(Int(targetScore))", bottom: "TARGET SCORE", icon: "target")
            }
            GeometryReader { geo in
                let progress = min(1.0, max(0.05, rec.physiqueScore / targetScore))
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.line)
                    Capsule()
                        .fill(LinearGradient(colors: [Theme.accent, Theme.accentGlow], startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * progress)
                }
            }
            .frame(height: 6)
        }
        .padding(18)
        .glassCard(radius: 20)
    }

    private func projectionTile(top: String, bottom: String, icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.accentGlow)
            Text(top)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
            Text(bottom)
                .font(.system(size: 8, weight: .semibold)).tracking(1.2)
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.25)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.line, lineWidth: 0.6))
    }

    // MARK: - Inline radar chart

    private struct RadarChartView: View {
        let metrics: [(String, Double)]

        var body: some View {
            GeometryReader { geo in
                let size = min(geo.size.width, geo.size.height)
                let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                let radius = size / 2 - 18
                ZStack {
                    gridLayer(center: center, radius: radius)
                    spokesLayer(center: center, radius: radius)
                    polygonFill(center: center, radius: radius)
                    polygonStroke(center: center, radius: radius)
                    dotsLayer(center: center, radius: radius)
                    labelsLayer(center: center, radius: radius)
                }
            }
        }

        private func point(at i: Int, center: CGPoint, radius: CGFloat, scale: CGFloat) -> CGPoint {
            let a = angle(for: i)
            return CGPoint(x: center.x + CGFloat(cos(a)) * radius * scale,
                           y: center.y + CGFloat(sin(a)) * radius * scale)
        }

        @ViewBuilder
        private func gridLayer(center: CGPoint, radius: CGFloat) -> some View {
            let count = metrics.count
            ForEach([0.25, 0.5, 0.75, 1.0], id: \.self) { f in
                Path { p in
                    for i in 0..<count {
                        let pt = point(at: i, center: center, radius: radius, scale: CGFloat(f))
                        if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                    }
                    p.closeSubpath()
                }
                .stroke(Theme.line, lineWidth: 0.5)
            }
        }

        @ViewBuilder
        private func spokesLayer(center: CGPoint, radius: CGFloat) -> some View {
            let count = metrics.count
            ForEach(0..<count, id: \.self) { i in
                Path { p in
                    p.move(to: center)
                    p.addLine(to: point(at: i, center: center, radius: radius, scale: 1))
                }
                .stroke(Theme.line.opacity(0.5), lineWidth: 0.5)
            }
        }

        private func polygonPath(center: CGPoint, radius: CGFloat) -> Path {
            Path { p in
                let count = metrics.count
                for i in 0..<count {
                    let v = CGFloat(max(0, min(100, metrics[i].1)) / 100)
                    let pt = point(at: i, center: center, radius: radius, scale: v)
                    if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                }
                p.closeSubpath()
            }
        }

        private func polygonFill(center: CGPoint, radius: CGFloat) -> some View {
            polygonPath(center: center, radius: radius)
                .fill(Theme.accentGlow.opacity(0.25))
        }

        private func polygonStroke(center: CGPoint, radius: CGFloat) -> some View {
            polygonPath(center: center, radius: radius)
                .stroke(Theme.accentGlow, lineWidth: 1.5)
        }

        @ViewBuilder
        private func dotsLayer(center: CGPoint, radius: CGFloat) -> some View {
            let count = metrics.count
            ForEach(0..<count, id: \.self) { i in
                let v = CGFloat(max(0, min(100, metrics[i].1)) / 100)
                let pt = point(at: i, center: center, radius: radius, scale: v)
                Circle().fill(Theme.accentGlow)
                    .frame(width: 6, height: 6)
                    .position(x: pt.x, y: pt.y)
            }
        }

        @ViewBuilder
        private func labelsLayer(center: CGPoint, radius: CGFloat) -> some View {
            let count = metrics.count
            ForEach(0..<count, id: \.self) { i in
                let pt = point(at: i, center: center, radius: radius + 14, scale: 1)
                Text(metrics[i].0)
                    .font(.system(size: 9, weight: .bold)).tracking(1.2)
                    .foregroundStyle(Theme.textSecondary)
                    .position(x: pt.x, y: pt.y)
            }
        }

        private func angle(for i: Int) -> Double {
            -.pi / 2 + (2 * .pi / Double(metrics.count)) * Double(i)
        }
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
