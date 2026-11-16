import Foundation

/// Display-only admin directory copy. Subscription tiers come from the
/// backend as internal codes and must never be presented as verification
/// badges or assumed to mean an active payment.
enum ATHLTHAdminDirectoryPresentation {
    enum Plan: Equatable {
        case plus
        case free
        case unknown
    }

    static func plan(for raw: String) -> Plan {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "athlth_plus": .plus
        case "free": .free
        default: .unknown
        }
    }

    static func planTitle(_ raw: String, norwegian: Bool) -> String {
        switch plan(for: raw) {
        case .plus: "ATHLTH+"
        case .free: norwegian ? "Gratis" : "Free"
        case .unknown: norwegian ? "Ukjent abonnement" : "Unknown plan"
        }
    }

    /// An expired trial is not a Plus subscription, even if its stored
    /// entitlement tier was originally athlth_plus.
    static func subscriptionLabel(
        tier: String, status: String, norwegian: Bool
    ) -> String {
        switch status {
        case "trialing":
            return norwegian ? "ATHLTH+ · Prøveperiode" : "ATHLTH+ · Trial"
        case "trial_expired":
            return norwegian ? "Utløpt prøveperiode" : "Trial expired"
        case "expired", "revoked", "cancelled":
            return norwegian ? "Utgått abonnement" : "Subscription expired"
        case "admin_grant":
            return norwegian ? "ATHLTH+ · Tildelt" : "ATHLTH+ · Granted"
        default:
            return planTitle(tier, norwegian: norwegian)
        }
    }

    static func accountStatusTitle(
        _ raw: String, norwegian: Bool
    ) -> String {
        switch raw {
        case "active": return norwegian ? "Aktiv" : "Active"
        case "suspended": return norwegian ? "Deaktivert" : "Suspended"
        default: return norwegian ? "Ukjent kontostatus" : "Unknown account status"
        }
    }

    static func roleTitle(_ raw: String, norwegian: Bool) -> String {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "owner": norwegian ? "Eier" : "Owner"
        case "admin": norwegian ? "Administrator" : "Administrator"
        case "user": norwegian ? "Bruker" : "User"
        default: norwegian ? "Ukjent rolle" : "Unknown role"
        }
    }

    static func displayName(_ name: String?, username: String?) -> String {
        if let name = name?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty { return name }
        if let username = username?.trimmingCharacters(in: .whitespacesAndNewlines),
           !username.isEmpty { return username }
        return "—"
    }

    static func initials(_ name: String?, username: String?) -> String {
        let value = displayName(name, username: username)
        guard value != "—" else { return "?" }
        let parts = value.split(whereSeparator: \.isWhitespace)
        return String(parts.prefix(2).compactMap(\.first)).uppercased()
    }
}
