# Ascend Life — production polish pass

Keep current UI / colors; surgical changes only.

- [x] Brand: app display name "Ascend Life", new logo PNG into AppIcon (root + ios)
- [x] Permission strings updated to "Ascend Life"
- [x] Welcome / onboarding wordmark says "Ascend Life"
- [x] Notifications: NotificationService with permission + daily reminders, wired into onboarding & Profile
- [x] Front camera mirror fix: capture mirrors to match preview (selfies look natural)
- [x] PSL stability: rolling-average smoothing over recent scans; pass anchor scores into AI prompt
- [x] Physique stability: rolling-average smoothing over recent scans
- [x] Physique pose tolerance: loosened brightness/centering/coverage thresholds
- [x] Cal AI: vision-first auto-detect; description optional when image present; better prompt
- [x] Analysis animations: smoother PSL face mesh sweep, Physique skeleton trace, Cal AI scan grid
- [x] runChecks passes
