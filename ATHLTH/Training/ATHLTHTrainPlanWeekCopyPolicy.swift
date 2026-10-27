import Foundation

/// Safe fill-empty-week copying used by the Train > Plan reference surface.
/// Never overwrites an existing workout or an explicit rest day and never
/// changes completed historical sessions.
enum ATHLTHTrainPlanWeekCopyPolicy {
    struct Preview: Equatable {
        var eligibleSessions = 0
        var protectedDays = 0
        var pastDays = 0

        var canCopy: Bool { eligibleSessions > 0 }
    }

    struct Result: Equatable {
        var copiedSessions = 0
        var failedSessions = 0
        var protectedDays = 0
        var pastDays = 0
    }

    static func preview(
        plan: TrainingPlan,
        sourceWeekIndex: Int,
        targetWeekIndex: Int,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Preview {
        guard let start = plan.startDate,
              plan.weeks.indices.contains(sourceWeekIndex),
              plan.weeks.indices.contains(targetWeekIndex),
              sourceWeekIndex != targetWeekIndex else { return Preview() }

        let first = calendar.startOfDay(for: start)
        let today = calendar.startOfDay(for: now)
        let source = plan.weeks[sourceWeekIndex]
        let target = plan.weeks[targetWeekIndex]
        var result = Preview()

        for sourceDay in source.days {
            let sourceSessions = sourceDay.sessions.filter { !$0.isExplicitRestDay }
            guard !sourceSessions.isEmpty else { continue }
            guard let targetDay = target.days.first(where: {
                $0.dayIndex == sourceDay.dayIndex
            }) else {
                result.protectedDays += 1
                continue
            }
            guard let date = calendar.date(
                byAdding: .day,
                value: targetWeekIndex * 7 + targetDay.dayIndex - 1,
                to: first
            ), date >= today else {
                result.pastDays += 1
                continue
            }
            // Explicit rest days are intentional. They are protected too.
            guard targetDay.sessions.isEmpty else {
                result.protectedDays += 1
                continue
            }
            result.eligibleSessions += sourceSessions.count
        }
        return result
    }

    @MainActor
    static func copy(
        in store: AppSessionStore,
        planID: UUID,
        sourceWeekIndex: Int,
        targetWeekIndex: Int,
        now: Date = Date()
    ) -> Result {
        guard let original = store.trainingPlan(withID: planID),
              original.weeks.indices.contains(sourceWeekIndex),
              original.weeks.indices.contains(targetWeekIndex),
              sourceWeekIndex != targetWeekIndex else { return Result() }

        let eligibility = preview(
            plan: original,
            sourceWeekIndex: sourceWeekIndex,
            targetWeekIndex: targetWeekIndex,
            now: now
        )
        var result = Result(
            protectedDays: eligibility.protectedDays,
            pastDays: eligibility.pastDays
        )
        guard eligibility.canCopy else { return result }

        let source = original.weeks[sourceWeekIndex]
        let target = original.weeks[targetWeekIndex]
        for day in source.days {
            let workouts = day.sessions.filter { !$0.isExplicitRestDay }
            guard !workouts.isEmpty,
                  let destination = target.days.first(where: {
                      $0.dayIndex == day.dayIndex
                  }), destination.sessions.isEmpty else { continue }

            let dayPreview = previewForSingleDay(
                original, sourceWeekIndex: sourceWeekIndex,
                targetWeekIndex: targetWeekIndex,
                dayIndex: day.dayIndex,
                now: now
            )
            guard dayPreview else { continue }
            for workout in workouts {
                guard let latest = store.trainingPlan(withID: planID),
                      store.copyPlanStudioWorkout(
                        planID: planID,
                        sourceWorkoutID: workout.id,
                        targetDayID: destination.id,
                        expectedVersion: latest.version
                      ) else {
                    result.failedSessions += 1
                    continue
                }
                result.copiedSessions += 1
            }
        }
        return result
    }

    private static func previewForSingleDay(
        _ plan: TrainingPlan,
        sourceWeekIndex: Int,
        targetWeekIndex: Int,
        dayIndex: Int,
        now: Date
    ) -> Bool {
        guard let sourceDay = plan.weeks[sourceWeekIndex].days.first(where: {
            $0.dayIndex == dayIndex
        }), let targetDay = plan.weeks[targetWeekIndex].days.first(where: {
            $0.dayIndex == dayIndex
        }) else { return false }

        // Count only the specific day's source content by creating an
        // isolated comparison. The target itself stays untouched.
        guard !sourceDay.sessions.filter({ !$0.isExplicitRestDay }).isEmpty,
              targetDay.sessions.isEmpty, let start = plan.startDate else {
            return false
        }
        let calendar = Calendar.current
        let first = calendar.startOfDay(for: start)
        let today = calendar.startOfDay(for: now)
        guard let targetDate = calendar.date(
            byAdding: .day,
            value: targetWeekIndex * 7 + dayIndex - 1,
            to: first
        ) else { return false }
        return targetDate >= today
    }
}
