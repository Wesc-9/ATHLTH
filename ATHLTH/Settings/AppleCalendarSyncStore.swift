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
    @Published private(set) var defaultStartHour: Int
    @Published private(set) var defaultStartMinute: Int
    @Published var errorMessage: String?

    let calendarName = "ATHLTH"

    private let eventStore = EKEventStore()
    private let defaults: UserDefaults
    private var pendingSnapshot: CalendarSyncSnapshot?

    private struct CalendarSyncSnapshot {
        let plan: TrainingPlan?
        let communityEvents: [CommunityEventItem]
        let groupEvents: [CommunityGroupEventRecord]
        let groupEventRSVPs: [CommunityGroupEventRSVPRecord]
        let challenges: [ATHLTHChallenge]
        let currentUserID: UUID?
    }

    private enum CalendarAttendanceState {
        case going
        case maybe
        case unanswered
        case waitlist

        var titlePrefix: String? {
            switch self {
            case .going:
                return nil
            case .maybe:
                return "Maybe"
            case .unanswered:
                return "No response"
            case .waitlist:
                return "Waitlist"
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
    }

    func enable(
        plan: TrainingPlan?,
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

    func syncIfEnabled(
        plan: TrainingPlan?,
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
            communityEvents: communityEvents,
            groupEvents: groupEvents,
            groupEventRSVPs: groupEventRSVPs,
            challenges: challenges,
            currentUserID: currentUserID
        )
    }

    func sync(
        plan: TrainingPlan?,
        communityEvents: [CommunityEventItem] = [],
        groupEvents: [CommunityGroupEventRecord] = [],
        groupEventRSVPs: [CommunityGroupEventRSVPRecord] = [],
        challenges: [ATHLTHChallenge] = [],
        currentUserID: UUID? = nil
    ) async {
        let snapshot = CalendarSyncSnapshot(
            plan: plan,
            communityEvents: communityEvents,
            challenges: challenges,
            officialChallenges: officialChallenges,
            joinedOfficialChallengeIDs:
                joinedOfficialChallengeIDs,
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
            try synchronize(
                snapshot: snapshot,
                calendar: calendar
            )

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
    ) throws {
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

        if let plan = snapshot.plan,
           let planStart = plan.startDate {
            let calendarAPI = Calendar.current
            let normalizedStart =
                calendarAPI.startOfDay(
                    for: planStart
                )

            for week in plan.weeks {
                for day in week.days {
                    let dayOffset =
                        max(
                            week.weekNumber - 1,
                            0
                        ) * 7 +
                        max(
                            day.dayIndex - 1,
                            0
                        )

                    guard let dayDate =
                            calendarAPI.date(
                                byAdding: .day,
                                value: dayOffset,
                                to: normalizedStart
                            )
                    else {
                        continue
                    }

                    for session in day.sessions {
                        let key =
                            managedKey(
                                type: "session",
                                id: session.id
                            )
                        activeKeys.insert(key)

                        let event =
                            existingByKey[key] ??
                            EKEvent(
                                eventStore:
                                    eventStore
                            )

                        configure(
                            event,
                            session: session,
                            plan: plan,
                            dayDate: dayDate,
                            calendar: calendar
                        )

                        try eventStore.save(
                            event,
                            span: .thisEvent,
                            commit: false
                        )
                    }
                }
            }
        }

        if let currentUserID = snapshot.currentUserID {
            let now = Date()

            // Public Community events only enter Calendar after the user has
            // explicitly selected Going or Maybe.
            for item in snapshot.communityEvents {
                let record = item.event
                let attendance = item.participantRows.first {
                    $0.userID == currentUserID
                }?.attendanceStatus
                let effectiveEnd =
                    record.endsAt ??
                    record.startsAt.addingTimeInterval(3_600)

                guard let attendance,
                      record.status == "upcoming",
                      effectiveEnd >= now
                else {
                    continue
                }

                let key = managedKey(
                    type: "event",
                    id: record.id
                )
                activeKeys.insert(key)

                let event =
                    existingByKey[key] ??
                    EKEvent(eventStore: eventStore)

                configure(
                    event,
                    communityEvent: item,
                    attendance:
                        attendance == .maybe
                            ? .maybe
                            : .going,
                    calendar: calendar
                )

                try eventStore.save(
                    event,
                    span: .thisEvent,
                    commit: false
                )
            }

            // Club membership makes an upcoming Club event relevant to the
            // user. No RSVP is shown as "No response" until they answer.
            for record in snapshot.groupEvents {
                let effectiveEnd =
                    record.endsAt ??
                    record.startsAt.addingTimeInterval(3_600)

                guard (
                    record.status == "upcoming" ||
                    record.status == "live"
                ),
                effectiveEnd >= now
                else {
                    continue
                }

                let rsvp = snapshot.groupEventRSVPs.first {
                    $0.eventID == record.id &&
                    $0.userID == currentUserID
                }?.status

                guard rsvp != "not_going" else {
                    continue
                }

                let attendance: CalendarAttendanceState
                switch rsvp {
                case "going":
                    attendance = .going
                case "maybe":
                    attendance = .maybe
                case "waitlist":
                    attendance = .waitlist
                default:
                    attendance = .unanswered
                }

                let key = managedKey(
                    type: "group-event",
                    id: record.id
                )
                activeKeys.insert(key)

                let event =
                    existingByKey[key] ??
                    EKEvent(eventStore: eventStore)

                configure(
                    event,
                    groupEvent: record,
                    attendance: attendance,
                    calendar: calendar
                )

                try eventStore.save(
                    event,
                    span: .thisEvent,
                    commit: false
                )
            }

            // Only challenges where this user was actually challenged are
            // synced. An invitation remains visible as "No response" until
            // accepted or declined.
            for challenge in snapshot.challenges {
                guard let participant = challenge.participants.first(
                    where: { $0.userID == currentUserID }
                ),
                participant.state == .invited ||
                    participant.state == .accepted,
                challenge.status == .invited ||
                    challenge.status == .upcoming ||
                    challenge.status == .active
                else {
                    continue
                }

                let key = managedKey(
                    type: "challenge",
                    id: challenge.id
                )
                activeKeys.insert(key)

                let event =
                    existingByKey[key] ??
                    EKEvent(eventStore: eventStore)

                configure(
                    event,
                    challenge: challenge,
                    attendance:
                        participant.state == .invited
                            ? .unanswered
                            : .going,
                    calendar: calendar
                )

                try eventStore.save(
                    event,
                    span: .thisEvent,
                    commit: false
                )
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
