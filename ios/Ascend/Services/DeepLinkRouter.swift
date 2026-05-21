import Foundation
import SwiftUI

/// Pending deep-link state. Set when the app is launched/woken via a
/// universal link or custom URL scheme; consumed by `CirclesView` to
/// auto-open the join sheet with the code prefilled.
@MainActor
@Observable
final class DeepLinkRouter {
    static let shared = DeepLinkRouter()

    var pendingJoinCode: String? = nil

    private init() {}

    /// Parse a URL into an invite code if it matches one of our schemes.
    /// Supported:
    ///   - `https://<host>/join/<CODE>`
    ///   - `ascend://join/<CODE>`
    func handle(url: URL) -> Bool {
        let path = url.path
        if path.hasPrefix("/join/") {
            let code = String(path.dropFirst("/join/".count))
            return setCode(code)
        }
        if url.scheme?.lowercased() == "ascend", url.host?.lowercased() == "join" {
            // ascend://join/CODE → host = "join", path = "/CODE"
            let code = url.path.trimmingCharacters(in: .init(charactersIn: "/"))
            return setCode(code)
        }
        if url.scheme?.lowercased() == "ascend", url.path.hasPrefix("/join/") {
            return setCode(String(url.path.dropFirst("/join/".count)))
        }
        return false
    }

    @discardableResult
    private func setCode(_ raw: String) -> Bool {
        let cleaned = raw.uppercased().filter { $0.isLetter || $0.isNumber }
        guard cleaned.count == 6 else { return false }
        pendingJoinCode = cleaned
        // Make sure the Circles tab is visible so the user actually sees the join sheet.
        NotificationCenter.default.post(name: .switchTab, object: AppTab.circles)
        return true
    }

    func consume() -> String? {
        let c = pendingJoinCode
        pendingJoinCode = nil
        return c
    }
}

