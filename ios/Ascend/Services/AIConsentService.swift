import Foundation
import SwiftUI

/// One‑time consent gate for sending user text or images to the third‑party AI
/// provider (required by App Store Guidelines 5.1.1(i) and 5.1.2(i)).
///
/// Behavior:
/// - Persists the decision locally in `UserDefaults` so we only ask once.
/// - `ensureConsent()` is the single entry point every AI call funnels through.
///   - If the user already tapped **Allow**, it returns `true` immediately.
///   - If undecided, it presents the consent sheet and awaits the tap.
///   - If the user taps **Not Now**, it returns `false` and the AI call is
///     skipped — no data leaves the device.
/// - The user can revoke at any time from Profile → Privacy.
@MainActor
@Observable
final class AIConsentService {
    static let shared = AIConsentService()

    private let decisionKey = "ai.consent.decision.v1"   // "allowed" | "denied" | nil

    /// Drives the consent sheet presented from the root view.
    var isPromptVisible: Bool = false

    /// Continuations waiting on the user's tap. Multiple AI calls in flight
    /// share a single prompt and all resume together.
    private var pending: [CheckedContinuation<Bool, Never>] = []

    private init() {}

    // MARK: - Public state

    var hasDecided: Bool {
        UserDefaults.standard.string(forKey: decisionKey) != nil
    }

    var isAllowed: Bool {
        UserDefaults.standard.string(forKey: decisionKey) == "allowed"
    }

    // MARK: - Entry points

    /// Guarantees a consent decision before any AI call. Returns `true` only
    /// when the user has tapped **Allow** (now or previously).
    func ensureConsent() async -> Bool {
        if isAllowed { return true }
        if hasDecided { return false } // user tapped Not Now previously — caller can re-prompt via `requestAgain()`
        return await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            pending.append(cont)
            isPromptVisible = true
        }
    }

    /// Force-show the prompt again (e.g. after the user revoked, or tapped a
    /// "Try AI analysis" CTA after previously declining).
    func requestAgain() async -> Bool {
        if isAllowed { return true }
        return await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            pending.append(cont)
            isPromptVisible = true
        }
    }

    // MARK: - User actions

    func allow() {
        UserDefaults.standard.set("allowed", forKey: decisionKey)
        isPromptVisible = false
        resumeAll(true)
    }

    func deny() {
        UserDefaults.standard.set("denied", forKey: decisionKey)
        isPromptVisible = false
        resumeAll(false)
    }

    /// Clear the stored decision so the next AI call re-prompts.
    func revoke() {
        UserDefaults.standard.removeObject(forKey: decisionKey)
        isPromptVisible = false
        resumeAll(false)
    }

    private func resumeAll(_ value: Bool) {
        let waiters = pending
        pending.removeAll()
        for c in waiters { c.resume(returning: value) }
    }
}
