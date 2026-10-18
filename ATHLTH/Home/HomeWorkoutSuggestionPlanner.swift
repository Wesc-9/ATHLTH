import Foundation

/// Converts a Workouts template into an independent calendar workout.
/// The source template is never modified and no training plan is changed.
enum HomeWorkoutSuggestionPlanner {
    /// Time-only DatePicker selections can carry an unrelated calendar date.
    /// Resolve the chosen clock time on the *tapped* day before validation or
    /// saving, including when local time has a daylight-saving transition.
    static func scheduledStart(
        on selectedDay: Date,
        clockTime: Date,
        calendar: Calendar = .current
    ) -> Date? {
        let time = calendar.dateComponents([.hour, .minute], from: clockTime)
        guard let hour = time.hour, let minute = time.minute,
              let resolved = calendar.date(
                bySettingHour: hour, minute: minute, second: 0,
                of: selectedDay, matchingPolicy: .strict
              ),
              calendar.isDate(resolved, inSameDayAs: selectedDay)
        else { return nil }
        return resolved
    }

    static func canSchedule(
        on selectedDay: Date,
        at start: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        calendar.isDate(start, inSameDayAs: selectedDay) && start > now
    }

    static func independentSession(
        from template: PlannedSession,
        start: Date
    ) -> PlannedSession {
        var copy = PlannedSession(
            id: UUID(),
            title: template.title,
            kind: template.kind,
            scheduledStart: start,
            durationMinutes: template.durationMinutes,
            targetDistanceKilometers: template.targetDistanceKilometers,
            targetPaceSecondsPerKilometer: template.targetPaceSecondsPerKilometer,
            routeID: template.routeID,
            exercises: template.exercises,
            notes: template.notes
        )
        copy.runningWorkout = template.runningWorkout
        copy.runningWorkouts = template.runningWorkouts
        copy.workoutTemplateID = template.workoutTemplateID
        copy.workoutBlocks = template.workoutBlocks
        copy.workoutCategory = template.workoutCategory
        copy.gearIDs = template.gearIDs
        copy.audioCoachConfiguration = template.audioCoachConfiguration
        copy.autoPauseEnabled = template.autoPauseEnabled
        copy.spotifyPlaylist = template.spotifyPlaylist
        copy.spotifyAutoplayOnStart = template.spotifyAutoplayOnStart
        copy.targetAlertConfiguration = template.targetAlertConfiguration
        copy.routeAlertConfiguration = template.routeAlertConfiguration
        copy.ghostTargetDurationSeconds = template.ghostTargetDurationSeconds
        copy.ghostUpdates = template.ghostUpdates
        return copy
    }
}
