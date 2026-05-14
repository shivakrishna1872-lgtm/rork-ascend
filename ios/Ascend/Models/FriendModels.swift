import Foundation
import SwiftData
import SwiftUI

/// Muted accent palette for groups — never neon.
enum GroupAccent: String, CaseIterable, Codable, Identifiable {
    case steel, ash, copper, plum, sand, sage, slate, rose
    var id: String { rawValue }

    var color: Color {
        switch self {
        case .steel:  Color(red: 0.45, green: 0.62, blue: 0.82)
        case .ash:    Color(red: 0.55, green: 0.72, blue: 0.62)
        case .copper: Color(red: 0.82, green: 0.55, blue: 0.38)
        case .plum:   Color(red: 0.62, green: 0.48, blue: 0.72)
        case .sand:   Color(red: 0.82, green: 0.72, blue: 0.48)
        case .sage:   Color(red: 0.50, green: 0.68, blue: 0.55)
        case .slate:  Color(red: 0.52, green: 0.58, blue: 0.66)
        case .rose:   Color(red: 0.82, green: 0.58, blue: 0.62)
        }
    }

    var title: String {
        switch self {
        case .steel:  "Steel"
        case .ash:    "Ash"
        case .copper: "Copper"
        case .plum:   "Plum"
        case .sand:   "Sand"
        case .sage:   "Sage"
        case .slate:  "Slate"
        case .rose:   "Rose"
        }
    }
}

@Model
final class FriendGroup {
    @Attribute(.unique) var id: UUID
    var name: String
    var accentRaw: String
    var inviteCode: String
    var createdAt: Date
    @Relationship(deleteRule: .cascade, inverse: \Friend.group) var members: [Friend]

    init(
        id: UUID = UUID(),
        name: String,
        accent: GroupAccent = .steel,
        inviteCode: String = FriendGroup.generateCode(),
        createdAt: Date = .now,
        members: [Friend] = []
    ) {
        self.id = id
        self.name = name
        self.accentRaw = accent.rawValue
        self.inviteCode = inviteCode
        self.createdAt = createdAt
        self.members = members
    }

    var accent: GroupAccent { GroupAccent(rawValue: accentRaw) ?? .steel }

    static func generateCode() -> String {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return String((0..<6).map { _ in alphabet.randomElement()! })
    }

    var inviteURL: URL {
        URL(string: "https://aether.app/join/\(inviteCode)")!
    }

    struct RankedMember: Identifiable {
        var id: UUID
        var name: String
        var xp: Int
        var tier: Tier
        var isMe: Bool
        var isPending: Bool
    }

    func rankedMembers(currentUserXP: Int, currentUserName: String) -> [RankedMember] {
        var entries: [RankedMember] = members.map { m in
            RankedMember(id: m.id,
                         name: m.displayName,
                         xp: m.xp,
                         tier: Tier.forXP(m.xp),
                         isMe: false,
                         isPending: m.isPending)
        }
        entries.append(RankedMember(
            id: UUID(),
            name: currentUserName,
            xp: currentUserXP,
            tier: Tier.forXP(currentUserXP),
            isMe: true,
            isPending: false
        ))
        return entries
            .filter { !$0.isPending }
            .sorted { $0.xp > $1.xp }
    }
}

enum FriendSource: String, Codable {
    case manual
    case contact
    case link
}

@Model
final class Friend {
    @Attribute(.unique) var id: UUID
    var displayName: String
    var initials: String
    var phoneOrEmail: String
    var sourceRaw: String
    var xp: Int
    var isPending: Bool
    var joinedAt: Date
    var group: FriendGroup?

    init(
        id: UUID = UUID(),
        displayName: String,
        phoneOrEmail: String = "",
        source: FriendSource = .manual,
        xp: Int = 0,
        isPending: Bool = false,
        joinedAt: Date = .now
    ) {
        self.id = id
        self.displayName = displayName
        self.initials = Self.initials(from: displayName)
        self.phoneOrEmail = phoneOrEmail
        self.sourceRaw = source.rawValue
        self.xp = xp
        self.isPending = isPending
        self.joinedAt = joinedAt
    }

    var source: FriendSource { FriendSource(rawValue: sourceRaw) ?? .manual }

    static func initials(from name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        return parts.map { String($0.first ?? "?") }.joined().uppercased()
    }

    var tier: Tier { Tier.forXP(xp) }
}
