import Foundation

/// An inbox event is historical evidence that an invitation was sent,
/// not evidence that the underlying workout is still open. Prefer the
/// account's current workout session state over the event's old title.
enum ATHLTHNotificationWorkoutInvitationStatus: Equatable {
    case actionable
    case accepted
    case declined
    case cancelled
    case completed
    case unverified

    var localizedLabel: String {
        switch self {
        case .actionable:
            return ATHLTHLocalization.choose(english: "Invitation", norwegian: "Invitasjon")
        case .accepted:
            return ATHLTHLocalization.choose(english: "Accepted", norwegian: "Godtatt")
        case .declined:
            return ATHLTHLocalization.choose(english: "Declined", norwegian: "Avslått")
        case .cancelled:
            return ATHLTHLocalization.choose(english: "Cancelled", norwegian: "Avlyst")
        case .completed:
            return ATHLTHLocalization.choose(english: "Finished", norwegian: "Avsluttet")
        case .unverified:
            return ATHLTHLocalization.choose(
                english: "Invitation unavailable or not verified",
                norwegian: "Invitasjonen er ikke tilgjengelig eller bekreftet"
            )
        }
    }

    var systemImage: String {
        switch self {
        case .actionable: "envelope"
        case .accepted: "checkmark.circle"
        case .declined: "minus.circle"
        case .cancelled: "xmark.circle"
        case .completed: "checkmark.seal"
        case .unverified: "questionmark.circle"
        }
    }
}

enum ATHLTHNotificationWorkoutInvitationPolicy {
    static func status(
        session: SocialWorkoutSessionRecord?,
        participant: SocialWorkoutParticipantRecord?,
        now: Date = Date()
    ) -> ATHLTHNotificationWorkoutInvitationStatus {
        status(
            sessionStatus: session?.status,
            participantState: participant?.state,
            scheduledStart: session?.invitePayload?.workout.scheduledStart,
            isPlanned: session?.resolvedWorkoutPhase == .planned,
            now: now
        )
    }

    /// Do not call a missing entry "deleted": a limited list read or offline
    /// device can simply lack the source session. Only an explicit cancelled
    /// server status merits the word "Avlyst".
    static func status(
        sessionStatus: SocialWorkoutSessionStatus?,
        participantState: SocialWorkoutParticipantState?,
        scheduledStart: Date? = nil,
        isPlanned: Bool = true,
        now: Date = Date()
    ) -> ATHLTHNotificationWorkoutInvitationStatus {
        guard let sessionStatus else { return .unverified }

        switch sessionStatus {
        case .cancelled: return .cancelled
        case .completed: return .completed
        case .active:
            // Only pending planned invitations expire, not accepted sessions.
            if participantState == .invited, isPlanned,
               let scheduledStart, scheduledStart <= now {
                return .cancelled
            }
            switch participantState {
            case .invited: return .actionable
            case .accepted: return .accepted
            case .declined: return .declined
            case .creator, nil: return .unverified
            }
        }
    }
}
