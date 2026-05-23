import SwiftUI
import SwiftData

/// Editable workout plan detail. Each day is a collapsible card; each exercise
/// is editable inline (sets/reps/rest/notes), reorderable, replaceable, and
/// removable. Includes a per-exercise rest timer that auto-advances.
struct WorkoutPlanDetailView: View {
    @Bindable var plan: WorkoutPlan
    let user: UserProfile
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss

    @State private var expandedDays: Set<UUID> = []
    @State private var editingExercise: WorkoutExercise?
    @State private var activeTimer: TimerState?
    @State private var showRegenerate: Bool = false
    @State private var addingExerciseDay: WorkoutDay?
    @State private var loggingExercise: WorkoutExercise?
    @State private var timerExpanded: Bool = false

    var body: some View {
        ZStack {
            AmbientBackground(intensity: 0.5).ignoresSafeArea()
            ScrollView {
                LazyVStack(spacing: 14) {
                    headerCard
                    ForEach(plan.sortedDays) { day in
                        dayCard(day)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)

            if let timer = activeTimer {
                VStack {
                    Spacer()
                    RestTimerBar(
                        state: timer,
                        onExpand: {
                            Haptics.tap()
                            timerExpanded = true
                        },
                        onClose: { activeTimer = nil }
                    )
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .animation(.spring(response: 0.4, dampingFraction: 0.86), value: activeTimer?.id)
            }
        }
        .navigationTitle(plan.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if plan.source == .generated {
                        Button {
                            Haptics.tap()
                            showRegenerate = true
                        } label: {
                            Label("Regenerate", systemImage: "arrow.clockwise")
                        }
                    }
                    Button {
                        renameDialog()
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        ctx.delete(plan)
                        try? ctx.save()
                        dismiss()
                    } label: {
                        Label("Delete Plan", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.accentGlow)
                }
            }
        }
        .sheet(item: $editingExercise) { ex in
            ExerciseEditorSheet(exercise: ex) {
                plan.updatedAt = .now
                try? ctx.save()
            }
        }
        .sheet(isPresented: $showRegenerate) {
            GeneratePlanView(user: user) { newPlan in
                // Replace contents of this plan with the new one so the user
                // doesn't lose their selection in the hub.
                replaceContents(with: newPlan)
            }
        }
        .sheet(item: $addingExerciseDay) { day in
            AddExerciseSheet(day: day) {
                plan.updatedAt = .now
                try? ctx.save()
            }
        }
        .sheet(item: $loggingExercise) { ex in
            LogSetSheet(exercise: ex, planId: plan.id, unitSystem: user.unitSystem) { restSeconds in
                // Auto-start the rest timer after logging a set.
                let secs = restSeconds > 0 ? restSeconds : (ex.restSeconds > 0 ? ex.restSeconds : 75)
                withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                    activeTimer = TimerState(exerciseName: ex.name, seconds: secs)
                    timerExpanded = true
                }
            }
        }
        .sheet(isPresented: $timerExpanded) {
            if let timer = activeTimer {
                RestTimerFullView(
                    state: timer,
                    onSkip: {
                        timer.cancel()
                        timerExpanded = false
                        activeTimer = nil
                    },
                    onDismiss: { timerExpanded = false }
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
            }
        }
        .onAppear {
            if expandedDays.isEmpty, let first = plan.sortedDays.first {
                expandedDays.insert(first.id)
            }
        }
    }

    // MARK: - Header

    private var headerCard: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(plan.goalRaw.uppercased())
                        .font(.system(size: 10, weight: .heavy)).tracking(2)
                        .foregroundStyle(Theme.accentGlow)
                    Text("\(plan.days.count) days · \(plan.source.label)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Image(systemName: plan.source == .scanned ? "doc.text" : "dumbbell.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(plan.source == .scanned ? Theme.gold : Theme.accentGlow)
            }
            statStrip
        }
        .padding(14)
        .glassCard(radius: 16)
    }

    private var statStrip: some View {
        let totals = weeklyTotals()
        return HStack(spacing: 0) {
            statColumn(value: "\(totals.exercises)", label: "EXERCISES")
            statDivider
            statColumn(value: "\(totals.sets)", label: "SETS / WEEK")
            statDivider
            statColumn(value: "\(totals.minutes)m", label: "AVG SESSION")
        }
    }

    private func statColumn(value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 9, weight: .heavy)).tracking(1.4)
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }
    private var statDivider: some View {
        Rectangle().fill(Theme.lineStrong).frame(width: 0.5, height: 28)
    }

    private func weeklyTotals() -> (exercises: Int, sets: Int, minutes: Int) {
        let all = plan.days.flatMap { $0.exercises }
        let exercises = all.count
        let sets = all.reduce(0) { $0 + $1.sets + $1.warmupSets }
        let totalSecs = all.reduce(0) { $0 + $1.estimatedSeconds }
        let avgMin = plan.days.isEmpty ? 0 : Int((Double(totalSecs) / Double(plan.days.count) / 60).rounded())
        return (exercises, sets, avgMin)
    }

    // MARK: - Day card

    private func dayCard(_ day: WorkoutDay) -> some View {
        let expanded = expandedDays.contains(day.id)
        let totalSets = day.exercises.reduce(0) { $0 + $1.sets + $1.warmupSets }
        let totalMin = max(1, day.exercises.reduce(0) { $0 + $1.estimatedSeconds } / 60)
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                Haptics.tap()
                withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                    if expanded { expandedDays.remove(day.id) } else { expandedDays.insert(day.id) }
                }
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(day.dayTitle)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        HStack(spacing: 6) {
                            Text(day.focus.uppercased())
                                .font(.system(size: 10, weight: .heavy)).tracking(1.6)
                                .foregroundStyle(Theme.textTertiary)
                            Text("·")
                                .font(.system(size: 10, weight: .heavy))
                                .foregroundStyle(Theme.textTertiary)
                            Text("\(totalSets) sets · ~\(totalMin)m")
                                .font(.system(size: 10, weight: .heavy)).tracking(0.8)
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }
                    Spacer()
                    Text("\(day.exercises.count)")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(minWidth: 26, minHeight: 22)
                        .padding(.horizontal, 6)
                        .background(Capsule().fill(Theme.surface.opacity(0.7)))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.textTertiary)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .padding(14)
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(spacing: 8) {
                    ForEach(day.sortedExercises) { ex in
                        exerciseRow(ex)
                    }
                    addExerciseButton(day)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.surface.opacity(0.55)))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.lineStrong, lineWidth: 0.6))
    }

    private func exerciseRow(_ ex: WorkoutExercise) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(ex.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    ChipsFlow(spacing: 6, lineSpacing: 6) {
                        setsRepsChip(ex)
                        restChip(ex)
                        if ex.warmupSets > 0 { warmupChip(ex) }
                        if !ex.tempo.isEmpty { tempoChip(ex) }
                        if !ex.muscleGroup.isEmpty { muscleChip(ex) }
                    }
                    if !ex.notes.isEmpty {
                        Text(ex.notes)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 2)
                    }
                }
                Spacer(minLength: 0)
                Menu {
                    Button { editingExercise = ex } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    Button { moveExercise(ex, by: -1) } label: {
                        Label("Move Up", systemImage: "arrow.up")
                    }
                    Button { moveExercise(ex, by: 1) } label: {
                        Label("Move Down", systemImage: "arrow.down")
                    }
                    Button(role: .destructive) { deleteExercise(ex) } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
            }
            HStack(spacing: 8) {
                Button {
                    Haptics.success()
                    loggingExercise = ex
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13, weight: .bold))
                        Text("Log Set")
                            .font(.system(size: 13, weight: .heavy))
                    }
                    .foregroundStyle(Theme.bg)
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Theme.accentGlow))
                }
                .buttonStyle(.plain)

                Button {
                    Haptics.medium()
                    let secs = ex.restSeconds > 0 ? ex.restSeconds : 75
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                        activeTimer = TimerState(exerciseName: ex.name, seconds: secs)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "timer")
                            .font(.system(size: 13, weight: .bold))
                        Text("Rest")
                            .font(.system(size: 13, weight: .heavy))
                    }
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 96, height: 36)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Theme.surface.opacity(0.7)))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.lineStrong, lineWidth: 0.6))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.bgElevated.opacity(0.5)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.line, lineWidth: 0.6))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            editingExercise = ex
        }
    }

    private func tempoChip(_ ex: WorkoutExercise) -> some View {
        Text("TEMPO \(ex.tempo)")
            .font(.system(size: 9, weight: .heavy)).tracking(0.9)
            .foregroundStyle(Theme.gold)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Capsule().fill(Theme.gold.opacity(0.14)))
    }
    private func muscleChip(_ ex: WorkoutExercise) -> some View {
        Text(ex.muscleGroup.capitalized)
            .font(.system(size: 10, weight: .heavy)).tracking(1)
            .foregroundStyle(Theme.textTertiary)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Capsule().fill(Theme.surface.opacity(0.6)))
    }

    private func setsRepsChip(_ ex: WorkoutExercise) -> some View {
        Text("\(ex.sets) × \(ex.reps)")
            .font(.system(size: 12, weight: .heavy))
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(Capsule().fill(Theme.accentGlow.opacity(0.18)))
            .overlay(Capsule().strokeBorder(Theme.accentGlow.opacity(0.4), lineWidth: 0.5))
    }
    private func restChip(_ ex: WorkoutExercise) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "timer").font(.system(size: 9, weight: .bold))
            Text(formatRest(ex.restSeconds))
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(Theme.textSecondary)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Capsule().fill(Theme.surface.opacity(0.7)))
    }
    private func warmupChip(_ ex: WorkoutExercise) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "flame.fill").font(.system(size: 9, weight: .bold))
            Text("\(ex.warmupSets) WU")
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(Theme.gold)
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Capsule().fill(Theme.gold.opacity(0.14)))
    }

    private func formatRest(_ secs: Int) -> String {
        if secs >= 60 && secs % 60 == 0 { return "\(secs/60) min" }
        if secs >= 60 { return "\(secs/60)m \(secs%60)s" }
        return "\(secs)s"
    }

    private func addExerciseButton(_ day: WorkoutDay) -> some View {
        Button {
            Haptics.tap()
            addingExerciseDay = day
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus.circle.fill")
                Text("Add Exercise")
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.accentGlow)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 11).fill(Theme.accentGlow.opacity(0.10)))
            .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Theme.accentGlow.opacity(0.35), style: StrokeStyle(lineWidth: 0.7, dash: [3, 3])))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Mutations

    private func deleteExercise(_ ex: WorkoutExercise) {
        Haptics.warning()
        if let day = ex.day {
            ctx.delete(ex)
            // Re-index remaining exercises.
            let remaining = day.exercises.filter { $0.id != ex.id }.sorted { $0.orderIndex < $1.orderIndex }
            for (i, e) in remaining.enumerated() { e.orderIndex = i }
        }
        plan.updatedAt = .now
        try? ctx.save()
    }

    private func moveExercise(_ ex: WorkoutExercise, by delta: Int) {
        guard let day = ex.day else { return }
        let sorted = day.sortedExercises
        guard let idx = sorted.firstIndex(where: { $0.id == ex.id }) else { return }
        let newIdx = idx + delta
        guard newIdx >= 0 && newIdx < sorted.count else { return }
        Haptics.tap()
        var arr = sorted
        arr.swapAt(idx, newIdx)
        for (i, e) in arr.enumerated() { e.orderIndex = i }
        plan.updatedAt = .now
        try? ctx.save()
    }

    private func renameDialog() {
        // Simple inline rename via alert is awkward in SwiftUI; flip to editing
        // the title using a sheet would add cost. Use UIAlertController bridge.
        let alert = UIAlertController(title: "Rename Plan", message: nil, preferredStyle: .alert)
        alert.addTextField { tf in
            tf.text = self.plan.title
            tf.autocapitalizationType = .words
        }
        alert.addAction(.init(title: "Cancel", style: .cancel))
        alert.addAction(.init(title: "Save", style: .default) { _ in
            if let text = alert.textFields?.first?.text, !text.trimmingCharacters(in: .whitespaces).isEmpty {
                self.plan.title = text.trimmingCharacters(in: .whitespaces)
                self.plan.updatedAt = .now
                try? self.ctx.save()
            }
        })
        UIApplication.shared.topMostViewController()?.present(alert, animated: true)
    }

    private func replaceContents(with newPlan: WorkoutPlan) {
        // Delete existing days (cascade clears exercises).
        for d in plan.days { ctx.delete(d) }
        plan.title = newPlan.title
        plan.goalRaw = newPlan.goalRaw
        plan.inputHash = newPlan.inputHash
        plan.preferencesJSON = newPlan.preferencesJSON
        plan.sourceRaw = newPlan.sourceRaw
        plan.updatedAt = .now
        for newDay in newPlan.sortedDays {
            let d = WorkoutDay(orderIndex: newDay.orderIndex, dayTitle: newDay.dayTitle, focus: newDay.focus)
            d.plan = plan
            ctx.insert(d)
            for newEx in newDay.sortedExercises {
                let ex = WorkoutExercise(
                    orderIndex: newEx.orderIndex,
                    name: newEx.name,
                    sets: newEx.sets,
                    reps: newEx.reps,
                    restSeconds: newEx.restSeconds,
                    notes: newEx.notes,
                    muscleGroup: newEx.muscleGroup,
                    equipment: newEx.equipment,
                    difficulty: newEx.difficulty,
                    warmupSets: newEx.warmupSets,
                    tempo: newEx.tempo
                )
                ex.day = d
                ctx.insert(ex)
            }
        }
        // Delete the freshly-generated duplicate.
        ctx.delete(newPlan)
        try? ctx.save()
    }
}

// MARK: - Rest timer

@MainActor
@Observable
final class TimerState: Identifiable {
    let id = UUID()
    let exerciseName: String
    let total: Int
    var remaining: Int
    private var task: Task<Void, Never>?

    init(exerciseName: String, seconds: Int) {
        self.exerciseName = exerciseName
        self.total = seconds
        self.remaining = seconds
        start()
    }

    func start() {
        task?.cancel()
        task = Task { [weak self] in
            while let self, self.remaining > 0 {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                self.remaining -= 1
                if self.remaining == 0 {
                    Haptics.success()
                }
            }
        }
    }

    func add(_ secs: Int) {
        remaining = max(0, remaining + secs)
        if remaining > 0 && task == nil { start() }
    }

    func cancel() { task?.cancel(); task = nil }

    var progress: Double {
        guard total > 0 else { return 0 }
        return 1 - Double(remaining) / Double(total)
    }
}

private struct RestTimerBar: View {
    @Bindable var state: TimerState
    let onExpand: () -> Void
    let onClose: () -> Void

    var body: some View {
        Button(action: onExpand) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().strokeBorder(Theme.line, lineWidth: 3)
                    Circle()
                        .trim(from: 0, to: state.progress)
                        .stroke(Theme.accentGlow, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.5), value: state.progress)
                    Text("\(state.remaining)")
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                        .monospacedDigit()
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 2) {
                    Text("REST · TAP TO EXPAND")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.6)
                        .foregroundStyle(Theme.textTertiary)
                    Text(state.exerciseName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Button {
                    Haptics.tap()
                    state.add(15)
                } label: {
                    Text("+15s")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Capsule().fill(Theme.surface.opacity(0.7)))
                }
                .buttonStyle(.plain)
                Button {
                    Haptics.tap()
                    state.cancel()
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Theme.surface.opacity(0.7)))
                }
                .buttonStyle(.plain)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.lineStrong, lineWidth: 0.6))
            .softShadow()
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Full rest timer

struct RestTimerFullView: View {
    @Bindable var state: TimerState
    let onSkip: () -> Void
    let onDismiss: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            AmbientBackground(intensity: 0.55).ignoresSafeArea()
            VStack(spacing: 28) {
                Text("REST")
                    .font(.system(size: 11, weight: .heavy)).tracking(3)
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.top, 18)
                Text(state.exerciseName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                ZStack {
                    Circle().strokeBorder(Theme.line, lineWidth: 10)
                    Circle()
                        .trim(from: 0, to: state.progress)
                        .stroke(Theme.accentGlow, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.5), value: state.progress)
                    VStack(spacing: 4) {
                        Text(formatTime(state.remaining))
                            .font(.system(size: 64, weight: .heavy, design: .rounded))
                            .foregroundStyle(Theme.textPrimary)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                        Text("of \(formatTime(state.total))")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.textTertiary)
                            .monospacedDigit()
                    }
                }
                .frame(width: 260, height: 260)
                .padding(.vertical, 8)

                HStack(spacing: 12) {
                    timerButton("-15s", systemImage: "minus") {
                        Haptics.tap(); state.add(-15)
                    }
                    timerButton("+15s", systemImage: "plus") {
                        Haptics.tap(); state.add(15)
                    }
                    timerButton("+30s", systemImage: "plus.forwardslash.minus") {
                        Haptics.tap(); state.add(30)
                    }
                }
                .padding(.horizontal, 24)

                Spacer(minLength: 0)

                HStack(spacing: 12) {
                    Button {
                        Haptics.warning()
                        onSkip()
                        dismiss()
                    } label: {
                        Text("Skip Rest")
                            .font(.system(size: 15, weight: .heavy))
                            .foregroundStyle(Theme.textPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface.opacity(0.7)))
                            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.lineStrong, lineWidth: 0.6))
                    }
                    .buttonStyle(.plain)
                    Button {
                        Haptics.tap()
                        onDismiss()
                        dismiss()
                    } label: {
                        Text("Minimize")
                            .font(.system(size: 15, weight: .heavy))
                            .foregroundStyle(Theme.bg)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(RoundedRectangle(cornerRadius: 14).fill(Theme.accentGlow))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 18)
            }
        }
        .onChange(of: state.remaining) { _, newValue in
            if newValue == 0 {
                // Auto-dismiss when timer completes.
                Haptics.success()
            }
        }
    }

    private func timerButton(_ label: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .bold))
                Text(label)
                    .font(.system(size: 13, weight: .heavy))
            }
            .foregroundStyle(Theme.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface.opacity(0.6)))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.lineStrong, lineWidth: 0.6))
        }
        .buttonStyle(.plain)
    }

    private func formatTime(_ secs: Int) -> String {
        let m = secs / 60
        let s = secs % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Chips wrap layout

struct ChipsFlow: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalWidth: CGFloat = 0
        for sub in subviews {
            let s = sub.sizeThatFits(.unspecified)
            if x + s.width > maxWidth && x > 0 {
                y += lineHeight + lineSpacing
                x = 0
                lineHeight = 0
            }
            x += s.width + spacing
            lineHeight = max(lineHeight, s.height)
            totalWidth = max(totalWidth, x - spacing)
        }
        return CGSize(width: totalWidth, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var lineHeight: CGFloat = 0
        for sub in subviews {
            let s = sub.sizeThatFits(.unspecified)
            if x - bounds.minX + s.width > maxWidth && x > bounds.minX {
                y += lineHeight + lineSpacing
                x = bounds.minX
                lineHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            lineHeight = max(lineHeight, s.height)
        }
    }
}

// MARK: - Exercise editor

private struct ExerciseEditorSheet: View {
    @Bindable var exercise: WorkoutExercise
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var sets: Int = 3
    @State private var reps: String = "10"
    @State private var rest: Int = 75
    @State private var notes: String = ""

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground(intensity: 0.45).ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 14) {
                        field("Exercise") {
                            TextField("Name", text: $name)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                                .padding(.horizontal, 14).padding(.vertical, 12)
                                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface.opacity(0.6)))
                                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.lineStrong, lineWidth: 0.6))
                        }
                        HStack(spacing: 12) {
                            field("Sets") {
                                Stepper(value: $sets, in: 1...20) {
                                    Text("\(sets)")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(Theme.textPrimary)
                                }
                                .padding(.horizontal, 14).padding(.vertical, 8)
                                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface.opacity(0.6)))
                                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.lineStrong, lineWidth: 0.6))
                            }
                            field("Reps") {
                                TextField("e.g. 8 or 8-10", text: $reps)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(Theme.textPrimary)
                                    .padding(.horizontal, 14).padding(.vertical, 12)
                                    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface.opacity(0.6)))
                                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.lineStrong, lineWidth: 0.6))
                            }
                        }
                        field("Rest (seconds)") {
                            HStack {
                                Stepper(value: $rest, in: 0...600, step: 15) {
                                    Text("\(rest)s")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(Theme.textPrimary)
                                }
                            }
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface.opacity(0.6)))
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.lineStrong, lineWidth: 0.6))
                        }
                        field("Notes") {
                            TextField("Optional", text: $notes, axis: .vertical)
                                .font(.system(size: 14))
                                .foregroundStyle(Theme.textPrimary)
                                .lineLimit(2...6)
                                .padding(.horizontal, 14).padding(.vertical, 12)
                                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface.opacity(0.6)))
                                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.lineStrong, lineWidth: 0.6))
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 6)
                    .padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Edit Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        exercise.name = name.trimmingCharacters(in: .whitespaces)
                        exercise.sets = sets
                        exercise.reps = reps.trimmingCharacters(in: .whitespaces)
                        exercise.restSeconds = rest
                        exercise.notes = notes
                        onSave()
                        dismiss()
                    }
                    .foregroundStyle(Theme.accentGlow)
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                name = exercise.name
                sets = exercise.sets
                reps = exercise.reps
                rest = exercise.restSeconds
                notes = exercise.notes
            }
        }
    }

    private func field<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .heavy)).tracking(1.6)
                .foregroundStyle(Theme.textTertiary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Add exercise

private struct AddExerciseSheet: View {
    let day: WorkoutDay
    let onSave: () -> Void
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss

    @State private var query: String = ""
    @State private var name: String = ""
    @State private var sets: Int = 3
    @State private var reps: String = "10"
    @State private var rest: Int = 75

    private var suggestions: [WorkoutPlanGenerator.LibraryExercise] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else {
            return Array(WorkoutPlanGenerator.library.prefix(12))
        }
        return WorkoutPlanGenerator.library
            .filter { $0.name.lowercased().contains(q) || $0.muscle.rawValue.contains(q) }
            .prefix(20).map { $0 }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground(intensity: 0.45).ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 12) {
                        TextField("Search exercises…", text: $query)
                            .font(.system(size: 15))
                            .padding(.horizontal, 14).padding(.vertical, 12)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface.opacity(0.6)))
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.lineStrong, lineWidth: 0.6))
                        ForEach(suggestions, id: \.name) { ex in
                            Button {
                                Haptics.tap()
                                name = ex.name
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(ex.name)
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(Theme.textPrimary)
                                        Text(ex.muscle.rawValue.capitalized)
                                            .font(.system(size: 11))
                                            .foregroundStyle(Theme.textTertiary)
                                    }
                                    Spacer()
                                    if name == ex.name {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(Theme.accentGlow)
                                    }
                                }
                                .padding(12)
                                .background(RoundedRectangle(cornerRadius: 11).fill(Theme.surface.opacity(0.55)))
                                .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(name == ex.name ? Theme.accentGlow : Theme.line, lineWidth: 0.6))
                            }
                            .buttonStyle(.plain)
                        }
                        Divider().overlay(Theme.line).padding(.vertical, 4)
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("SETS").font(.system(size: 10, weight: .heavy)).tracking(1.4).foregroundStyle(Theme.textTertiary)
                                Stepper("\(sets)", value: $sets, in: 1...20)
                                    .foregroundStyle(Theme.textPrimary)
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(RoundedRectangle(cornerRadius: 10).fill(Theme.surface.opacity(0.6)))
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text("REPS").font(.system(size: 10, weight: .heavy)).tracking(1.4).foregroundStyle(Theme.textTertiary)
                                TextField("10", text: $reps)
                                    .font(.system(size: 14, weight: .semibold))
                                    .padding(.horizontal, 12).padding(.vertical, 10)
                                    .background(RoundedRectangle(cornerRadius: 10).fill(Theme.surface.opacity(0.6)))
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text("REST").font(.system(size: 10, weight: .heavy)).tracking(1.4).foregroundStyle(Theme.textTertiary)
                                Stepper("\(rest)s", value: $rest, in: 0...600, step: 15)
                                    .foregroundStyle(Theme.textPrimary)
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(RoundedRectangle(cornerRadius: 10).fill(Theme.surface.opacity(0.6)))
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 6)
                    .padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Add Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add") {
                        let finalName = name.isEmpty ? query.trimmingCharacters(in: .whitespaces) : name
                        guard !finalName.isEmpty else { return }
                        let nextIdx = (day.exercises.map { $0.orderIndex }.max() ?? -1) + 1
                        let ex = WorkoutExercise(
                            orderIndex: nextIdx,
                            name: finalName,
                            sets: sets,
                            reps: reps,
                            restSeconds: rest
                        )
                        ex.day = day
                        ctx.insert(ex)
                        onSave()
                        dismiss()
                    }
                    .foregroundStyle(Theme.accentGlow)
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Helpers

extension UIApplication {
    func topMostViewController() -> UIViewController? {
        guard let scene = connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else { return nil }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        return top
    }
}
