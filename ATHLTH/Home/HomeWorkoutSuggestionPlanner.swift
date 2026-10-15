import Foundation

/// Converts a Workouts template into an independent calendar workout.
/// The source template is never modified and no training plan is changed.
enum HomeWorkoutSuggestionPlanner {
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
