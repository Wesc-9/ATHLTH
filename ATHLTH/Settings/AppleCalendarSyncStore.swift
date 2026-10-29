import EventKit
import Foundation
import UIKit

@MainActor
final class AppleCalendarSyncStore: ObservableObject {
    @Published private(set) var authorizationStatus:
        EKAuthorizationStatus
    @Published private(set) var isEnabled: Bool
    @Published private(set) var isSyncing = false
    @Published private(set) var calendarIdentifier: String?
    @Published private(set) var lastSyncedAt: Date?
    @Published private(set) var lastSyncWorkoutCount: Int?
    @Published private(set) var lastSyncTentativeCount: Int?
    @Published private(set) var lastSyncEventCount: Int?
    @Published private(set) var defaultStartHour: Int
    @Published private(set) var defaultStartMinute: Int
    @Published var errorMessage: String?

    let calendarName = "ATHLTH"

    private let eventStore = EKEventStore()
    private let defaults: UserDefaults
    private var pendingSnapshot: CalendarSyncSnapshot?

    private struct CalendarSyncSnapshot {
        let plan: TrainingPlan?
        let standaloneSessions: [PlannedSession]
        let communityEvents: [CommunityEventItem]
        let groupEvents: [CommunityGroupEventRecord]
        let groupEventRSVPs: [CommunityGroupEventRSVPRecord]
        let challenges: [ATHLTHChallenge]
        let currentUserID: UUID?
    }

    private struct SyncSummary {
        let workouts: Int
        let tentative: Int
        let total: Int
    }

    private enum CalendarAttendanceState {
        case going
        case maybe
        case unanswered
        case waitlist

        var titlePrefix: String? {
            switch self {
            case .going: return nil
            case .maybe, .unanswered, .waitlist:
                return ATHLTHLocalization.choose(
                    english: "Tentative", norwegian: "Foreløpig"
                )
            }
        }

        var noteLabel: String {
            switch self {
            case .going:
                return "Going"
            case .maybe:
                return "Maybe"
            case .unanswered:
                return "No response"
            case .waitlist:
                return "Waitlist"
            }
        }
    }

    private enum Key {
        static let enabled =
            "calendarSync.enabled"
        static let calendarIdentifier =
            "calendarSync.calendarIdentifier"
        static let lastSyncedAt =
            "calendarSync.lastSyncedAt"
        static let defaultStartHour =
            "calendarSync.defaultStartHour"
        static let defaultStartMinute =
            "calendarSync.defaultStartMinute"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        authorizationStatus =
            EKEventStore.authorizationStatus(
                for: .event
            )
        isEnabled =
            defaults.object(
                forKey: Key.enabled
            ) as? Bool ?? false
        calendarIdentifier =
            defaults.string(
                forKey: Key.calendarIdentifier
            )
        lastSyncedAt =
            defaults.object(
                forKey: Key.lastSyncedAt
            ) as? Date
        defaultStartHour =
            defaults.object(
                forKey: Key.defaultStartHour
            ) as? Int ?? 18
        defaultStartMinute =
            defaults.object(
                forKey: Key.defaultStartMinute
            ) as? Int ?? 0

        recoverCalendarStateIfNeeded()
    }

    var hasFullAccess: Bool {
        switch authorizationStatus {
        case .authorized, .fullAccess:
            return true
        default:
            return false
        }
    }

    var authorizationTitle: String {
        switch authorizationStatus {
        case .notDetermined:
            return "Not connected"
        case .restricted:
            return "Restricted"
        case .denied:
            return "Access denied"
        case .writeOnly:
            return "Write only"
        case .authorized, .fullAccess:
            return "Connected"
        @unknown default:
            return "Unknown"
        }
    }

    var calendarExists: Bool {
        guard let calendarIdentifier else {
            return false
        }

        return eventStore.calendar(
            withIdentifier: calendarIdentifier
        ) != nil
    }

    func refreshAuthorizationStatus() {
        authorizationStatus =
            EKEventStore.authorizationStatus(
                for: .event
            )

        recoverCalendarStateIfNeeded()
    }

    private func recoverCalendarStateIfNeeded() {
        guard hasFullAccess else {
            return
        }

        let existingCalendar: EKCalendar?

        if let calendarIdentifier,
           let calendar =
                eventStore.calendar(
                    withIdentifier:
                        calendarIdentifier
                ),
           calendar.allowsContentModifications {
            existingCalendar = calendar
        } else {
            existingCalendar =
                eventStore
                    .calendars(for: .event)
                    .first(where: {
                        $0.title == calendarName &&
                        $0.allowsContentModifications
                    })

            if let existingCalendar {
                saveCalendarIdentifier(
                    existingCalendar
                        .calendarIdentifier
                )
            }
        }

        // Respect an explicit user choice to turn Calendar sync off.
        // Only self-heal when the preference key itself disappeared while
        // iOS still has full access and the ATHLTH calendar still exists.
        guard defaults.object(
            forKey: Key.enabled
        ) == nil,
        existingCalendar != nil
        else {
            return
        }

        isEnabled = true
        persistEnabled()
    }

    func enable(
        plan: TrainingPlan?,
        standaloneSessions: [PlannedSession] = [],
        communityEvents: [CommunityEventItem] = [],
        groupEvents: [CommunityGroupEventRecord] = [],
        groupEventRSVPs: [CommunityGroupEventRSVPRecord] = [],
        challenges: [ATHLTHChallenge] = [],
        currentUserID: UUID? = nil
    ) async {
        errorMessage = nil

        do {
            let granted =
                try await requestFullAccessIfNeeded()

            guard granted else {
                isEnabled = false
                persistEnabled()
                return
            }

            _ = try ensureCalendar()
            isEnabled = true
            persistEnabled()

            await sync(
                plan: plan,
                standaloneSessions: standaloneSessions,
                communityEvents: communityEvents,
                groupEvents: groupEvents,
                groupEventRSVPs: groupEventRSVPs,
                challenges: challenges,
                currentUserID: currentUserID
            )
        } catch {
            isEnabled = false
            persistEnabled()
            errorMessage =
                error.localizedDescription
        }
    }

    func disable() {
        isEnabled = false
        persistEnabled()
    }

    var defaultStartTime: Date {
        let calendar = Calendar.current
        let base = calendar.startOfDay(for: Date())

        return calendar.date(
            bySettingHour: defaultStartHour,
            minute: defaultStartMinute,
            second: 0,
            of: base
        ) ?? base
    }

    func setDefaultStartTime(_ date: Date) {
        let components = Calendar.current.dateComponents(
            [.hour, .minute],
            from: date
        )

        defaultStartHour = components.hour ?? 18
        defaultStartMinute = components.minute ?? 0

        defaults.set(
            defaultStartHour,
            forKey: Key.defaultStartHour
        )
        defaults.set(
            defaultStartMinute,
            forKey: Key.defaultStartMinute
        )
    }

    /// Adds or refreshes one Community event in the ATHLTH calendar
    /// without enabling full automatic calendar sync.
    @discardableResult
    func addCommunityEvent(
        _ item: CommunityEventItem,
        currentUserID: UUID
    ) async -> Bool {
        errorMessage = nil

        do {
            let granted =
                try await requestFullAccessIfNeeded()

            guard granted else {
                return false
            }

            let calendar =
                try ensureCalendar()
            let key =
                managedKey(
                    type: "event",
                    id: item.id
                )
            let existing =
                managedEvents(
                    in: calendar
                )
                .first {
                    managedKey(
                        from: $0
                    ) == key
                }
            let event =
                existing ??
                EKEvent(
                    eventStore: eventStore
                )

            let attendance:
                CalendarAttendanceState

            if item.event.creatorID ==
                currentUserID {
                attendance = .going
            } else if item
                .participantRows
                .first(
                    where: {
                        $0.userID ==
                            currentUserID
                    }
                )?
                .attendanceStatus ==
                .maybe {
                attendance = .maybe
            } else {
                attendance = .going
            }

            configure(
                event,
                communityEvent: item,
                attendance: attendance,
                calendar: calendar
            )

            try eventStore.save(
                event,
                span: .thisEvent,
                commit: true
            )

            return true
        } catch {
            errorMessage =
                error.localizedDescription
            return false
        }
    }

    func syncIfEnabled(
        plan: TrainingPlan?,
        standaloneSessions: [PlannedSession] = [],
        communityEvents: [CommunityEventItem] = [],
        groupEvents: [CommunityGroupEventRecord] = [],
        groupEventRSVPs: [CommunityGroupEventRSVPRecord] = [],
        challenges: [ATHLTHChallenge] = [],
        currentUserID: UUID? = nil
    ) async {
        guard isEnabled else {
            return
        }

        refreshAuthorizationStatus()

        guard hasFullAccess else {
            errorMessage =
                "Calendar access is no longer available. Reconnect it in Settings."
            return
        }

        await sync(
            plan: plan,
            standaloneSessions: standaloneSessions,
            communityEvents: communityEvents,
            groupEvents: groupEvents,
            groupEventRSVPs: groupEventRSVPs,
            challenges: challenges,
            currentUserID: currentUserID
        )
    }

    func sync(
        plan: TrainingPlan?,
        standaloneSessions: [PlannedSession] = [],
        communityEvents: [CommunityEventItem] = [],
        groupEvents: [CommunityGroupEventRecord] = [],
        groupEventRSVPs: [CommunityGroupEventRSVPRecord] = [],
        challenges: [ATHLTHChallenge] = [],
        currentUserID: UUID? = nil
    ) async {
        let snapshot = CalendarSyncSnapshot(
            plan: plan,
            standaloneSessions: standaloneSessions,
            communityEvents: communityEvents,
            groupEvents: groupEvents,
            groupEventRSVPs: groupEventRSVPs,
            challenges: challenges,
            currentUserID: currentUserID
        )

        if isSyncing {
            pendingSnapshot = snapshot
            return
        }

        isSyncing = true
        errorMessage = nil

        do {
            let calendar = try ensureCalendar()
            let summary = try synchronize(
                snapshot: snapshot,
                calendar: calendar
            )
            lastSyncWorkoutCount = summary.workouts
            lastSyncTentativeCount = summary.tentative
            lastSyncEventCount = summary.total
            lastSyncedAt = Date()
            defaults.set(
                lastSyncedAt,
                forKey: Key.lastSyncedAt
            )
        } catch {
            errorMessage =
                error.localizedDescription
        }

        isSyncing = false

        if let pendingSnapshot {
            self.pendingSnapshot = nil
            await sync(
                plan: pendingSnapshot.plan,
                standaloneSessions: pendingSnapshot.standaloneSessions,
                communityEvents:
                    pendingSnapshot.communityEvents,
                groupEvents:
                    pendingSnapshot.groupEvents,
                groupEventRSVPs:
                    pendingSnapshot.groupEventRSVPs,
                challenges:
                    pendingSnapshot.challenges,
                currentUserID:
                    pendingSnapshot.currentUserID
            )
        }
    }

    func removeATHLTHCalendar() async {
        errorMessage = nil

        do {
            refreshAuthorizationStatus()

            guard hasFullAccess else {
                throw AppleCalendarSyncError
                    .calendarAccessRequired
            }

            if let calendarIdentifier,
               let calendar =
                eventStore.calendar(
                    withIdentifier:
                        calendarIdentifier
                ) {
                try eventStore.removeCalendar(
                    calendar,
                    commit: true
                )
            }

            self.calendarIdentifier = nil
            lastSyncedAt = nil
            lastSyncWorkoutCount = nil
            lastSyncEventCount = nil
            lastSyncTentativeCount = nil
            isEnabled = false

            defaults.removeObject(
                forKey: Key.calendarIdentifier
            )
            defaults.removeObject(
                forKey: Key.lastSyncedAt
            )
            persistEnabled()
        } catch {
            errorMessage =
                error.localizedDescription
        }
    }

    private func requestFullAccessIfNeeded()
        async throws -> Bool {
        refreshAuthorizationStatus()

        switch authorizationStatus {
        case .authorized, .fullAccess:
            return true

        case .notDetermined, .writeOnly:
            let granted =
                try await eventStore
                    .requestFullAccessToEvents()
            refreshAuthorizationStatus()
            return granted && hasFullAccess

        case .denied, .restricted:
            throw AppleCalendarSyncError
                .calendarAccessRequired

        @unknown default:
            throw AppleCalendarSyncError
                .calendarAccessRequired
        }
    }

    private func ensureCalendar()
        throws -> EKCalendar {
        if let calendarIdentifier,
           let existing =
            eventStore.calendar(
                withIdentifier:
                    calendarIdentifier
            ),
           existing.allowsContentModifications {
            return existing
        }

        // If iOS kept the calendar but UserDefaults was lost,
        // prefer reusing an editable ATHLTH calendar instead of
        // creating a duplicate.
        if let existing =
            eventStore
                .calendars(for: .event)
                .first(where: {
                    $0.title == calendarName &&
                    $0.allowsContentModifications
                }) {
            saveCalendarIdentifier(
                existing.calendarIdentifier
            )
            return existing
        }

        guard let source =
                preferredCalendarSource()
        else {
            throw AppleCalendarSyncError
                .noWritableCalendarSource
        }

        let calendar = EKCalendar(
            for: .event,
            eventStore: eventStore
        )
        calendar.title = calendarName
        calendar.source = source
        calendar.cgColor =
            UIColor.systemGreen.cgColor

        try eventStore.saveCalendar(
            calendar,
            commit: true
        )

        saveCalendarIdentifier(
            calendar.calendarIdentifier
        )

        return calendar
    }

    private func preferredCalendarSource()
        -> EKSource? {
        let iCloud = eventStore.sources.first {
            $0.title.localizedCaseInsensitiveContains(
                "icloud"
            )
        }

        if let iCloud {
            return iCloud
        }

        if let source =
            eventStore
                .defaultCalendarForNewEvents?
                .source {
            return source
        }

        return eventStore.sources.first {
            switch $0.sourceType {
            case .calDAV, .local, .exchange:
                return true
            default:
                return false
            }
        }
    }

    private func synchronize(
        snapshot: CalendarSyncSnapshot,
        calendar: EKCalendar
    ) throws -> SyncSummary {
        let existingEvents =
            managedEvents(in: calendar)

        var existingByKey:
            [String: EKEvent] = [:]
        var duplicateEvents:
            [EKEvent] = []

        for event in existingEvents {
            guard let key = managedKey(from: event)
            else {
                continue
            }

            if existingByKey[key] == nil {
                existingByKey[key] = event
            } else {
                duplicateEvents.append(event)
            }
        }

        var activeKeys = Set<String>()
        var syncedWorkouts = 0
        var tentativeEvents = 0

        if let plan = snapshot.plan {
            for (weekIndex, week) in plan.weeks.enumerated() {
                for day in week.days {
                    for session in day.sessions {
                        // A moved workout may be on a different day from its
                        // original plan slot. Explicit scheduledStart wins.
                        guard plan.startDate != nil ||
                                session.scheduledStart != nil,
                              let dayDate = ATHLTHCalendarParticipationPolicy
                                .scheduledDate(
                                    session: session,
                                    planStart: plan.startDate ?? plan.createdAt,
                                    weekNumber: weekIndex + 1,
                                    dayIndex: day.dayIndex
                                )
                        else { continue }

                        let key = managedKey(type: "session", id: session.id)
                        activeKeys.insert(key)
                        let event = existingByKey[key] ??
                            EKEvent(eventStore: eventStore)
                        configure(
                            event, session: session,
                            plan: plan, dayDate: dayDate, calendar: calendar
                        )
                        try eventStore.save(
                            event, span: .thisEvent, commit: false
                        )
                        syncedWorkouts += 1
                    }
                }
            }
        }

        // One-off workouts are scheduled without an active training plan.
        // They must be synced, edited and removed just like plan workouts.
        for session in snapshot.standaloneSessions {
            guard let start = session.scheduledStart else { continue }
            let key = managedKey(type: "standalone-session", id: session.id)
            activeKeys.insert(key)
            let event = existingByKey[key] ??
                EKEvent(eventStore: eventStore)
            configure(
                event, session: session,
                plan: nil, dayDate: start, calendar: calendar
            )
            try eventStore.save(
                event, span: .thisEvent, commit: false
            )
            syncedWorkouts += 1
        }

        if let currentUserID = snapshot.currentUserID {
            let now = Date()

            // A public event must belong to the athlete. An unanswered
            // public discovery item is not an invitation.
            for item in snapshot.communityEvents {
                let record = item.event
                let participant = item.participantRows.first {
                    $0.userID == currentUserID
                }
                guard let decision = ATHLTHCalendarParticipationPolicy.community(
                    eventStatus: record.status,
                    endsAt: record.endsAt ??
                        record.startsAt.addingTimeInterval(3_600),
                    attendance: participant?.attendanceStatus,
                    isCreator: record.creatorID == currentUserID,
                    now: now
                ) else { continue }
                let key = managedKey(type: "event", id: record.id)
                activeKeys.insert(key)
                let event = existingByKey[key] ?? EKEvent(eventStore: eventStore)
                configure(
                    event, communityEvent: item,
                    attendance: decision.isTentative ? .maybe : .going,
                    calendar: calendar
                )
                try eventStore.save(event, span: .thisEvent, commit: false)
                if decision.isTentative { tentativeEvents += 1 }
            }

            // Members with no response are shown as tentative, not as
            // confirmed attendees. A declined RSVP removes the old entry.
            for record in snapshot.groupEvents {
                let response = snapshot.groupEventRSVPs.first {
                    $0.eventID == record.id &&
                    $0.userID == currentUserID
                }?.status
                guard let decision = ATHLTHCalendarParticipationPolicy.club(
                    eventStatus: record.status,
                    endsAt: record.endsAt ??
                        record.startsAt.addingTimeInterval(3_600),
                    rsvp: response,
                    now: now
                ) else { continue }

                let attendance: CalendarAttendanceState
                if !decision.isTentative {
                    attendance = .going
                } else {
                    switch response {
                    case "maybe": attendance = .maybe
                    case "waitlist": attendance = .waitlist
                    default: attendance = .unanswered
                    }
                }

                let key = managedKey(type: "group-event", id: record.id)
                activeKeys.insert(key)
                let event = existingByKey[key] ?? EKEvent(eventStore: eventStore)
                configure(
                    event, groupEvent: record,
                    attendance: attendance, calendar: calendar
                )
                try eventStore.save(event, span: .thisEvent, commit: false)
                if decision.isTentative { tentativeEvents += 1 }
            }

            for challenge in snapshot.challenges {
                let participant = challenge.participants.first {
                    $0.userID == currentUserID
                }
                guard let decision = ATHLTHCalendarParticipationPolicy.challenge(
                    status: challenge.status,
                    participantState: participant?.state,
                    isCreator: challenge.creatorID == currentUserID
                ) else { continue }
                let attendance: CalendarAttendanceState =
                    decision.isTentative ? .unanswered : .going

                // An actual meetup has its own precise scheduled time and
                // place, separate from the challenge competition window.
                if let meetup = challenge.rules.meetup,
                   meetup.scheduledAt.addingTimeInterval(3_600) >= now {
                    let key = managedKey(
                        type: "challenge-meetup", id: challenge.id
                    )
                    activeKeys.insert(key)
                    let event = existingByKey[key] ??
                        EKEvent(eventStore: eventStore)
                    configure(
                        event, challengeMeetup: challenge,
                        attendance: attendance, calendar: calendar
                    )
                    try eventStore.save(
                        event, span: .thisEvent, commit: false
                    )
                    if decision.isTentative { tentativeEvents += 1 }
                }

                // Avoid two duplicate events if the workout and meetup
                // have essentially the same starting time.
                let overlapsMeetup = challenge.rules.meetup.map {
                    abs($0.scheduledAt.timeIntervalSince(
                        challenge.rules.startsAt
                    )) < 1_800
                } ?? false
                guard !overlapsMeetup,
                      ATHLTHCalendarParticipationPolicy.challengeEnd(
                        start: challenge.rules.startsAt,
                        explicitEnd: challenge.rules.endsAt
                      ) >= now
                else { continue }

                let key = managedKey(type: "challenge", id: challenge.id)
                activeKeys.insert(key)
                let event = existingByKey[key] ??
                    EKEvent(eventStore: eventStore)
                configure(
                    event, challenge: challenge,
                    attendance: attendance, calendar: calendar
                )
                try eventStore.save(event, span: .thisEvent, commit: false)
                if decision.isTentative { tentativeEvents += 1 }
            }
        }

        for event in existingEvents {
            guard let key = managedKey(from: event),
                  !activeKeys.contains(key)
            else {
                continue
            }

            try eventStore.remove(
                event,
                span: .thisEvent,
                commit: false
            )
        }

        for duplicate in duplicateEvents {
            try eventStore.remove(
                duplicate,
                span: .thisEvent,
                commit: false
            )
        }

        try eventStore.commit()

        // A successful EventKit commit is necessary but doesn't prove that
        // the expected workouts and invitations were actually written.
        // Re-read the ATHLTH calendar before reporting a successful sync.
        let presentKeys = Set(
            managedEvents(in: calendar).compactMap { managedKey(from: $0) }
        )
        let missingCount = activeKeys.subtracting(presentKeys).count
        guard missingCount == 0 else {
            throw AppleCalendarSyncError.verificationFailed(missingCount)
        }
        return SyncSummary(
            workouts: syncedWorkouts,
            tentative: tentativeEvents,
            total: activeKeys.count
        )
    }

    private func configure(
        _ event: EKEvent,
        communityEvent item: CommunityEventItem,
        attendance: CalendarAttendanceState,
        calendar: EKCalendar
    ) {
        let record = item.event

        resetManagedEvent(event)
        event.calendar = calendar
        event.title = titled(
            record.title,
            attendance: attendance
        )
        event.startDate = record.startsAt
        event.endDate =
            record.endsAt ??
            record.startsAt.addingTimeInterval(3_600)
        event.isAllDay = false
        event.location =
            record.meetingName
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                .isEmpty
            ? nil
            : record.meetingName

        var lines = [
            "ATHLTH · Community Event",
            "RSVP: \(attendance.noteLabel)"
        ]

        if !record.summary
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            .isEmpty {
            lines.append("")
            lines.append(record.summary)
        }

        if let pace = record.paceLabel,
           !pace.trimmingCharacters(
                in: .whitespacesAndNewlines
           ).isEmpty {
            lines.append("Pace: \(pace)")
        }

        if let route = record.routeTitle,
           !route.trimmingCharacters(
                in: .whitespacesAndNewlines
           ).isEmpty {
            lines.append("Route: \(route)")
        }

        lines.append("")
        lines.append("Synced from ATHLTH")
        lines.append(
            managedMarker(
                type: "event",
                id: record.id
            )
        )

        event.notes = lines.joined(separator: "\n")
    }

    private func configure(
        _ event: EKEvent,
        groupEvent record: CommunityGroupEventRecord,
        attendance: CalendarAttendanceState,
        calendar: EKCalendar
    ) {
        resetManagedEvent(event)
        event.calendar = calendar
        event.title = titled(
            record.title,
            attendance: attendance
        )
        event.startDate = record.startsAt
        event.endDate =
            record.endsAt ??
            record.startsAt.addingTimeInterval(3_600)
        event.isAllDay = false
        event.location =
            record.meetingName
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                .isEmpty
            ? nil
            : record.meetingName

        if record.repeatRule == "weekly" {
            let recurrenceEnd =
                record.repeatUntil.map {
                    EKRecurrenceEnd(end: $0)
                }

            event.addRecurrenceRule(
                EKRecurrenceRule(
                    recurrenceWith: .weekly,
                    interval: 1,
                    end: recurrenceEnd
                )
            )
        }

        var lines = [
            "ATHLTH · Club Event",
            "RSVP: \(attendance.noteLabel)"
        ]

        if attendance == .unanswered {
            lines.append(
                "Open ATHLTH to respond."
            )
        }

        if !record.summary
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            .isEmpty {
            lines.append("")
            lines.append(record.summary)
        }

        lines.append("")
        lines.append("Synced from ATHLTH")
        lines.append(
            managedMarker(
                type: "group-event",
                id: record.id
            )
        )

        event.notes = lines.joined(separator: "\n")
    }

    private func configure(
        _ event: EKEvent,
        challenge: ATHLTHChallenge,
        attendance: CalendarAttendanceState,
        calendar: EKCalendar
    ) {
        resetManagedEvent(event)
        event.calendar = calendar
        event.title = titled(
            "Challenge · \(challenge.title)",
            attendance: attendance
        )
        event.startDate = challenge.rules.startsAt
        event.endDate =
            challenge.rules.endsAt ??
            challenge.rules.startsAt
                .addingTimeInterval(3_600)
        event.isAllDay = false

        var lines = [
            "ATHLTH · Challenge",
            "Response: \(attendance.noteLabel)"
        ]

        if attendance == .unanswered {
            lines.append(
                "Open ATHLTH to accept or decline the challenge."
            )
        }

        lines.append(
            "Sport: \(challenge.sport.rawValue.capitalized)"
        )

        if let distance =
            challenge.rules.targetDistanceMeters {
            lines.append(
                String(
                    format: "Target: %.1f km",
                    distance / 1_000
                )
            )
        }

        lines.append("")
        lines.append("Synced from ATHLTH")
        lines.append(
            managedMarker(
                type: "challenge",
                id: challenge.id
            )
        )

        event.notes = lines.joined(separator: "\n")
    }

    private func titled(
        _ base: String,
        attendance: CalendarAttendanceState
    ) -> String {
        guard let prefix =
            attendance.titlePrefix
        else {
            return base
        }

        return "\(prefix) · \(base)"
    }

    private func resetManagedEvent(
        _ event: EKEvent
    ) {
        event.recurrenceRules?.forEach {
            event.removeRecurrenceRule($0)
        }
        event.location = nil
        event.url = nil
    }

    private func configure(
        _ event: EKEvent,
        session: PlannedSession,
        plan: TrainingPlan,
        dayDate: Date,
        calendar: EKCalendar
    ) {
        let calendarAPI = Calendar.current

        event.calendar = calendar
        event.title = "\(plan.title): \(session.title)"

        let hour: Int
        let minute: Int

        if let scheduledStart =
                session.scheduledStart {
            let time = calendarAPI
                .dateComponents(
                    [.hour, .minute],
                    from: scheduledStart
                )

            hour = time.hour ?? defaultStartHour
            minute = time.minute ?? defaultStartMinute
        } else {
            hour = defaultStartHour
            minute = defaultStartMinute
        }

        event.startDate =
            calendarAPI.date(
                bySettingHour: hour,
                minute: minute,
                second: 0,
                of: dayDate
            ) ?? dayDate

        event.endDate =
            calendarAPI.date(
                byAdding: .minute,
                value: max(
                    session.durationMinutes ??
                    60,
                    5
                ),
                to: event.startDate
            ) ??
            event.startDate
                .addingTimeInterval(
                    3_600
                )

        event.isAllDay = false

        event.notes = eventNotes(
            session: session,
            plan: plan
        )
    }

    private func eventNotes(
        session: PlannedSession,
        plan: TrainingPlan
    ) -> String {
        var lines = [
            "ATHLTH · \(session.kind.title)",
            "Plan: \(plan.title)"
        ]

        if let minutes =
                session.durationMinutes {
            lines.append(
                "Duration: \(minutes) min"
            )
        }

        if let distance =
                session
                    .targetDistanceKilometers {
            lines.append(
                String(
                    format:
                        "Distance: %.1f km",
                    distance
                )
            )
        }

        if let notes = session.notes,
           !notes
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            .isEmpty {
            lines.append("")
            lines.append(notes)
        }

        lines.append("")
        lines.append("Synced from ATHLTH")
        lines.append(
            managedMarker(
                type: "session",
                id: session.id
            )
        )
        lines.append(
            "[ATHLTH_SESSION:\(session.id.uuidString)]"
        )
        lines.append(
            "[ATHLTH_PLAN:\(plan.id.uuidString)]"
        )

        return lines.joined(
            separator: "\n"
        )
    }

    private func managedEvents(
        in calendar: EKCalendar
    ) -> [EKEvent] {
        let now = Date()
        let start =
            Calendar.current.date(
                byAdding: .year,
                value: -3,
                to: now
            ) ??
            now.addingTimeInterval(
                -94_608_000
            )
        let end =
            Calendar.current.date(
                byAdding: .year,
                value: 5,
                to: now
            ) ??
            now.addingTimeInterval(
                157_680_000
            )

        let predicate =
            eventStore.predicateForEvents(
                withStart: start,
                end: end,
                calendars: [calendar]
            )

        return eventStore
            .events(
                matching: predicate
            )
            .filter {
                let notes = $0.notes ?? ""
                return notes.contains(
                    "[ATHLTH_MANAGED:"
                ) ||
                notes.contains(
                    "[ATHLTH_SESSION:"
                )
            }
    }

    private func managedKey(
        type: String,
        id: UUID
    ) -> String {
        "\(type):\(id.uuidString)"
    }

    private func managedMarker(
        type: String,
        id: UUID
    ) -> String {
        "[ATHLTH_MANAGED:\(type):\(id.uuidString)]"
    }

    private func managedKey(
        from event: EKEvent
    ) -> String? {
        guard let notes = event.notes else {
            return nil
        }

        if let markerRange =
            notes.range(
                of: "[ATHLTH_MANAGED:"
            ) {
            let valueStart =
                markerRange.upperBound

            guard let closing =
                    notes[valueStart...]
                        .firstIndex(of: "]")
            else {
                return nil
            }

            let payload = String(
                notes[valueStart..<closing]
            )
            let parts = payload.split(
                separator: ":",
                maxSplits: 1
            )

            guard parts.count == 2,
                  let id = UUID(
                    uuidString: String(parts[1])
                  )
            else {
                return nil
            }

            return managedKey(
                type: String(parts[0]),
                id: id
            )
        }

        if let legacySessionID =
            sessionID(from: event) {
            return managedKey(
                type: "session",
                id: legacySessionID
            )
        }

        return nil
    }

    private func sessionID(
        from event: EKEvent
    ) -> UUID? {
        guard let notes = event.notes,
              let markerRange =
                notes.range(
                    of: "[ATHLTH_SESSION:"
                )
        else {
            return nil
        }

        let valueStart =
            markerRange.upperBound

        guard let closing =
                notes[valueStart...]
                    .firstIndex(of: "]")
        else {
            return nil
        }

        return UUID(
            uuidString:
                String(
                    notes[
                        valueStart..<closing
                    ]
                )
        )
    }

    private func saveCalendarIdentifier(
        _ identifier: String
    ) {
        calendarIdentifier = identifier
        defaults.set(
            identifier,
            forKey: Key.calendarIdentifier
        )
    }

    private func persistEnabled() {
        defaults.set(
            isEnabled,
            forKey: Key.enabled
        )
    }
}

private enum AppleCalendarSyncError:
    LocalizedError {
    case calendarAccessRequired
    case noWritableCalendarSource

    var errorDescription: String? {
        switch self {
        case .calendarAccessRequired:
            return "ATHLTH needs full Calendar access to create and keep the ATHLTH training calendar synchronized."

        case .noWritableCalendarSource:
            return "ATHLTH could not find a writable Calendar account on this iPhone."
        }
    }
}
