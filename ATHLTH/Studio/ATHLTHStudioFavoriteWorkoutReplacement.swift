import Foundation

/// Keeps the existing scheduled workout ID for an atomic, version-checked
/// replacement via AppSessionStore.savePlanStudioWorkout. The selected
/// favorite's complete configuration is copied, not just its title.
extension PlannedSession {
    func studioReplacement(keepingIDFrom original: PlannedSession) -> PlannedSession {
        var result = PlannedSession(
            id: original.id,
            title: title,
            kind: kind,
            scheduledStart: original.scheduledStart ?? scheduledStart,
            durationMinutes: durationMinutes,
            targetDistanceKilometers: targetDistanceKilometers,
            targetPaceSecondsPerKilometer: targetPaceSecondsPerKilometer,
            routeID: routeID,
            exercises: exercises,
            notes: notes,
            runningWorkout: runningWorkout
        )
        result.runningWorkouts = runningWorkouts
        result.gearIDs = gearIDs
        result.audioCoachConfiguration = audioCoachConfiguration
        result.autoPauseEnabled = autoPauseEnabled
        result.spotifyPlaylist = spotifyPlaylist
        result.spotifyAutoplayOnStart = spotifyAutoplayOnStart
        result.targetAlertConfiguration = targetAlertConfiguration
        result.routeAlertConfiguration = routeAlertConfiguration
        result.ghostTargetDurationSeconds = ghostTargetDurationSeconds
        result.ghostUpdates = ghostUpdates
        result.workoutTemplateID = workoutTemplateID
        result.workoutBlocks = workoutBlocks
        result.workoutCategory = workoutCategory
        result.meetingPoint = meetingPoint
        result.plannedTrainingPlace = plannedTrainingPlace
        result.reminderMinutesBefore = reminderMinutesBefore
        result.trainTogetherMode = trainTogetherMode
        result.invitedPartnerID = invitedPartnerID
        result.allowInviteeExercises = allowInviteeExercises
        result.sharedSourceOwnerID = sharedSourceOwnerID
        result.sharedSourceSessionID = sharedSourceSessionID
        // Completion adjustments are not imported from an unrelated favorite.
        return result
    }
}
