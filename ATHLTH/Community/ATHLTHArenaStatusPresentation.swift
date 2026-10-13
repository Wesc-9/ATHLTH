import SwiftUI

/// One display-only vocabulary for the Arena overview, competitions,
/// results and seasons. Business status and authorization stay on the server.
enum ATHLTHArenaStatusKind: Equatable {
    case active
    case ready
    case waiting
    case needsReview
    case completed
    case upcoming
    case unavailable

    var title: String {
        switch self {
        case .active:
            return ATHLTHLocalization.choose(english: "IN PROGRESS", norwegian: "PÅGÅR")
        case .ready:
            return ATHLTHLocalization.choose(english: "READY", norwegian: "KLAR")
        case .waiting:
            return ATHLTHLocalization.choose(english: "AWAITING", norwegian: "AVVENTER")
        case .needsReview:
            return ATHLTHLocalization.choose(english: "REVIEW", norwegian: "KONTROLL")
        case .completed:
            return ATHLTHLocalization.choose(english: "COMPLETED", norwegian: "FULLFØRT")
        case .upcoming:
            return ATHLTHLocalization.choose(english: "UPCOMING", norwegian: "KOMMENDE")
        case .unavailable:
            return ATHLTHLocalization.choose(english: "UNRESOLVED", norwegian: "UAVKLART")
        }
    }

    var symbol: String {
        switch self {
        case .active: return "figure.run"
        case .ready: return "flag.checkered"
        case .waiting: return "clock"
        case .needsReview: return "exclamationmark.circle"
        case .completed: return "checkmark.seal"
        case .upcoming: return "calendar"
        case .unavailable: return "questionmark.circle"
        }
    }

    var foreground: Color {
        switch self {
        case .active: return ATHLTHArenaLightStyle.ink
        case .ready: return ATHLTHArenaLightStyle.warmGold
        case .waiting: return ATHLTHArenaLightStyle.warmGold
        case .needsReview: return .orange
        case .completed: return ATHLTHArenaLightStyle.secondary
        case .upcoming: return ATHLTHArenaLightStyle.warmGold
        case .unavailable: return ATHLTHArenaLightStyle.secondary
        }
    }

    var background: Color {
        switch self {
        case .active: return ATHLTHArenaLightStyle.soft
        case .ready: return ATHLTHArenaLightStyle.warmGold.opacity(0.11)
        case .waiting, .upcoming:
            return ATHLTHArenaLightStyle.warmGold.opacity(0.11)
        case .needsReview: return Color.orange.opacity(0.10)
        case .completed, .unavailable: return ATHLTHArenaLightStyle.soft
        }
    }
}

enum ATHLTHArenaStatusPresentation {
    static func series(
        status: String,
        deadlinePassed: Bool = false,
        unresolved: Bool = false
    ) -> ATHLTHArenaStatusKind {
        // A missed deadline or disputed result must never appear "completed".
        if deadlinePassed || unresolved { return .needsReview }
        switch status {
        case "active": return .active
        case "draft": return .waiting
        case "completed": return .completed
        case "cancelled", "canceled": return .unavailable
        default: return .unavailable
        }
    }

    static func result(status: String) -> ATHLTHArenaStatusKind {
        switch status {
        case "approved": return .completed
        case "pending": return .waiting
        case "rejected", "expired", "unresolved": return .needsReview
        default: return .unavailable
        }
    }

    static func liveRace(
        status: String,
        requiresResponse: Bool = false
    ) -> ATHLTHArenaStatusKind {
        if requiresResponse { return .needsReview }
        switch status {
        case "accepted": return .ready
        case "active", "running": return .active
        case "pending": return .waiting
        case "completed", "finished": return .completed
        default: return .unavailable
        }
    }
}

/// Compact and accessible. This view communicates a status; it never
/// performs actions or implies that points have been awarded.
struct ATHLTHArenaStatusPill: View {
    let kind: ATHLTHArenaStatusKind
    var title: String? = nil

    var body: some View {
        Label(title ?? kind.title, systemImage: kind.symbol)
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.35)
            .foregroundStyle(kind.foreground)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(kind.background, in: Capsule())
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityElement(children: .combine)
    }
}
