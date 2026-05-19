import Foundation
import AuthenticationServices
import Security

/// Handles Apple Sign-In credential persistence and revocation.
/// We store only the Apple user ID + cached name/email (from first sign-in) in
/// Keychain so the user can be auto-signed-in on subsequent launches.
@MainActor
@Observable
final class AuthService {
    static let shared = AuthService()

    private let service = "app.rork.ascend.auth"
    private let userIdKey = "appleUserId"
    private let nameKey = "appleName"
    private let emailKey = "appleEmail"
    private let authCodeKey = "appleAuthCode"

    private(set) var appleUserId: String?
    private(set) var cachedName: String?
    private(set) var cachedEmail: String?

    private init() {
        self.appleUserId = Self.keychainRead("app.rork.ascend.auth", "appleUserId")
        self.cachedName = Self.keychainRead("app.rork.ascend.auth", "appleName")
        self.cachedEmail = Self.keychainRead("app.rork.ascend.auth", "appleEmail")
    }

    var isSignedIn: Bool { appleUserId != nil }

    /// Persist Apple credentials. Name/email are ONLY provided on the very first
    /// successful sign-in — we cache them so future launches don't need to ask.
    func store(userId: String, name: String?, email: String?, authorizationCode: String? = nil) {
        appleUserId = userId
        Self.keychainWrite(service, userIdKey, userId)
        if let name, !name.isEmpty {
            cachedName = name
            Self.keychainWrite(service, nameKey, name)
        }
        if let email, !email.isEmpty {
            cachedEmail = email
            Self.keychainWrite(service, emailKey, email)
        }
        if let authorizationCode, !authorizationCode.isEmpty {
            Self.keychainWrite(service, authCodeKey, authorizationCode)
        }
    }

    /// Apple-issued single-use authorization code captured on the most recent
    /// sign-in. Used server-side to mint a refresh_token and revoke it when
    /// the user deletes their account (App Store Guideline 5.1.1(v)).
    var authorizationCode: String? {
        Self.keychainRead(service, authCodeKey)
    }

    /// Verify the stored Apple ID is still valid for this device.
    /// Returns `true` when the credential is authorized; signs out on revoke/notFound.
    func refreshCredentialState() async -> Bool {
        guard let userId = appleUserId else { return false }
        let provider = ASAuthorizationAppleIDProvider()
        return await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            provider.getCredentialState(forUserID: userId) { [weak self] state, _ in
                Task { @MainActor in
                    switch state {
                    case .authorized:
                        cont.resume(returning: true)
                    case .revoked, .notFound, .transferred:
                        self?.signOut()
                        cont.resume(returning: false)
                    @unknown default:
                        cont.resume(returning: true)
                    }
                }
            }
        }
    }

    func signOut() {
        appleUserId = nil
        cachedName = nil
        cachedEmail = nil
        Self.keychainDelete(service, userIdKey)
        Self.keychainDelete(service, nameKey)
        Self.keychainDelete(service, emailKey)
        Self.keychainDelete(service, authCodeKey)
    }

    /// Calls the backend to revoke this user's Apple refresh token so the
    /// account is fully unlinked from Apple's side (required for deletion to
    /// pass App Review). Returns true on success, false if there's nothing
    /// to revoke or the call failed — caller should still proceed with the
    /// local wipe in either case.
    func revokeAppleTokenIfPossible() async -> Bool {
        guard let code = authorizationCode, !code.isEmpty else { return false }
        let base = Config.EXPO_PUBLIC_RORK_FUNCTIONS_URL
        guard let url = URL(string: base.trimmingCharacters(in: .init(charactersIn: "/"))
                              + "/apple/revoke") else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 15
        let payload: [String: String] = ["authorizationCode": code]
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse else { return false }
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let ok = obj["ok"] as? Bool {
                return http.statusCode == 200 && ok
            }
            return (200..<300).contains(http.statusCode)
        } catch {
            return false
        }
    }

    // MARK: - Keychain helpers

    nonisolated private static func keychainWrite(_ service: String, _ account: String, _ value: String) {
        guard let data = value.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        var attrs = query
        attrs[kSecValueData as String] = data
        SecItemAdd(attrs as CFDictionary, nil)
    }

    nonisolated private static func keychainRead(_ service: String, _ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data,
              let str = String(data: data, encoding: .utf8) else { return nil }
        return str
    }

    nonisolated private static func keychainDelete(_ service: String, _ account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
