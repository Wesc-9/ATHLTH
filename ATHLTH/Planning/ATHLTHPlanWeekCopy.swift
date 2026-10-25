import Foundation

/// Preview and application use identical conflict checks, so a user never
/// confirms a week-copy based on a different set of rules than the save.
struct ATHLTHPlanWeekCopy {
    enum BlockReason: String {
        case pastDate
        case plannedRest
        case existingWorkout
        case standaloneWorkout
        case sourceEmpty
    }

    struct Day: Identifiable {
        let date: Date
        let sourceDayIndex: Int
        let titles: [String]
        let reason: BlockReason?
        var id: Int { sourceDayIndex }
        var canCopy: Bool { reason == nil && !titles.isEmpty }
    }

    let sourceWeekID: UUID
    let destinationWeekID: UUID
    let expectedVersion: Int
    let days: [Day]

    var copyCount: Int {
        days.filter(\.canCopy).reduce(0) { $0 + $1.titles.count }
    }

    var occupiedCount: Int {
        days.filter { $0.reason == .existingWorkout ||
            $0.reason == .standaloneWorkout || $0.reason == .plannedRest
        }.count
    }

    init?(
        plan: TrainingPlan,
        sourceWeekID: UUID,
        destinationWeekID: UUID,
        standaloneSessions: [PlannedSession],
        today: Date = Date(),
        calendar: Calendar = .current
    ) {
        guard sourceWeekID != destinationWeekID,
              let source = plan.weeks.first(where: { $0.id == sourceWeekID }),
              let destination = plan.weeks.first(where: {
                  $0.id == destinationWeekID
              }),
              plan.startDate != nil else { return nil }

        self.sourceWeekID = sourceWeekID
        self.destinationWeekID = destinationWeekID
        self.expectedVersion = plan.version
        self.days = destination.days.sorted {
            $0.dayIndex < $1.dayIndex
        }.compactMap { targetDay in
            guard let sourceDay = source.days.first(where: {
                $0.dayIndex == targetDay.dayIndex
            }), let date = TrainingPlanSchedule.dayDate(
                in: plan, week: destination, day: targetDay, calendar: calendar
            ) else { return nil }

            let titles = sourceDay.sessions.map(\.title)
            let blocked: BlockReason?
            if titles.isEmpty {
                blocked = .sourceEmpty
            } else if calendar.startOfDay(for: date) <
                calendar.startOfDay(for: today) {
                blocked = .pastDate
            } else if targetDay.isRestDay == true {
                blocked = .plannedRest
            } else if !TrainingPlanSchedule.sessions(
                in: plan, on: date, calendar: calendar
            ).isEmpty {
                blocked = .existingWorkout
            } else if standaloneSessions.contains(where: {
                guard let scheduled = $0.scheduledStart else { return false }
                return calendar.isDate(scheduled, inSameDayAs: date)
            }) {
                blocked = .standaloneWorkout
            } else {
                blocked = nil
            }
            return Day(
                date: date,
                sourceDayIndex: targetDay.dayIndex,
                titles: titles,
                reason: blocked
            )
        }
    }

    /// Return independent scheduled occurrences, not new recorded activity.
    /// IDs for the workout, planned exercises and superset rounds are renewed.
    static func clone(_ source: PlannedSession, on day: Date,
                      calendar: Calendar = .current) -> PlannedSession {
        var copied = PlannedSession(
            id: UUID(),
            title: source.title,
            kind: source.kind,
            scheduledStart: nil,
            durationMinutes: source.durationMinutes,
            targetDistanceKilometers: source.targetDistanceKilometers,
            targetPaceSecondsPerKilometer: source.targetPaceSecondsPerKilometer,
            routeID: source.routeID,
            exercises: [],
            notes: source.notes
        )
        let oldClock = source.scheduledStart.map {
            calendar.dateComponents([.hour, .minute], from: $0)
        }
        let legacyHasClock = (oldClock?.hour ?? 0) != 0 ||
            (oldClock?.minute ?? 0) != 0
        let hasClock = source.scheduledTimeIsExplicit ?? legacyHasClock
        if hasClock, let oldClock {
            copied.scheduledStart = calendar.date(
                bySettingHour: oldClock.hour ?? 18,
                minute: oldClock.minute ?? 0,
                second: 0,
                of: day
            ) ?? day
        } else {
            copied.scheduledStart = day
        }
        copied.scheduledTimeIsExplicit = hasClock
        var newSupersets: [UUID: UUID] = [:]
        copied.exercises = source.exercises.map { exercise in
            let group = exercise.supersetGroupID.map { old -> UUID in
                if let known = newSupersets[old] { return known }
                let id = UUID()
                newSupersets[old] = id
                return id
            }
            return PlannedExercise(
                id: UUID(),
                exerciseID: exercise.exerciseID,
                embeddedExercise: exercise.embeddedExercise,
                sets: exercise.sets,
                reps: exercise.reps,
                targetWeightKilograms: exercise.targetWeightKilograms,
                targetRPE: exercise.targetRPE,
                restSeconds: exercise.restSeconds,
                notes: exercise.notes,
                targetRIR: exercise.targetRIR,
                supersetGroupID: group,
                progression: exercise.progression,
                targetKind: exercise.targetKind,
                targetDurationSeconds: exercise.targetDurationSeconds,
                loadKind: exercise.loadKind,
                targetResistanceLevel: exercise.targetResistanceLevel
            )
        }
        copied.runningWorkout = source.runningWorkout
        copied.runningWorkouts = source.runningWorkouts
        copied.gearIDs = source.gearIDs
        copied.audioCoachConfiguration = source.audioCoachConfiguration
        copied.autoPauseEnabled = source.autoPauseEnabled
        copied.spotifyPlaylist = source.spotifyPlaylist
        copied.spotifyAutoplayOnStart = source.spotifyAutoplayOnStart
        copied.targetAlertConfiguration = source.targetAlertConfiguration
        copied.workoutTemplateID = source.workoutTemplateID
        copied.workoutBlocks = source.workoutBlocks
        copied.workoutCategory = source.workoutCategory
        // No plan completion, shared-session or follow-up relationship is
        // inherited by a new scheduled occurrence.
        return copied
    }
}
