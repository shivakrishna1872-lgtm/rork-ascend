import SwiftUI
import SwiftData

/// Sheet for logging today's working sets of one exercise. Also shows the
/// deterministic progressive-overload suggestion and recent history.
struct LogSetSheet: View {
    let exercise: WorkoutExercise
    let planId: UUID?
    let onLogged: ((Int) -> Void)?
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query private var history: [SetLog]

    @State private var weightKg: String = ""
    @State private var reps: String = ""
    @State private var suggestion: ProgressiveOverload.Suggestion?
    @State private var todaySets: [SetLog] = []

    init(exercise: WorkoutExercise, planId: UUID?, onLogged: ((Int) -> Void)? = nil) {
        self.exercise = exercise
        self.planId = planId
        self.onLogged = onLogged
        let name = exercise.name
        let predicate = #Predicate<SetLog> { $0.exerciseName == name }
        _history = Query(filter: predicate, sort: [SortDescriptor(\.date, order: .reverse)])
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground(intensity: 0.4).ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 14) {
                        if let s = suggestion { suggestionCard(s) }
                        inputCard
                        if !todaySets.isEmpty { todayCard }
                        if !history.isEmpty { historyCard }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 6)
                    .padding(.bottom, 32)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle(exercise.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Theme.accentGlow)
                        .fontWeight(.semibold)
                }
            }
            .onAppear { computeSuggestion() }
            .onChange(of: history) { _, _ in computeSuggestion() }
        }
    }

    // MARK: - Cards

    private func suggestionCard(_ s: ProgressiveOverload.Suggestion) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: arrow(for: s.direction))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(color(for: s.direction))
                Text("TODAY'S TARGET")
                    .font(.system(size: 10, weight: .heavy)).tracking(1.6)
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if s.weightKg > 0 {
                    Text(formatKg(s.weightKg))
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                } else {
                    Text("Set your start weight")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                }
                if s.weightKg > 0 {
                    Text("× \(s.reps)")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
            }
            Text(s.reason)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if s.weightKg > 0 {
                Button {
                    Haptics.tap()
                    weightKg = trimDouble(s.weightKg)
                    reps = String(ProgressiveOverload.parseRepRange(s.reps).1)
                } label: {
                    Text("Use suggestion")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.accentGlow)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(color(for: s.direction).opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(color(for: s.direction).opacity(0.4), lineWidth: 0.6))
    }

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("LOG SET")
                .font(.system(size: 10, weight: .heavy)).tracking(1.6)
                .foregroundStyle(Theme.textTertiary)
            HStack(spacing: 10) {
                field("WEIGHT (kg)") {
                    TextField("0", text: $weightKg)
                        .keyboardType(.decimalPad)
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 12).padding(.vertical, 11)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface.opacity(0.6)))
                }
                field("REPS") {
                    TextField("0", text: $reps)
                        .keyboardType(.numberPad)
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 12).padding(.vertical, 11)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface.opacity(0.6)))
                }
            }
            Button {
                Haptics.success()
                logSet()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Log Set")
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.bg)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(RoundedRectangle(cornerRadius: 12).fill(canLog ? Theme.accentGlow : Theme.lineStrong))
            }
            .buttonStyle(.plain)
            .disabled(!canLog)
        }
        .padding(14)
        .glassCard(radius: 14)
    }

    private var todayCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TODAY")
                .font(.system(size: 10, weight: .heavy)).tracking(1.6)
                .foregroundStyle(Theme.textTertiary)
            ForEach(Array(todaySets.enumerated()), id: \.element.id) { idx, log in
                HStack {
                    Text("Set \(idx + 1)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Text("\(formatKg(log.weightKg)) × \(log.reps)")
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                    Button {
                        Haptics.warning()
                        ctx.delete(log)
                        try? ctx.save()
                        recomputeToday()
                        computeSuggestion()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 6)
                if idx < todaySets.count - 1 {
                    Divider().overlay(Theme.line)
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface.opacity(0.55)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.line, lineWidth: 0.5))
    }

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("RECENT")
                .font(.system(size: 10, weight: .heavy)).tracking(1.6)
                .foregroundStyle(Theme.textTertiary)
            let sessions = groupedSessions().prefix(5)
            ForEach(Array(sessions.enumerated()), id: \.offset) { _, session in
                let top = session.logs.map(\.weightKg).max() ?? 0
                let topReps = session.logs.filter { abs($0.weightKg - top) < 0.001 }.map(\.reps)
                HStack {
                    Text(session.label)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Text("\(formatKg(top)) · \(topReps.map(String.init).joined(separator: "/"))")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                }
                .padding(.vertical, 4)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface.opacity(0.4)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.line, lineWidth: 0.5))
    }

    // MARK: - Helpers

    private var canLog: Bool {
        Double(weightKg.replacingOccurrences(of: ",", with: ".")) ?? 0 > 0
            && Int(reps) ?? 0 > 0
    }

    private func field<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 9, weight: .heavy)).tracking(1.2)
                .foregroundStyle(Theme.textTertiary)
            content()
        }
        .frame(maxWidth: .infinity)
    }

    private func logSet() {
        let w = Double(weightKg.replacingOccurrences(of: ",", with: ".")) ?? 0
        let r = Int(reps) ?? 0
        guard w > 0, r > 0 else { return }
        let log = SetLog(
            exerciseName: exercise.name,
            planIdString: planId?.uuidString,
            setIndex: todaySets.count,
            weightKg: w,
            reps: r
        )
        ctx.insert(log)
        try? ctx.save()
        // Keep weight, clear reps for fast multi-set entry.
        reps = ""
        recomputeToday()
        computeSuggestion()
        // Notify caller so the rest timer can auto-start.
        let rest = exercise.restSeconds > 0 ? exercise.restSeconds : 75
        onLogged?(rest)
        dismiss()
    }

    private func recomputeToday() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        todaySets = history
            .filter { cal.startOfDay(for: $0.date) == today }
            .sorted { $0.setIndex < $1.setIndex }
    }

    private func computeSuggestion() {
        recomputeToday()
        // Suggestion uses only PRIOR sessions, not today.
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let prior = history.filter { cal.startOfDay(for: $0.date) < today }
        let isCompound = inferCompound()
        suggestion = ProgressiveOverload.suggest(
            exerciseName: exercise.name,
            repsTarget: exercise.reps,
            isCompound: isCompound,
            history: prior
        )
    }

    private func inferCompound() -> Bool {
        let n = exercise.name.lowercased()
        return ["squat", "deadlift", "bench", "press", "row", "pull-up", "chin-up", "dip", "lunge"]
            .contains { n.contains($0) }
    }

    private struct Session { let label: String; let logs: [SetLog] }

    private func groupedSessions() -> [Session] {
        let cal = Calendar.current
        var byDay: [Date: [SetLog]] = [:]
        for log in history {
            let day = cal.startOfDay(for: log.date)
            byDay[day, default: []].append(log)
        }
        let formatter: DateFormatter = {
            let f = DateFormatter(); f.dateFormat = "MMM d"; return f
        }()
        return byDay.keys.sorted(by: >).map { day in
            Session(label: formatter.string(from: day), logs: byDay[day] ?? [])
        }
    }

    private func formatKg(_ x: Double) -> String {
        if x == 0 { return "—" }
        if x == x.rounded() { return "\(Int(x))kg" }
        return String(format: "%.1fkg", x)
    }

    private func trimDouble(_ x: Double) -> String {
        if x == x.rounded() { return "\(Int(x))" }
        return String(format: "%.1f", x)
    }

    private func arrow(for d: ProgressiveOverload.Suggestion.Direction) -> String {
        switch d {
        case .up: return "arrow.up.right.circle.fill"
        case .down: return "arrow.down.right.circle.fill"
        case .hold: return "equal.circle.fill"
        case .fresh: return "sparkles"
        }
    }

    private func color(for d: ProgressiveOverload.Suggestion.Direction) -> Color {
        switch d {
        case .up: return Theme.accentGlow
        case .down: return .orange
        case .hold: return Theme.gold
        case .fresh: return Theme.accentGlow
        }
    }
}
