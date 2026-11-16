import Foundation

@MainActor
extension AppSessionStore {
    /// The single status snapshot used by Apple Calendar. Explicit Health
    /// associations are used; a coincidentally similar workout never counts.
    func calendarWorkoutStatuses(
        healthWorkouts: [WorkoutSummary],
        strengthHistory: [StrengthWorkoutLog]
    ) -> [UUID: ATHLTHCalendarWorkoutStatus] {
        let healthByID = Dictionary(
            healthWorkouts.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var output: [UUID: ATHLTHCalendarWorkoutStatus] = [:]
        let plans = ([activePlan].compactMap { $0 } + scheduledPlans)
        for plan in plans {
            for workout in plan.weeks.flatMap(\.days).flatMap(\.sessions)
                where !workout.isExplicitRestDay {
                let timing = recordedTimes(for: workout.id)
                let recordedHealth = linkedHealthWorkoutID(
                    planID: plan.id, sessionID: workout.id
                ).flatMap { healthByID[$0] }
                let recordedStrength = strengthHistory.first {
                    $0.plannedSessionID == workout.id && $0.isFinished
                }
                let completed = isPlanSessionCompleted(
                    planID: plan.id, sessionID: workout.id,
                    healthWorkouts: healthWorkouts,
                    strengthHistory: strengthHistory
                ) || timing?.endedAt != nil
                output[workout.id] = ATHLTHCalendarWorkoutStatus(
                    completed: completed,
                    cancelled: isPlanSessionSkipped(
                        planID: plan.id, sessionID: workout.id
                    ) || workout.cancelledAt != nil,
                    actualStart: timing?.endedAt != nil
                        ? timing?.startedAt :
                        (recordedHealth?.startDate ?? recordedStrength?.startedAt),
                    actualEnd: timing?.endedAt ??
                        recordedHealth?.endDate ?? recordedStrength?.endedAt
                )
            }
        }
        for workout in standalonePlannedSessions where !workout.isExplicitRestDay {
            let timing = recordedTimes(for: workout.id)
            output[workout.id] = ATHLTHCalendarWorkoutStatus(
                completed: timing?.endedAt != nil,
                cancelled: workout.cancelledAt != nil,
                actualStart: timing?.endedAt != nil ? timing?.startedAt : nil,
                actualEnd: timing?.endedAt
            )
        }
        return output
    }

    /// Only unfinished, unstarted, still-scheduled sessions may be changed.
    /// Keep exactly the same session UUID and structured workout recipe.
    @discardableResult
    func changePlannedWorkoutClock(
        _ workoutID: UUID,
        on selectedDate: Date,
        to clockTime: Date,
        healthWorkouts: [WorkoutSummary],
        strengthHistory: [StrengthWorkoutLog],
        now: Date = Date()
    ) -> Bool {
        guard let revised = ATHLTHPlannedWorkoutLifecycle.updatingClock(
            scheduled: selectedDate, clock: clockTime
        ), revised > now else { return false }
        guard recordedTimes(for: workoutID) == nil else { return false }
        return changePlannedWorkoutClockWithoutTiming(
            workoutID, to: revised,
            healthWorkouts: healthWorkouts, strengthHistory: strengthHistory
        )
    }

    private func changePlannedWorkoutClockWithoutTiming(
        _ workoutID: UUID,
        to revised: Date,
        healthWorkouts: [WorkoutSummary],
        strengthHistory: [StrengthWorkoutLog]
    ) -> Bool {
        if let existing = standalonePlannedSessions.first(where: { $0.id == workoutID }) {
            guard existing.cancelledAt == nil,
                  recordedTimes(for: workoutID) == nil
            else { return false }
            var updated = existing
            updated.scheduledStart = revised
            updateStandalonePlannedSession(updated)
            return true
        }
        for plan in ([activePlan].compactMap { $0 } + scheduledPlans) {
            guard let existing = plan.weeks.flatMap(\.days).flatMap(\.sessions)
                .first(where: { $0.id == workoutID }) else { continue }
            guard !existing.isExplicitRestDay, existing.cancelledAt == nil,
                  recordedTimes(for: workoutID) == nil,
                  !isPlanSessionSkipped(planID: plan.id, sessionID: workoutID),
                  !isPlanSessionCompleted(
                      planID: plan.id, sessionID: workoutID,
                      healthWorkouts: healthWorkouts,
                      strengthHistory: strengthHistory
                  )
            else { return false }
            var updated = existing
            updated.scheduledStart = revised
            updateSession(updated, inPlan: plan.id)
            return true
        }
        return false
    }

    @discardableResult
    func cancelPlannedWorkout(
        _ workoutID: UUID,
        healthWorkouts: [WorkoutSummary],
        strengthHistory: [StrengthWorkoutLog],
        now: Date = Date()
    ) -> Bool {
        guard recordedTimes(for: workoutID) == nil else { return false }
        if let existing = standalonePlannedSessions.first(where: { $0.id == workoutID }) {
            guard !existing.isExplicitRestDay, existing.cancelledAt == nil
            else { return false }
            var updated = existing
            updated.cancelledAt = now
            updateStandalonePlannedSession(updated)
            PlannedWorkoutReminderScheduler.cancel(workoutID)
            return true
        }
        for plan in ([activePlan].compactMap { $0 } + scheduledPlans) {
            guard let existing = plan.weeks.flatMap(\.days).flatMap(\.sessions)
                .first(where: { $0.id == workoutID }) else { continue }
            guard !existing.isExplicitRestDay, existing.cancelledAt == nil,
                  !isPlanSessionSkipped(planID: plan.id, sessionID: workoutID),
                  !isPlanSessionCompleted(
                      planID: plan.id, sessionID: workoutID,
                      healthWorkouts: healthWorkouts,
                      strengthHistory: strengthHistory
                  )
            else { return false }
            var updated = existing
            updated.cancelledAt = now
            updateSession(updated, inPlan: plan.id)
            setPlanSessionSkipped(
                planID: plan.id, sessionID: workoutID, skipped: true
            )
            PlannedWorkoutReminderScheduler.cancel(workoutID)
            return true
        }
        return false
    }

    /// Re-run on foreground and while viewing the selected day. The caller
    /// must also keep a time-based wake-up while the app remains open.
    @discardableResult
    func reconcileExpiredPlannedWorkouts(
        now: Date = Date(),
        healthWorkouts: [WorkoutSummary],
        strengthHistory: [StrengthWorkoutLog]
    ) -> Int {
        var expired: [UUID] = []
        for workout in standalonePlannedSessions {
            if ATHLTHPlannedWorkoutLifecycle.shouldCancel(
                scheduled: workout.scheduledStart, now: now,
                hasStarted: recordedTimes(for: workout.id) != nil,
                isCompleted: recordedTimes(for: workout.id)?.endedAt != nil,
                isCancelled: workout.cancelledAt != nil
            ) {
                expired.append(workout.id)
            }
        }
        for plan in ([activePlan].compactMap { $0 } + scheduledPlans) {
            for workout in plan.weeks.flatMap(\.days).flatMap(\.sessions) {
                guard !workout.isExplicitRestDay else { continue }
                if ATHLTHPlannedWorkoutLifecycle.shouldCancel(
                    scheduled: workout.scheduledStart, now: now,
                    hasStarted: recordedTimes(for: workout.id) != nil,
                    isCompleted: isPlanSessionCompleted(
                        planID: plan.id, sessionID: workout.id,
                        healthWorkouts: healthWorkouts,
                        strengthHistory: strengthHistory
                    ),
                    isCancelled: workout.cancelledAt != nil ||
                        isPlanSessionSkipped(
                            planID: plan.id, sessionID: workout.id
                        )
                ) { expired.append(workout.id) }
            }
        }
        var count = 0
        for id in Set(expired) {
            if cancelPlannedWorkout(
                id, healthWorkouts: healthWorkouts,
                strengthHistory: strengthHistory, now: now
            ) { count += 1 }
        }
        return count
    }

    /// Used for a precise in-app wake-up; never assume the OS will execute
    /// timers after the user force-quits or suspends the app.
    func nextPlannedCancellationDeadline(
        after now: Date = Date(),
        healthWorkouts: [WorkoutSummary],
        strengthHistory: [StrengthWorkoutLog]
    ) -> Date? {
        var candidates: [Date] = []
        let all = standalonePlannedSessions +
            ([activePlan].compactMap { $0 } + scheduledPlans)
            .flatMap(\.weeks).flatMap(\.days).flatMap(\.sessions)
        for workout in all where !workout.isExplicitRestDay {
            guard let start = workout.scheduledStart,
                  recordedTimes(for: workout.id) == nil,
                  workout.cancelledAt == nil else { continue }
            let isPlanSkippedOrCompleted = ([activePlan].compactMap { $0 } + scheduledPlans)
                .contains { plan in
                    plan.weeks.flatMap(\.days).flatMap(\.sessions)
                        .contains { $0.id == workout.id } &&
                        (isPlanSessionSkipped(planID: plan.id, sessionID: workout.id) ||
                         isPlanSessionCompleted(
                            planID: plan.id, sessionID: workout.id,
                            healthWorkouts: healthWorkouts,
                            strengthHistory: strengthHistory
                         ))
                }
            guard !isPlanSkippedOrCompleted else { continue }
            let cutoff = ATHLTHPlannedWorkoutLifecycle.cancellationDeadline(for: start)
            if cutoff > now { candidates.append(cutoff) }
        }
        return candidates.min()
    }
}
