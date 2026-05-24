import SwiftUI

struct PhysiqueResultsView: View {
    let record: PhysiqueScanRecord
    let isHistory: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var revealStep: Int = 0
    @State private var showDebug: Bool = false

    var body: some View {
        ZStack {
            AmbientBackground().ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    HStack {
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Theme.textPrimary)
                                .frame(width: 36, height: 36)
                                .glassCard(radius: 12)
                        }
                        Spacer()
                        Text(record.date.formatted(date: .abbreviated, time: .omitted))
                            .font(.aetherCaption).foregroundStyle(Theme.textTertiary)
                            .onLongPressGesture(minimumDuration: 0.6) {
                                Haptics.medium()
                                showDebug = true
                            }
                        Spacer()
                        Color.clear.frame(width: 36, height: 36)
                    }

                    if revealStep >= 1 {
                        VStack(spacing: 6) {
                            Text(record.archetypeRaw.uppercased())
                                .font(.system(size: 11, weight: .semibold)).tracking(3)
                                .foregroundStyle(Theme.accentGlow)
                            Text("Your Physique")
                                .font(.aetherTitle).foregroundStyle(Theme.textPrimary)
                        }
                        .transition(.opacity.combined(with: .blurReplace))
                    }

                    if revealStep >= 2 {
                        ZStack {
                            RadialScore(score: record.physiqueScore, label: "Physique", size: 240, color: Theme.accentGlow)
                        }
                        .padding(.vertical, 8)
                        .transition(.scale.combined(with: .opacity))
                    }

                    if revealStep >= 4 {
                        metricsGrid
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }

                    if revealStep >= 5 {
                        bodyFatCard
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }

                    if revealStep >= 5, !record.confidenceReasons.isEmpty || record.isUncertaintyEvent {
                        confidenceReasonsCard
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }

                    if revealStep >= 6 {
                        insightCard
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }

                    if revealStep >= 7 {
                        recommendationsCard
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }

                    Color.clear.frame(height: 60)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
        }
        .scrollIndicators(.hidden)
        .sheet(isPresented: $showDebug) {
            ScanDebugView(record: record)
        }
        .onAppear {
            if isHistory {
                revealStep = 7
            } else {
                runReveal()
            }
        }
    }

    private func runReveal() {
        let delays: [Double] = [0.05, 0.20, 0.40, 0.60, 0.80, 1.00, 1.20]
        for (i, d) in delays.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + d) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) {
                    revealStep = i + 1
                }
                if i == 0 || i == 2 { Haptics.soft() }
                if i == 1 { Haptics.medium() }
                if i == 6 { Haptics.success() }
            }
        }
    }

    @ViewBuilder
    private func anglePhoto(_ data: Data?, _ label: String) -> some View {
        VStack(spacing: 6) {
            Color(.secondarySystemBackground).opacity(0.001)
                .frame(height: 130)
                .overlay {
                    if let data, let img = UIImage(data: data) {
                        Image(uiImage: img).resizable().aspectRatio(contentMode: .fill).allowsHitTesting(false)
                    } else {
                        Image(systemName: "figure.stand").font(.system(size: 36)).foregroundStyle(Theme.textTertiary)
                    }
                }
                .clipShape(.rect(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.line, lineWidth: 0.5))
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold)).tracking(1.4)
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private var metricsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            metricCard("Symmetry", record.symmetryScore, "arrow.left.and.right.righttriangle.left.righttriangle.right")
            metricCard("Muscularity", record.muscularityScore, "figure.strengthtraining.traditional")
            metricCard("Conditioning", record.conditioningScore, "flame.fill")
            metricCard("V-Taper", record.vTaperScore, "triangle.fill")
        }
    }

    private func metricCard(_ label: String, _ value: Double, _ icon: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: icon).font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.accentGlow)
                    Text(label.uppercased())
                        .font(.system(size: 9, weight: .semibold)).tracking(1.4)
                        .foregroundStyle(Theme.textTertiary)
                }
                CountingNumber(value: value, font: .system(size: 28, weight: .semibold, design: .rounded))
            }
            Spacer()
            ThinRing(progress: value / 100, color: Theme.accentGlow, lineWidth: 5)
                .frame(width: 44, height: 44)
        }
        .padding(14)
        .glassCard(radius: 16)
    }

    private var bodyFatCard: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Body Fat Estimate".uppercased())
                    .font(.system(size: 10, weight: .semibold)).tracking(2)
                    .foregroundStyle(Theme.textTertiary)
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    CountingNumber(value: record.bodyFatPercent,
                                   format: { String(format: "%.1f", $0) },
                                   font: .system(size: 38, weight: .semibold, design: .rounded))
                    Text("%").font(.aetherHeadline).foregroundStyle(Theme.textSecondary)
                }
                HStack(spacing: 4) {
                    Circle().fill(confidenceColor).frame(width: 6, height: 6)
                    Text("\(Int(record.bodyFatConfidence))% confidence")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer()
            // Confidence ring
            ZStack {
                ThinRing(progress: record.bodyFatConfidence / 100, color: confidenceColor, lineWidth: 6)
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(confidenceColor)
            }
            .frame(width: 56, height: 56)
        }
        .padding(16)
        .glassCard(radius: 20)
    }

    private var confidenceReasonsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: record.isUncertaintyEvent ? "exclamationmark.triangle.fill" : "info.circle.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(record.isUncertaintyEvent ? Theme.warn : Theme.accentGlow)
                Text(record.isUncertaintyEvent ? "Uncertainty Event".uppercased() : "Why this confidence".uppercased())
                    .font(.system(size: 10, weight: .semibold)).tracking(2)
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
                if record.partialityRaw != "full" {
                    Text(record.partialityRaw.uppercased())
                        .font(.system(size: 9, weight: .bold)).tracking(1.2)
                        .foregroundStyle(Theme.warn)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(Theme.warn.opacity(0.15)))
                        .overlay(Capsule().strokeBorder(Theme.warn.opacity(0.5), lineWidth: 0.5))
                }
            }
            ForEach(record.confidenceReasons, id: \.self) { reason in
                HStack(alignment: .top, spacing: 8) {
                    Circle().fill(Theme.warn.opacity(0.7)).frame(width: 4, height: 4)
                        .padding(.top, 7)
                    Text(reason)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
            if record.confidenceReasons.isEmpty && record.isUncertaintyEvent {
                Text("Cross-check between PSL and Physique disagreed — confidence reduced.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: 16)
    }

    private var confidenceColor: Color {
        if record.bodyFatConfidence >= 75 { return Theme.good }
        if record.bodyFatConfidence >= 50 { return Theme.warn }
        return Theme.bad
    }

    private var insightCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "sparkles").font(.system(size: 16, weight: .bold))
                .foregroundStyle(Theme.accentGlow)
                .ambientFloat(amplitude: 2, duration: 2.6)
            VStack(alignment: .leading, spacing: 6) {
                Text("Insight".uppercased())
                    .font(.system(size: 10, weight: .semibold)).tracking(2)
                    .foregroundStyle(Theme.textTertiary)
                Text(record.insight)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .glassCard(radius: 20)
    }

    private var recommendationsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Coaching".uppercased())
                .font(.system(size: 10, weight: .semibold)).tracking(2)
                .foregroundStyle(Theme.textTertiary)
            ForEach(Array(record.recommendations.enumerated()), id: \.offset) { idx, rec in
                HStack(alignment: .top, spacing: 12) {
                    Text("\(idx + 1)").font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.bg)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Theme.accentGlow))
                    Text(rec).font(.aetherBody).foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: 20)
    }
}
