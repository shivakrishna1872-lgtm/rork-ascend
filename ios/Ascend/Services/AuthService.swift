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
    func store(userId: String, name: String?, email: String?) {
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
