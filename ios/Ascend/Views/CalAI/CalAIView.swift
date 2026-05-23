import SwiftUI
import SwiftData
import PhotosUI

struct CalAIView: View {
    let user: UserProfile
    @Environment(\.modelContext) private var ctx
    @Environment(AppState.self) private var app
    @Query(sort: \MealEntry.date, order: .reverse) private var allMeals: [MealEntry]
    @Query(sort: \PhysiqueScanRecord.date, order: .reverse) private var scans: [PhysiqueScanRecord]

    @State private var showLog = false
    @State private var editingMeal: MealEntry?

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                header

                ringsCard.blurFadeIn(delay: 0.06)

                HStack(spacing: 12) {
                    macroCard("Protein", value: totalProtein, target: user.proteinTargetG, color: Theme.elite)
                    macroCard("Carbs", value: totalCarbs, target: user.carbTargetG, color: Theme.accentGlow)
                    macroCard("Fats", value: totalFats, target: user.fatTargetG, color: Theme.warn)
                }
                .blurFadeIn(delay: 0.12)

                advisorCard.blurFadeIn(delay: 0.18)

                SectionHeader(title: "Today’s Log", trailing: "\(todayMeals.count) meals").padding(.horizontal, 4)
                logList.blurFadeIn(delay: 0.24)

                PrimaryButton(title: "Log a Meal", icon: "plus") {
                    showLog = true
                }
                .padding(.top, 4)

            }
            .padding(.horizontal, 20).padding(.top, 12)
        }
        .scrollIndicators(.hidden)
        .tabBarBottomInset()
        .sheet(isPresented: $showLog) {
            MealLogSheet(user: user)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $editingMeal) { meal in
            MealEditSheet(meal: meal, user: user)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Cal AI".uppercased())
                .font(.system(size: 11, weight: .semibold)).tracking(2)
                .foregroundStyle(Theme.textTertiary)
            Text("Nutrition Intelligence")
                .font(.aetherTitle).foregroundStyle(Theme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var todayMeals: [MealEntry] {
        let cal = Calendar.current
        return allMeals.filter { cal.isDateInToday($0.date) }
    }

    private var totalCals: Int { todayMeals.reduce(0) { $0 + $1.calories } }
    private var totalProtein: Int { todayMeals.reduce(0) { $0 + $1.proteinG } }
    private var totalCarbs: Int { todayMeals.reduce(0) { $0 + $1.carbsG } }
    private var totalFats: Int { todayMeals.reduce(0) { $0 + $1.fatsG } }

    private var ringsCard: some View {
        VStack(spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Calories".uppercased())
                        .font(.system(size: 10, weight: .semibold)).tracking(2)
                        .foregroundStyle(Theme.textTertiary)
                    HStack(alignment: .lastTextBaseline, spacing: 6) {
                        CountingNumber(value: Double(max(0, user.dailyCalorieTarget - totalCals)),
                                       font: .system(size: 44, weight: .semibold, design: .rounded))
                        Text("left").font(.aetherBody).foregroundStyle(Theme.textSecondary)
                    }
                    Text("\(totalCals) / \(user.dailyCalorieTarget) \(user.unitSystem.calorieUnit)")
                        .font(.aetherMono).foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                ZStack {
                    Circle().stroke(Theme.line, lineWidth: 12)
                    Circle()
                        .trim(from: 0, to: min(1, Double(totalCals) / Double(max(1, user.dailyCalorieTarget))))
                        .stroke(
                            AngularGradient(
                                colors: [Theme.accent, Theme.accentGlow, Theme.elite, Theme.accent],
                                center: .center
                            ),
                            style: .init(lineWidth: 12, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .shadow(color: Theme.accent.opacity(0.5), radius: 8)
                        .animation(.smooth(duration: 1.0), value: totalCals)
                    Image(systemName: "flame.fill").font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Theme.accentGlow)
                }
                .frame(width: 110, height: 110)
            }
        }
        .padding(20)
        .glassCard(radius: 24)
    }

    private func macroCard(_ label: String, value: Int, target: Int, color: Color) -> some View {
        let progress = Double(value) / Double(max(1, target))
        return VStack(alignment: .leading, spacing: 10) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold)).tracking(1.5)
                .foregroundStyle(Theme.textTertiary)
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                CountingNumber(value: Double(value),
                               font: .system(size: 22, weight: .semibold, design: .rounded))
                Text("g").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.textSecondary)
            }
            Text("of \(target)g").font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.line)
                    Capsule().fill(color).frame(width: max(4, geo.size.width * min(1, progress)))
                        .shadow(color: color.opacity(0.5), radius: 4)
                }
            }.frame(height: 4)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: 18)
    }

    private var advisorCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Smart Advisor".uppercased())
                    .font(.system(size: 10, weight: .semibold)).tracking(2)
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
                Text(advice.recommendation.uppercased())
                    .font(.system(size: 10, weight: .bold)).tracking(1.5)
                    .foregroundStyle(advice.color)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().fill(advice.color.opacity(0.15)))
                    .overlay(Capsule().strokeBorder(advice.color.opacity(0.5), lineWidth: 0.6))
            }
            Text(advice.reason)
                .font(.aetherBody).foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: 18)
    }

    private var advice: (recommendation: String, reason: String, color: Color) {
        let bf = scans.first?.bodyFatPercent ?? 16
        let hasLeanGoal = user.goals.contains(.loseFat)
        let hasMuscleGoal = user.goals.contains(.gainMuscle)
        if bf > 22 || hasLeanGoal {
            return ("Mini-cut", "Body fat is above optimal for aesthetic goals. A 14–21 day deficit will sharpen conditioning.", Theme.warn)
        }
        if bf < 14 && hasMuscleGoal {
            return ("Lean Bulk", "Conditioning is strong. A modest surplus will support muscularity without sacrificing definition.", Theme.good)
        }
        return ("Recomp", "Composition is balanced. Hold maintenance, prioritize protein and recovery.", Theme.accent)
    }

    @ViewBuilder
    private var logList: some View {
        if todayMeals.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "fork.knife.circle")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(Theme.textTertiary)
                Text("No meals logged yet.")
                    .font(.aetherBody).foregroundStyle(Theme.textTertiary)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 26)
            .glassCard(radius: 18)
        } else {
            VStack(spacing: 8) {
                ForEach(todayMeals) { meal in
                    Button {
                        Haptics.tap()
                        editingMeal = meal
                    } label: {
                        HStack(spacing: 12) {
                            thumb(for: meal)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(meal.name).font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Theme.textPrimary)
                                Text("\(meal.calories) \(user.unitSystem.calorieUnit) · P\(meal.proteinG) C\(meal.carbsG) F\(meal.fatsG)")
                                    .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.textSecondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 4) {
                                Text(meal.date.formatted(date: .omitted, time: .shortened))
                                    .font(.aetherCaption).foregroundStyle(Theme.textTertiary)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(Theme.textTertiary)
                            }
                        }
                        .padding(12)
                        .glassCard(radius: 14)
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        Button(role: .destructive) {
                            ctx.delete(meal); try? ctx.save()
                        } label: { Image(systemName: "trash") }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func thumb(for meal: MealEntry) -> some View {
        // Meal photos are intentionally not retained — show an icon placeholder.
        RoundedRectangle(cornerRadius: 10).fill(Theme.accent.opacity(0.15))
            .frame(width: 44, height: 44)
            .overlay { Image(systemName: "fork.knife").foregroundStyle(Theme.accentGlow) }
    }
}

// MARK: - Meal Edit Sheet

struct MealEditSheet: View {
    @Bindable var meal: MealEntry
    let user: UserProfile
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var ctx

    @State private var name: String = ""
    @State private var calories: String = ""
    @State private var proteinG: String = ""
    @State private var carbsG: String = ""
    @State private var fatsG: String = ""
    @State private var note: String = ""
    @State private var showDeleteConfirm = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("Edit Meal".uppercased())
                    .font(.system(size: 11, weight: .semibold)).tracking(2.5)
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.top, 18)

                field("Name", text: $name, placeholder: "e.g. Chicken bowl")

                HStack(spacing: 10) {
                    numField("Calories", text: $calories, unit: user.unitSystem.calorieUnit)
                    numField("Protein", text: $proteinG, unit: "g")
                }
                HStack(spacing: 10) {
                    numField("Carbs", text: $carbsG, unit: "g")
                    numField("Fats", text: $fatsG, unit: "g")
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Notes".uppercased())
                        .font(.system(size: 10, weight: .semibold)).tracking(1.5)
                        .foregroundStyle(Theme.textTertiary)
                    TextField("Optional", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                        .font(.system(size: 15, weight: .medium))
                        .padding(14)
                        .glassCard(radius: 14)
                }

                PrimaryButton(title: "Save Changes", icon: "checkmark") {
                    save()
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                .opacity(name.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)

                Button(role: .destructive) {
                    Haptics.tap()
                    showDeleteConfirm = true
                } label: {
                    HStack {
                        Image(systemName: "trash")
                        Text("Delete Meal")
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.bad)
                    .frame(maxWidth: .infinity).frame(height: 46)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.bad.opacity(0.12)))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.bad.opacity(0.4), lineWidth: 0.6))
                }
                .buttonStyle(.plain)

                Color.clear.frame(height: 30)
            }
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
        .background(Theme.bg)
        .onAppear {
            name = meal.name
            calories = String(meal.calories)
            proteinG = String(meal.proteinG)
            carbsG = String(meal.carbsG)
            fatsG = String(meal.fatsG)
            note = meal.note
        }
        .confirmationDialog("Delete this meal?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                ctx.delete(meal)
                try? ctx.save()
                Haptics.success()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func field(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold)).tracking(1.5)
                .foregroundStyle(Theme.textTertiary)
            TextField(placeholder, text: text)
                .font(.system(size: 16, weight: .medium))
                .padding(14)
                .glassCard(radius: 14)
        }
    }

    private func numField(_ label: String, text: Binding<String>, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold)).tracking(1.5)
                .foregroundStyle(Theme.textTertiary)
            HStack(spacing: 4) {
                TextField("0", text: text)
                    .keyboardType(.numberPad)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                Text(unit)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(14)
            .glassCard(radius: 14)
        }
        .frame(maxWidth: .infinity)
    }

    private func save() {
        meal.name = name.trimmingCharacters(in: .whitespaces)
        meal.calories = max(0, Int(calories) ?? 0)
        meal.proteinG = max(0, Int(proteinG) ?? 0)
        meal.carbsG = max(0, Int(carbsG) ?? 0)
        meal.fatsG = max(0, Int(fatsG) ?? 0)
        meal.note = note
        try? ctx.save()
        Haptics.success()
        dismiss()
    }
}

// MARK: - Meal Log Sheet

struct MealLogSheet: View {
    let user: UserProfile
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var ctx
    @Environment(AppState.self) private var app

    @State private var description: String = ""
    @State private var pickerItem: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var analyzing = false
    @State private var result: MealAnalysis?
    @State private var error: String?
    @State private var showCamera = false
    @State private var showCameraUnavailable = false
    @State private var showCameraDenied = false
    @State private var showLibraryPicker = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("Log a Meal".uppercased())
                    .font(.system(size: 11, weight: .semibold)).tracking(2.5)
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.top, 18)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(image == nil ? "Describe it" : "Hint (optional)")
                            .font(.system(size: 11, weight: .semibold)).tracking(1.5)
                            .foregroundStyle(Theme.textTertiary)
                        Spacer()
                        if image != nil {
                            Text("Auto-detected from photo".uppercased())
                                .font(.system(size: 9, weight: .bold)).tracking(1.3)
                                .foregroundStyle(Theme.good)
                        }
                    }
                    TextField(image == nil
                              ? "e.g. Chicken burrito bowl with guacamole"
                              : "Optional — add details if the photo is unclear",
                              text: $description, axis: .vertical)
                        .lineLimit(2...4)
                        .font(.system(size: 16, weight: .medium))
                        .padding(14)
                        .glassCard(radius: 14)
                }

                if let image {
                    Color.clear.frame(height: 160)
                        .overlay { Image(uiImage: image).resizable().aspectRatio(contentMode: .fill).allowsHitTesting(false) }
                        .clipShape(.rect(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.line, lineWidth: 0.5))
                }

                HStack(spacing: 10) {
                    Button {
                        Haptics.tap()
                        CameraAccessTrigger(
                            onAuthorized: { showCamera = true },
                            onDenied: { showCameraDenied = true },
                            onUnavailable: { showCameraUnavailable = true }
                        ).fire()
                    } label: {
                        HStack {
                            Image(systemName: "camera.fill")
                            Text("Take Photo")
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(maxWidth: .infinity).frame(height: 46)
                        .glassCard(radius: 12)
                    }
                    .buttonStyle(.plain)

                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        HStack {
                            Image(systemName: image == nil ? "photo.badge.plus" : "photo")
                            Text(image == nil ? "Upload" : "Change")
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(maxWidth: .infinity).frame(height: 46)
                        .glassCard(radius: 12)
                    }
                }

                if let result {
                    resultsView(result).transition(.opacity)
                } else if analyzing {
                    analyzingPlaceholder
                }

                if let error {
                    Text(error).font(.aetherBody).foregroundStyle(Theme.bad)
                }

                if result != nil {
                    PrimaryButton(title: "Save Meal", icon: "checkmark") {
                        saveMeal()
                    }
                } else {
                    PrimaryButton(title: analyzing ? "Analyzing…" : "Analyze", icon: "sparkles", loading: analyzing) {
                        analyze()
                    }
                    .disabled(canAnalyze == false || analyzing)
                    .opacity((canAnalyze == false || analyzing) ? 0.5 : 1)
                }

                Color.clear.frame(height: 30)
            }
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
        .background(Theme.bg)
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let img = UIImage(data: data) {
                    await MainActor.run { image = img }
                }
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraSheet(
                onCapture: { img in image = img; showCamera = false },
                onCancel: { showCamera = false }
            )
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showCameraUnavailable) {
            CameraUnavailableSheet(reason: .unavailable, onUseLibrary: { showLibraryPicker = true })
        }
        .sheet(isPresented: $showCameraDenied) {
            CameraUnavailableSheet(reason: .denied, onUseLibrary: { showLibraryPicker = true })
        }
        .photosPicker(isPresented: $showLibraryPicker, selection: $pickerItem, matching: .images)
    }

    private var canAnalyze: Bool {
        // Either a photo OR a description is enough — vision auto-detects food.
        image != nil || !description.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var analyzingPlaceholder: some View {
        VStack(spacing: 14) {
            FoodScanAnimation(image: image)
                .frame(height: image == nil ? 80 : 180)
            HStack(spacing: 8) {
                ProgressView().tint(Theme.accentGlow).scaleEffect(0.85)
                Text(image == nil ? "Estimating macros…" : "Identifying foods & portions…")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 16).padding(.horizontal, 12)
        .glassCard(radius: 16)
    }

    private func resultsView(_ r: MealAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(r.name).font(.system(size: 17, weight: .semibold))
                    if !r.dishType.isEmpty {
                        Text(r.dishType.uppercased())
                            .font(.system(size: 9, weight: .bold)).tracking(1.3)
                            .foregroundStyle(Theme.accentGlow)
                    }
                }
                Spacer()
                Text("\(r.calories) \(user.unitSystem.calorieUnit)").font(.aetherMono).foregroundStyle(Theme.accentGlow)
            }
            HStack(spacing: 8) {
                macroPill("P", r.proteinG, Theme.elite)
                macroPill("C", r.carbsG, Theme.accentGlow)
                macroPill("F", r.fatsG, Theme.warn)
            }
            HStack(spacing: 6) {
                Circle().fill(confidenceColor(r.confidence)).frame(width: 6, height: 6)
                Text("\(r.confidence)% confidence")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                if r.portionMultiplier > 0 && abs(r.portionMultiplier - 1.0) > 0.05 {
                    Text("· \(portionLabel(r.portionMultiplier)) portion")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            // Show top alternates when the top pick isn't confident enough.
            // Tapping one swaps the dish without burning another scan.
            if r.needsConfirmation, r.foodCandidates.count > 1 {
                candidatesPicker(r)
            }
            if !r.ingredients.isEmpty {
                Divider().overlay(Theme.line)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Detected Ingredients".uppercased())
                        .font(.system(size: 10, weight: .semibold)).tracking(1.5)
                        .foregroundStyle(Theme.textTertiary)
                    ForEach(r.ingredients, id: \.self) { ing in
                        HStack(spacing: 8) {
                            Circle().fill(Theme.accent.opacity(0.6)).frame(width: 4, height: 4)
                            Text(ing.name)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                            if !ing.portion.isEmpty {
                                Text(ing.portion)
                                    .font(.aetherMono)
                                    .foregroundStyle(Theme.textTertiary)
                            }
                        }
                    }
                }
            }
            if !r.note.isEmpty {
                Text(r.note).font(.aetherBody).foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(16)
        .glassCard(radius: 16)
    }

    private func candidatesPicker(_ r: MealAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Not quite right? Pick a closer match".uppercased())
                .font(.system(size: 9, weight: .bold)).tracking(1.4)
                .foregroundStyle(Theme.textTertiary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(r.foodCandidates.prefix(5), id: \.self) { cand in
                        Button {
                            Haptics.tap()
                            swapToCandidate(cand)
                        } label: {
                            HStack(spacing: 6) {
                                Text(cand.name).font(.system(size: 12, weight: .semibold))
                                Text("\(cand.confidence)%")
                                    .font(.aetherMono)
                                    .foregroundStyle(Theme.textTertiary)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Capsule().fill(Theme.accent.opacity(0.12)))
                            .overlay(Capsule().strokeBorder(Theme.line, lineWidth: 0.6))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .contentMargins(.horizontal, 0)
        }
    }

    private func portionLabel(_ m: Double) -> String {
        if m < 0.65 { return "small" }
        if m < 0.9 { return "under" }
        if m > 1.6 { return "large" }
        if m > 1.15 { return "big" }
        return "regular"
    }

    private func swapToCandidate(_ cand: FoodCandidate) {
        // Re-run analysis with the candidate name as the description so it goes
        // through the same DB-grounded resolver — no AI-authored macros.
        description = cand.name
        analyze()
    }

    private func confidenceColor(_ c: Int) -> Color {
        if c >= 75 { return Theme.good }
        if c >= 50 { return Theme.warn }
        return Theme.bad
    }

    private func macroPill(_ letter: String, _ value: Int, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Text(letter).font(.system(size: 11, weight: .bold)).foregroundStyle(color)
            Text("\(value)g").font(.system(size: 13, weight: .semibold))
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Capsule().fill(color.opacity(0.15)))
        .overlay(Capsule().strokeBorder(color.opacity(0.4), lineWidth: 0.6))
    }

    private func analyze() {
        analyzing = true
        error = nil
        Task {
            do {
                let r = try await AIService.shared.analyzeMeal(description: description, image: image, unitSystem: user.unitSystemRaw)
                await MainActor.run {
                    withAnimation { result = r; analyzing = false }
                    Haptics.success()
                }
            } catch {
                await MainActor.run {
                    self.error = (error as? LocalizedError)?.errorDescription ?? "Couldn’t analyze meal."
                    self.analyzing = false
                }
            }
        }
    }

    private func saveMeal() {
        guard let r = result else { return }
        let meal = MealEntry(
            name: r.name,
            calories: r.calories,
            proteinG: r.proteinG,
            carbsG: r.carbsG,
            fatsG: r.fatsG,
            note: r.note,
            imageData: nil
        )
        ctx.insert(meal)
        app.bumpStreakIfNeeded(user)
        app.awardXP(15, to: user)
        try? ctx.save()
        WidgetSync.push(user: user, context: ctx)
        Haptics.success()
        dismiss()
    }
}
