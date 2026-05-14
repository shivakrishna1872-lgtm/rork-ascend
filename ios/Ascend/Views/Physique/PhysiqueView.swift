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

                PrimaryButton(title: "New Scan", icon: "plus.viewfinder") {
                    showScanFlow = true
                }
            }
            .padding(20)
            .glassCard(radius: 24)
        }
        .buttonStyle(.plain)
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
