import Foundation

/// Shared safe settings for competition creation and future seasons.
/// Old locally saved drafts decode with conservative defaults.
enum ATHLTHCompetitionUnlock: String, Codable, CaseIterable, Identifiable {
    case interval, everyoneFinished
    var id: String { rawValue }
    var title: String {
        switch self {
        case .interval: return "Etter valgt tidsrom"
        case .everyoneFinished: return "Når alle har gjennomført"
        }
    }
}

enum ATHLTHCompetitionIntervalUnit: String, Codable, CaseIterable, Identifiable {
    case minute, hour, day, month
    var id: String { rawValue }
    var title: String {
        switch self {
        case .minute: return "Minutt"
        case .hour: return "Time"
        case .day: return "Dag"
        case .month: return "Måned"
        }
    }
    /// Calendar months must be evaluated by the server as calendar
    /// intervals, never approximated as a fixed 30-day duration.
    var maximumCount: Int {
        switch self {
        case .minute: return 10_080
        case .hour: return 720
        case .day: return 90
        case .month: return 12
        }
    }
}

enum ATHLTHCompetitionInvitePermission: String, Codable, CaseIterable, Identifiable {
    case admin, participants
    var id: String { rawValue }
    var title: String {
        self == .admin ? "Kun arrangør" : "Alle godkjente deltakere"
    }
}

enum ATHLTHCompetitionJoinApproval: String, Codable, CaseIterable, Identifiable {
    case open, participants, admin
    var id: String { rawValue }
    var title: String {
        switch self {
        case .open: return "Åpen – ingen ekstra godkjenning"
        case .participants: return "Alle deltakere må godkjenne"
        case .admin: return "Kun arrangøren godkjenner"
        }
    }
}

/// Rewards and penalties are a voluntary social agreement, not transfers,
/// obligations or automated punishments. Participants must acknowledge them
/// together with the final competition rules before any workout counts.
struct ATHLTHCompetitionAgreement: Codable, Equatable {
    var allowed: String = ""
    var prohibited: String = ""
    var firstPrize: String = ""
    var secondPrize: String = ""
    var thirdPrize: String = ""
    var loserConsequence: String = ""

    var hasTerms: Bool {
        [allowed, prohibited, firstPrize, secondPrize,
         thirdPrize, loserConsequence].contains {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
    var isValid: Bool {
        [allowed, prohibited, firstPrize, secondPrize,
         thirdPrize, loserConsequence].allSatisfy { $0.count <= 500 }
    }
}

struct ATHLTHTournamentCompetitionSettings: Codable, Equatable {
    var startsAt: Date? = nil
    var unlock: ATHLTHCompetitionUnlock = .interval
    var every: Int = 7
    var unit: ATHLTHCompetitionIntervalUnit = .day
    var completionHours: Int = 48
    var invitationPermission: ATHLTHCompetitionInvitePermission = .admin
    var joinApproval: ATHLTHCompetitionJoinApproval = .admin
    var agreement: ATHLTHCompetitionAgreement = .init()

    var isValid: Bool {
        let now = Date()
        let validStart = startsAt.map {
            $0 >= now.addingTimeInterval(-120) &&
            $0 <= now.addingTimeInterval(366 * 86_400)
        } ?? true
        return validStart &&
            (1...unit.maximumCount).contains(every) &&
            ATHLTHTournamentCadence.completionHours.contains(completionHours) &&
            agreement.isValid
    }

    var requiresExplicitConsent: Bool {
        agreement.hasTerms
    }

    /// Server scores a missed exercise as zero after its completion deadline.
    /// This is intentionally not a user-disableable setting.
    var missedExercisePoints: Int { 0 }
}
