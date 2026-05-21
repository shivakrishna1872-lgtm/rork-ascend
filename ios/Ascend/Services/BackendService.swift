import Foundation
import SwiftUI

/// Talks to the Ascend Cloudflare Worker (Hub Durable Object).
/// Identifies the current user by Apple user id (preferred) or a stable
/// per-install UUID as a fallback. All endpoints are stateless from the
/// client's perspective — the server is the source of truth.
@MainActor
@Observable
final class BackendService {
    static let shared = BackendService()

    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 15
        cfg.timeoutIntervalForResource = 20
        return URLSession(configuration: cfg)
    }()

    private let fallbackUserIdKey = "ascend.fallbackUserId"

    private var baseURL: String {
        Config.EXPO_PUBLIC_RORK_FUNCTIONS_URL.trimmingCharacters(in: .init(charactersIn: "/"))
    }

    /// Stable identifier for the current user. Apple Sign-In id wins; falls
    /// back to a per-install UUID so guests still appear on rankings.
    var currentUserId: String {
        if let id = AuthService.shared.appleUserId, !id.isEmpty { return id }
        if let cached = UserDefaults.standard.string(forKey: fallbackUserIdKey),
           !cached.isEmpty { return cached }
        let new = UUID().uuidString
        UserDefaults.standard.set(new, forKey: fallbackUserIdKey)
        return new
    }

    // MARK: - Requests

    private func makeRequest(_ path: String, method: String = "GET",
                             body: [String: Any]? = nil) -> URLRequest? {
        guard let url = URL(string: baseURL + path) else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(currentUserId, forHTTPHeaderField: "X-Ascend-User")
        if let body { req.httpBody = try? JSONSerialization.data(withJSONObject: body) }
        return req
    }

    private func send<T: Decodable>(_ req: URLRequest, as _: T.Type) async throws -> T {
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw BackendError.http((response as? HTTPURLResponse)?.statusCode ?? 0, body)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    // MARK: - User sync

    /// Push the current user's profile snapshot to the server. Safe to call
    /// repeatedly; the worker upserts by id.
    @discardableResult
    func upsertUser(name: String, xp: Int, streak: Int, tier: String) async -> Bool {
        let payload: [String: Any] = [
            "userId": currentUserId,
            "name": name,
            "xp": xp,
            "streak": streak,
            "tier": tier,
            "avatarSeed": String(name.prefix(2)).uppercased(),
        ]
        guard let req = makeRequest("/users/upsert", method: "POST", body: payload) else {
            return false
        }
        do {
            _ = try await session.data(for: req)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Rankings

    func fetchGlobalRankings() async throws -> GlobalRankings {
        guard let req = makeRequest("/rankings/global?userId=\(currentUserId)") else {
            throw BackendError.badURL
        }
        let res: RankingsEnvelope = try await send(req, as: RankingsEnvelope.self)
        return GlobalRankings(top: res.top, me: res.me, total: res.total)
    }

    // MARK: - Circles

    func listCircles() async throws -> [RemoteCircle] {
        guard let req = makeRequest("/circles?userId=\(currentUserId)") else {
            throw BackendError.badURL
        }
        let res: CirclesListEnvelope = try await send(req, as: CirclesListEnvelope.self)
        return res.circles
    }

    func createCircle(name: String, accent: String, ownerName: String) async throws -> RemoteCircle {
        let body: [String: Any] = [
            "name": name, "accent": accent,
            "ownerId": currentUserId, "ownerName": ownerName,
        ]
        guard let req = makeRequest("/circles", method: "POST", body: body) else {
            throw BackendError.badURL
        }
        let res: CircleEnvelope = try await send(req, as: CircleEnvelope.self)
        guard let c = res.circle else { throw BackendError.empty }
        return c
    }

    func joinCircle(code: String, userName: String) async throws -> RemoteCircle {
        let body: [String: Any] = [
            "code": code.uppercased(),
            "userId": currentUserId,
            "userName": userName,
        ]
        guard let req = makeRequest("/circles/join", method: "POST", body: body) else {
            throw BackendError.badURL
        }
        let res: CircleEnvelope = try await send(req, as: CircleEnvelope.self)
        guard let c = res.circle else { throw BackendError.codeNotFound }
        return c
    }

    func fetchCircle(id: String) async throws -> RemoteCircle {
        guard let req = makeRequest("/circles/\(id)?userId=\(currentUserId)") else {
            throw BackendError.badURL
        }
        let res: CircleEnvelope = try await send(req, as: CircleEnvelope.self)
        guard let c = res.circle else { throw BackendError.empty }
        return c
    }

    func leaveCircle(id: String) async throws {
        let body: [String: Any] = ["userId": currentUserId]
        guard let req = makeRequest("/circles/\(id)/leave", method: "POST", body: body) else {
            throw BackendError.badURL
        }
        _ = try await session.data(for: req)
    }

    func deleteCircle(id: String) async throws {
        guard let req = makeRequest("/circles/\(id)?userId=\(currentUserId)", method: "DELETE") else {
            throw BackendError.badURL
        }
        _ = try await session.data(for: req)
    }
}

// MARK: - Models

nonisolated struct GlobalRankings: Equatable {
    let top: [RankedUser]
    let me: RankedUser?
    let total: Int
}

nonisolated struct RankedUser: Codable, Identifiable, Equatable, Hashable {
    let rank: Int
    let id: String
    let name: String
    let xp: Int
    let streak: Int
    let tier: String
    let avatarSeed: String
    /// Only emitted by `/circles/*` endpoints; `nil` for global rankings rows.
    let isMe: Bool?

    enum CodingKeys: String, CodingKey {
        case rank, id, name, xp, streak, tier, avatarSeed, isMe
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rank = try c.decodeIfPresent(Int.self, forKey: .rank) ?? 0
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        xp = try c.decodeIfPresent(Int.self, forKey: .xp) ?? 0
        streak = try c.decodeIfPresent(Int.self, forKey: .streak) ?? 0
        tier = try c.decodeIfPresent(String.self, forKey: .tier) ?? "bronze"
        avatarSeed = try c.decodeIfPresent(String.self, forKey: .avatarSeed) ?? ""
        isMe = try c.decodeIfPresent(Bool.self, forKey: .isMe)
    }
}

nonisolated struct RemoteCircle: Codable, Identifiable, Equatable, Hashable {
    let id: String
    let name: String
    let accent: String
    let code: String
    let ownerId: String
    let createdAt: Double
    let memberCount: Int
    let isOwner: Bool
    let members: [RankedUser]
}

private nonisolated struct RankingsEnvelope: Decodable {
    let ok: Bool
    let total: Int
    let top: [RankedUser]
    let me: RankedUser?
}

private nonisolated struct CirclesListEnvelope: Decodable {
    let ok: Bool
    let circles: [RemoteCircle]
}

private nonisolated struct CircleEnvelope: Decodable {
    let ok: Bool
    let circle: RemoteCircle?
}

nonisolated enum BackendError: LocalizedError {
    case badURL
    case http(Int, String)
    case empty
    case codeNotFound

    var errorDescription: String? {
        switch self {
        case .badURL: "Backend URL is not configured."
        case .http(let s, _): "Server error (\(s))."
        case .empty: "Empty response from server."
        case .codeNotFound: "Invite code not found."
        }
    }
}
