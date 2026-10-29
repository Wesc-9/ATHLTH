import Foundation

/// Accepted activities reserve time; unanswered invitations remain clearly
/// tentative and must never be mistaken for accepted participation.
enum ATHLTHCalendarParticipationPolicy {
    enum Attendance: Equatable {
        case confirmed
        case tentative

        var isTentative: Bool { self == .tentative }
    }

    static func community(
        eventStatus: String,
        endsAt: Date,
        attendance: CommunityEventAttendance?,
        isCreator: Bool,
        now: Date = Date()
    ) -> Attendance? {
        guard (eventStatus == "upcoming" || eventStatus == "live"),
              endsAt >= now else { return nil }
        if isCreator { return .confirmed }
        switch attendance {
        case .going: return .confirmed
        case .maybe: return .tentative
        case nil: return nil
        }
    }

    /// Joined club members may have been invited to a group gathering
    /// without replying; those events are tentative, never confirmed.
    static func club(
        eventStatus: String,
        endsAt: Date,
        rsvp: String?,
        now: Date = Date()
    ) -> Attendance? {
        guard (eventStatus == "upcoming" || eventStatus == "live"),
              endsAt >= now else { return nil }
        switch rsvp {
        case "going": return .confirmed
        case nil, "maybe", "waitlist": return .tentative
        default: return nil
        }
    }

    static func challenge(
        status: ATHLTHChallengeStatus,
        participantState: ChallengeParticipantState?,
        isCreator: Bool
    ) -> Attendance? {
        guard status == .invited ||
                status == .upcoming ||
                status == .active
        else { return nil }

        if isCreator { return .confirmed }
        switch participantState {
        case .accepted: return .confirmed
        case .invited: return .tentative
        default: return nil
        }
    }

    /// Plan-day offsets are relative to the first day of the plan, not to
    /// Monday. An explicit moved/scheduled start is the source of truth.
    static func scheduledDate(
        session: PlannedSession,
        planStart: Date,
        weekNumber: Int,
        dayIndex: Int,
        calendar: Calendar = .current
    ) -> Date? {
        if let scheduled = session.scheduledStart {
            return scheduled
        }
        let start = calendar.startOfDay(for: planStart)
        let offset = max(weekNumber - 1, 0) * 7 +
                     max(dayIndex - 1, 0)
        return calendar.date(byAdding: .day, value: offset, to: start)
    }

    /// Multi-day competitive challenge windows must not block an entire
    /// week in the user's Apple Calendar. Show a one-hour start reminder.
    static func challengeEnd(
        start: Date, explicitEnd: Date?
    ) -> Date {
        if let end = explicitEnd {
            let span = end.timeIntervalSince(start)
            if span >= 300 && span <= 6 * 3_600 { return end }
        }
        return start.addingTimeInterval(3_600)
    }
}
