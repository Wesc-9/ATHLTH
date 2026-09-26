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
    private var pendingPlan: TrainingPlan?

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
        plan: TrainingPlan?
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

            await sync(plan: plan)
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
        plan: TrainingPlan?
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

        await sync(plan: plan)
    }

    func sync(
        plan: TrainingPlan?
    ) async {
        if isSyncing {
            pendingPlan = plan
            return
        }

        isSyncing = true
        errorMessage = nil

        do {
            let calendar = try ensureCalendar()
            try synchronize(
                plan: plan,
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

        if let pendingPlan {
            self.pendingPlan = nil
            await sync(plan: pendingPlan)
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
        plan: TrainingPlan?,
        calendar: EKCalendar
    ) throws {
        let existingEvents =
            managedEvents(in: calendar)

        var existingBySession:
            [UUID: EKEvent] = [:]
        var duplicateEvents:
            [EKEvent] = []

        for event in existingEvents {
            guard let sessionID =
                    sessionID(from: event)
            else {
                continue
            }

            if existingBySession[sessionID] == nil {
                existingBySession[sessionID] =
                    event
            } else {
                duplicateEvents.append(event)
            }
        }

        var activeSessionIDs = Set<UUID>()

        if let plan,
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
                        activeSessionIDs.insert(
                            session.id
                        )

                        let event =
                            existingBySession[
                                session.id
                            ] ??
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

        for event in existingEvents {
            guard let sessionID =
                    sessionID(from: event),
                  !activeSessionIDs.contains(
                    sessionID
                  )
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
        session: PlannedSession,
        plan: TrainingPlan,
        dayDate: Date,
        calendar: EKCalendar
    ) {
        let calendarAPI = Calendar.current

        event.calendar = calendar
        event.title = session.title

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
                $0.notes?
                    .contains(
                        "[ATHLTH_SESSION:"
                    ) == true
            }
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
