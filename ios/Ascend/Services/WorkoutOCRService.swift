import Foundation
import Vision
import UIKit

/// On-device OCR + deterministic line parser for converting a photo of a
/// workout sheet into a structured `WorkoutPlanGenerator`-style result.
///
/// No AI is involved. Parsing is purely rule-based — same image text → same
/// structured plan every time.
nonisolated enum WorkoutOCRService {

    enum OCRError: Error { case noText, recognitionFailed }

    nonisolated struct ParsedExercise: Sendable {
        let name: String
        let sets: Int
        let reps: String
        let restSeconds: Int
        let notes: String
    }
    nonisolated struct ParsedDay: Sendable {
        let title: String
        let focus: String
        let exercises: [ParsedExercise]
    }
    nonisolated struct ParsedPlan: Sendable {
        let title: String
        let days: [ParsedDay]
    }

    // MARK: - Public API

    /// Recognize text on-device, then parse it into a structured plan.
    static func recognize(image: UIImage) async throws -> ParsedPlan {
        let lines = try await recognizeLines(image: image)
        guard !lines.isEmpty else { throw OCRError.noText }
        return parse(lines: lines)
    }

    // MARK: - OCR

    private static func recognizeLines(image: UIImage) async throws -> [String] {
        guard let cg = image.cgImage else { throw OCRError.recognitionFailed }
        return try await withCheckedThrowingContinuation { cont in
            let req = VNRecognizeTextRequest { request, error in
                if let error {
                    cont.resume(throwing: error)
                    return
                }
                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                // Sort top-to-bottom using bounding-box midpoint (Vision uses
                // bottom-left origin, so larger Y = higher on the page).
                let sorted = observations.sorted { a, b in
                    a.boundingBox.midY > b.boundingBox.midY
                }
                let strings = sorted.compactMap { $0.topCandidates(1).first?.string }
                cont.resume(returning: strings)
            }
            req.recognitionLevel = .accurate
            req.usesLanguageCorrection = true
            req.recognitionLanguages = ["en-US"]
            let handler = VNImageRequestHandler(cgImage: cg, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                do { try handler.perform([req]) }
                catch { cont.resume(throwing: error) }
            }
        }
    }

    // MARK: - Parser

    /// Deterministic line-based parser. Recognizes day headers, exercise lines
    /// (with sets×reps), and rest annotations. Anything that doesn't fit gets
    /// attached as a note to the previous exercise so nothing is lost.
    static func parse(lines: [String]) -> ParsedPlan {
        var days: [ParsedDay] = []
        var currentDayTitle: String? = nil
        var currentFocus: String = ""
        var currentExercises: [ParsedExercise] = []
        var planTitle: String? = nil
        var lastExerciseIndex: Int? = nil

        func flushDay() {
            guard let t = currentDayTitle else { return }
            days.append(ParsedDay(title: t, focus: currentFocus, exercises: currentExercises))
            currentDayTitle = nil
            currentFocus = ""
            currentExercises = []
            lastExerciseIndex = nil
        }

        for rawLine in lines {
            let line = clean(rawLine)
            guard !line.isEmpty else { continue }

            // Day header? e.g. "Day 1 - Push", "Monday: Upper", "Push Day"
            if let (title, focus) = matchDayHeader(line) {
                flushDay()
                currentDayTitle = title
                currentFocus = focus
                continue
            }

            // Plan title — first non-day line at the very top.
            if planTitle == nil && currentDayTitle == nil && !looksLikeExercise(line) {
                planTitle = line
                continue
            }

            // Rest annotation — attach to previous exercise.
            if let restSecs = matchRest(line), let idx = lastExerciseIndex {
                let prev = currentExercises[idx]
                currentExercises[idx] = ParsedExercise(
                    name: prev.name,
                    sets: prev.sets,
                    reps: prev.reps,
                    restSeconds: restSecs,
                    notes: prev.notes
                )
                continue
            }

            // Exercise line.
            if let ex = matchExercise(line) {
                // No active day yet — create a default one.
                if currentDayTitle == nil {
                    currentDayTitle = "Day \(days.count + 1)"
                    currentFocus = ""
                }
                currentExercises.append(ex)
                lastExerciseIndex = currentExercises.count - 1
                continue
            }

            // Free-form note — attach to previous exercise.
            if let idx = lastExerciseIndex {
                let prev = currentExercises[idx]
                let merged = prev.notes.isEmpty ? line : prev.notes + " " + line
                currentExercises[idx] = ParsedExercise(
                    name: prev.name,
                    sets: prev.sets,
                    reps: prev.reps,
                    restSeconds: prev.restSeconds,
                    notes: merged
                )
            }
        }
        flushDay()

        // If we got nothing structured, fall back to a single "Scanned" day with
        // each line as an exercise so the user can still edit.
        if days.isEmpty && !lines.isEmpty {
            let fallback = lines.compactMap { l -> ParsedExercise? in
                let c = clean(l)
                guard !c.isEmpty else { return nil }
                return matchExercise(c) ?? ParsedExercise(name: c, sets: 3, reps: "10", restSeconds: 75, notes: "")
            }
            days = [ParsedDay(title: "Day 1", focus: "Scanned", exercises: fallback)]
        }

        return ParsedPlan(title: planTitle ?? "Scanned Plan", days: days)
    }

    // MARK: - Line classifiers

    private static func clean(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
         .replacingOccurrences(of: "\t", with: " ")
         .replacingOccurrences(of: "  ", with: " ")
    }

    private static let dayHeaderRegex = try! NSRegularExpression(
        pattern: #"^(day\s*\d+|monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b\s*[-:–]?\s*(.*)$"#,
        options: [.caseInsensitive]
    )

    private static func matchDayHeader(_ line: String) -> (String, String)? {
        let range = NSRange(line.startIndex..., in: line)
        guard let m = dayHeaderRegex.firstMatch(in: line, options: [], range: range) else {
            // "Push Day" style.
            let lower = line.lowercased()
            if lower.hasSuffix(" day") || lower == "push" || lower == "pull" || lower == "legs"
               || lower == "upper" || lower == "lower" || lower == "rest" {
                return (line, line)
            }
            return nil
        }
        let title = String(line[Range(m.range(at: 1), in: line)!]).capitalized
        let focusRaw = m.range(at: 2).location == NSNotFound
            ? ""
            : String(line[Range(m.range(at: 2), in: line)!]).trimmingCharacters(in: .whitespaces)
        return (title, focusRaw.isEmpty ? "Workout" : focusRaw.capitalized)
    }

    // Matches "Bench Press 4x8", "Bench Press - 4 x 8-10", "Bench Press 4 sets x 8 reps"
    private static let exerciseRegex = try! NSRegularExpression(
        pattern: #"^(.+?)\s*[-–:]?\s*(\d{1,2})\s*(?:x|×|sets?\s*(?:x|of)?)\s*([\d–\-]{1,7}|\d{1,3}\s*s(?:ec)?)\b"#,
        options: [.caseInsensitive]
    )

    private static func looksLikeExercise(_ line: String) -> Bool {
        exerciseRegex.firstMatch(in: line, options: [], range: NSRange(line.startIndex..., in: line)) != nil
    }

    private static func matchExercise(_ line: String) -> ParsedExercise? {
        let range = NSRange(line.startIndex..., in: line)
        guard let m = exerciseRegex.firstMatch(in: line, options: [], range: range),
              let nameRange = Range(m.range(at: 1), in: line),
              let setsRange = Range(m.range(at: 2), in: line),
              let repsRange = Range(m.range(at: 3), in: line) else { return nil }
        let rawName = String(line[nameRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        let setsStr = String(line[setsRange])
        let repsStr = String(line[repsRange]).trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "–", with: "-")
        guard !rawName.isEmpty, let sets = Int(setsStr) else { return nil }
        // Default rest based on compound heuristic.
        let lowerName = rawName.lowercased()
        let isCompound = ["bench", "squat", "deadlift", "press", "row", "pull", "clean", "snatch", "lunge"].contains { lowerName.contains($0) }
        let defaultRest = isCompound ? 90 : 60
        return ParsedExercise(
            name: rawName.capitalizedExerciseName(),
            sets: max(1, min(20, sets)),
            reps: repsStr,
            restSeconds: defaultRest,
            notes: ""
        )
    }

    private static let restRegex = try! NSRegularExpression(
        pattern: #"^rest\s*[:\-–]?\s*(\d{1,3})\s*(s|sec|seconds?|m|min|minutes?)\b"#,
        options: [.caseInsensitive]
    )

    private static func matchRest(_ line: String) -> Int? {
        let range = NSRange(line.startIndex..., in: line)
        guard let m = restRegex.firstMatch(in: line, options: [], range: range),
              let numRange = Range(m.range(at: 1), in: line),
              let unitRange = Range(m.range(at: 2), in: line),
              let val = Int(line[numRange]) else { return nil }
        let unit = line[unitRange].lowercased()
        let multiplier = unit.hasPrefix("m") ? 60 : 1
        return min(600, val * multiplier)
    }
}

private extension String {
    /// "BENCH PRESS" / "bench press" → "Bench Press".
    func capitalizedExerciseName() -> String {
        self.split(separator: " ").map { word -> String in
            let s = String(word)
            if s.count <= 2 { return s.lowercased() }
            return s.prefix(1).uppercased() + s.dropFirst().lowercased()
        }.joined(separator: " ")
    }
}
