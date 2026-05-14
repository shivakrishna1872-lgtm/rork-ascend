# Richer widgets, in-app camera capture, cleaner onboarding, split rankings

Keeping the existing design language untouched. Just upgrading content, removing prefilled data, and adding camera capture alongside photo upload.

**Widgets (Cal AI, Physique, Leaderboard, Overview)**
- Cal AI: add a 7-day mini calorie bar chart, today's macro split donut, hydration row, and a "next meal target" hint on medium; small gets a daily delta vs. yesterday.
- Physique: add 6-week mini score trendline (sparkline), body fat trend arrow with delta, symmetry / muscularity / conditioning micro-bars, last scan date.
- Leaderboard / Rank: split into two — a Physique Rank widget and a PSL Rank widget — each showing rank, gap, top-3 mini podium, and a tiny score trend bar. The global rank widget shows percentile and tier distribution mini chart.
- Overview (large): combined sparkline strip across nutrition / physique / PSL, weekly streak heatmap (7 dots), and XP-to-next-tier ring.
- All visuals reuse the current dark surface, line styles, accent color and Tier emblem — same design language, just denser and more analytical.
- Real empty states: if no scans / no meals / not in a circle, widget shows tasteful "Take your first scan" or "Log your first meal" prompts instead of demo numbers.

**In-app camera capture (alongside upload)**
- Cal AI meal capture, PSL face scan, and Physique scan flow each get a two-button choice row: "Take Photo" and "Upload from Library".
- Tapping "Take Photo" opens the native camera; on simulator a friendly placeholder explains to install via the Rork App on a real device (per platform guidance).
- Existing upload-from-library flow stays as-is. Same downstream analysis pipeline for both sources.

**Onboarding — no prefilled data**
- Name starts empty (no "Athlete" fallback unless user truly skips).
- Age, height, weight start unset; sliders/steppers show a placeholder dash until the user interacts. Next button stays disabled until each required field has a value.
- Sex, goals, activity level all start with nothing selected. Continue is disabled until the user picks.
- Permissions toggles default to off (user opts in deliberately).
- Visual layout, sliders, chips, and step animations are not redesigned — only the default values change and validation tightens.

**Global ranking — split PSL and Physique**
- In the Global tab of the rankings/circles view, replace the single combined tier display with two clearly separated sections:
  - Physique Ranking: tier distribution chart, your physique standing, physique tier ladder.
  - PSL Ranking: tier distribution chart, your PSL standing, PSL tier ladder.
- A small segmented toggle at the top of Global lets the user switch focus between PSL and Physique, while both summary cards remain visible below.
- Your standing card in each section pulls from the matching score (latest physique score vs. latest PSL score), not a blended number.

**Remove all remaining mock / demo data**
- Home: no fallback "70" symmetry, no hardcoded sleep "Good" / 0.72, no seeded insight headline. Replace with proper empty / "no data yet" placeholders.
- Cal AI, Physique, PSL: any leftover placeholder numbers, demo meals, demo scans removed. Each shows a clean empty state with a clear call to action.
- Circles: "Inviter" seeded friend on join, demo XP values, and example circle names removed. Joining a code creates an empty circle awaiting real members.
- Widget placeholder entry only used by the system snapshot — when real data is missing the widget renders an empty-state look, not fake stats.
- Profile and progression numbers all come from real saved user state.

Once approved I'll make these changes, then run validation to confirm the build is clean.