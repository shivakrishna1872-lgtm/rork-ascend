# Coach tab — chat + workouts

The Coach tab houses two related surfaces:

1. **AI Chat** (already shipped) — iMessage-style coach that can take real actions in the app.
2. **Workouts** (this plan) — deterministic workout plan generator + scan-a-plan-from-photo, both fully editable with a built-in timer.

## Workouts feature

### Entry point
- A dumbbell button in the Coach header opens the Workouts hub (sheet).
- Hub shows: saved plans list, "Generate Plan" CTA, "Scan Plan" CTA.

### Auto plan generator
- Inputs: age, height, weight, sex (from `UserProfile`), plus per-plan: fitness level, goal, equipment, frequency, injuries.
- Deterministic rule-based generator (no AI). Same inputs → same plan.
- 3 days → full-body A/B/C, 4 days → upper/lower, 5 days → PPL+UL, 6 days → PPLPPL.
- Goal drives set/rep/rest schemes (strength / hypertrophy / fat loss / athletic).
- Exercise library is an internal table tagged by muscle group + equipment + difficulty.

### Scan plan
- Camera or photo picker → on-device Vision OCR (`VNRecognizeTextRequest`).
- Deterministic line parser converts raw text into days/exercises/sets/reps/rest.
- Result lands in the same editable plan model as the auto generator.

### Editing
- Reorder, edit, replace, delete, add exercises. Edit sets/reps/rest/notes.
- All edits persisted via SwiftData.
- Regenerate plan from updated inputs.

### Timer
- Per-set start button; rest countdown bar appears; auto-advance optional.
- Defaults: compound 90s, isolation 60s, fallback 75s.

### UI
- Apple Fitness-clean: collapsible day cards, bold exercise name, `sets × reps` chip, rest pill.
- All dark theme, consistent with rest of app.

### Architecture rules
- Generator is pure / deterministic.
- OCR + parser produce structured data only — never raw text in UI.
- AI is NOT used to generate or modify plans (only allowed to explain them later).

## Tasks

- [x] Add SwiftData models: `WorkoutPlan`, `WorkoutDay`, `WorkoutExercise`.
- [x] Deterministic plan generator + internal exercise library.
- [x] OCR scan service + parser.
- [x] Workouts hub + plan detail (editable + timer) + generate form + scan flow.
- [x] Register models + add entry button in Coach header.
- [x] Progressive overload tracker — `SetLog` model + deterministic suggester surfaced in the plan editor.
- [x] HealthKit recovery signal — HRV / sleep / resting-HR badge on the Workouts hub.
- [x] Plan templates — preset PPL / Upper-Lower / Starting 5×5 / Full-Body 3 forkable into editable plans.
