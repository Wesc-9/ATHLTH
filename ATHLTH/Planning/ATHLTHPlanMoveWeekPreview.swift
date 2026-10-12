import Foundation

/// A pure projection: no history, reminder or persisted plan is changed.
enum ATHLTHPlanMoveWeekPreview {
    struct Destination: Identifiable {
        let dayID: UUID
        let date: Date
        var id: UUID { dayID }
    }

    struct Day: Identifiable {
        let dayID: UUID
        let date: Date
        let beforeCount: Int
        let afterCount: Int
        let beforeRunning: Int
        let afterRunning: Int
        let beforeStrength: Int
        let afterStrength: Int

        var id: UUID { dayID }
        var changed: Bool { beforeCount != afterCount }
    }

    struct Summary {
        let days: [Day]
        let activeDaysBefore: Int
        let activeDaysAfter: Int
        let runningStreakBefore: Int
        let runningStreakAfter: Int
        let strengthStreakBefore: Int
        let strengthStreakAfter: Int

        var usesFreeDay: Bool { activeDaysAfter > activeDaysBefore }
    }

    static func destinations(
        _ proposal: ATHLTHPlanReviewMoveProposal.Proposal,
        in plan: TrainingPlan,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> [Destination] {
        guard plan.id == proposal.planID,
              plan.version == proposal.expectedPlanVersion,
              let start = plan.startDate,
              let offset = plan.weeks.firstIndex(where: { $0.id == proposal.weekID }),
              let source = plan.weeks[offset].days.first(where: {
                  $0.id == proposal.sourceDayID
              }),
              (1...7).contains(source.dayIndex),
              let workout = source.sessions.first(where: {
                  $0.id == proposal.workoutID
              }),
              let weekStart = calendar.date(
                  byAdding: .day, value: offset * 7,
                  to: calendar.startOfDay(for: start)
              ),
              let sourceDate = calendar.date(
                  byAdding: .day, value: source.dayIndex - 1,
                  to: weekStart
              ),
              calendar.isDate(sourceDate, inSameDayAs: proposal.sourceDate),
              sourceDate >= calendar.startOfDay(for: referenceDate)
        else { return [] }

        if let scheduled = workout.scheduledStart,
           !calendar.isDate(scheduled, inSameDayAs: sourceDate) {
            return []
        }

        let week = plan.weeks[offset]
        let oldRun = longestStreak(in: week, kind: .running)
        let oldStrength = longestStreak(in: week, kind: .strength)
        let oldKind = longestStreak(in: week, kind: workout.kind)
        // Keep the original recommendation selectable, even when its purpose
        // is separating a crowded day rather than reducing a long streak.
        let defaultKind = longestStreak(
            in: week, kind: workout.kind,
            moving: workout, from: source.id, to: proposal.targetDayID
        )

        return week.days.compactMap { day -> Destination? in
            guard (1...7).contains(day.dayIndex),
                  day.sessions.isEmpty,
                  let date = calendar.date(
                      byAdding: .day, value: day.dayIndex - 1, to: weekStart
                  ),
                  date >= calendar.startOfDay(for: referenceDate)
            else { return nil }

            let newRun = longestStreak(
                in: week, kind: .running,
                moving: workout, from: source.id, to: day.id
            )
            let newStrength = longestStreak(
                in: week, kind: .strength,
                moving: workout, from: source.id, to: day.id
            )
            guard newRun <= max(oldRun, 2),
                  newStrength <= max(oldStrength, 2)
            else { return nil }

            // When the original recommendation reduces a long streak,
            // alternatives may not undo that specific improvement.
            if oldKind >= 3 && defaultKind < oldKind,
               longestStreak(
                   in: week, kind: workout.kind,
                   moving: workout, from: source.id, to: day.id
               ) > defaultKind {
                return nil
            }
            return Destination(dayID: day.id, date: date)
        }
        .sorted { $0.date < $1.date }
    }

    static func choosing(
        _ dayID: UUID,
        from proposal: ATHLTHPlanReviewMoveProposal.Proposal,
        in plan: TrainingPlan,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> ATHLTHPlanReviewMoveProposal.Proposal? {
        guard let destination = destinations(
            proposal, in: plan, referenceDate: referenceDate, calendar: calendar
        ).first(where: { $0.id == dayID }) else { return nil }

        return ATHLTHPlanReviewMoveProposal.Proposal(
            planID: proposal.planID,
            expectedPlanVersion: proposal.expectedPlanVersion,
            weekID: proposal.weekID,
            sourceDayID: proposal.sourceDayID,
            targetDayID: destination.id,
            workoutID: proposal.workoutID,
            workoutTitle: proposal.workoutTitle,
            sourceDate: proposal.sourceDate,
            targetDate: destination.date,
            reason: proposal.reason
        )
    }

    static func summarize(
        _ proposal: ATHLTHPlanReviewMoveProposal.Proposal,
        in plan: TrainingPlan,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> Summary? {
        guard let checked = choosing(
            proposal.targetDayID, from: proposal, in: plan,
            referenceDate: referenceDate, calendar: calendar
        ),
              let start = plan.startDate,
              let offset = plan.weeks.firstIndex(where: {
                  $0.id == proposal.weekID
              }),
              let source = plan.weeks[offset].days.first(where: {
                  $0.id == proposal.sourceDayID
              }),
              let workout = source.sessions.first(where: {
                  $0.id == proposal.workoutID
              }),
              let weekStart = calendar.date(
                  byAdding: .day, value: offset * 7,
                  to: calendar.startOfDay(for: start)
              )
        else { return nil }

        let week = plan.weeks[offset]
        let rows: [Day] = week.days.sorted {
            $0.dayIndex < $1.dayIndex
        }.compactMap { day in
            guard (1...7).contains(day.dayIndex),
                  let date = calendar.date(
                      byAdding: .day, value: day.dayIndex - 1,
                      to: weekStart
                  ) else { return nil }

            let removed = day.id == source.id ? 1 : 0
            let added = day.id == checked.targetDayID ? 1 : 0
            let run = workout.kind == .running ? 1 : 0
            let strength = workout.kind == .strength ? 1 : 0
            let runs = day.sessions.filter { $0.kind == .running }.count
            let lifts = day.sessions.filter { $0.kind == .strength }.count

            return Day(
                dayID: day.id, date: date,
                beforeCount: day.sessions.count,
                afterCount: day.sessions.count - removed + added,
                beforeRunning: runs,
                afterRunning: runs - removed * run + added * run,
                beforeStrength: lifts,
                afterStrength: lifts - removed * strength + added * strength
            )
        }

        return Summary(
            days: rows,
            activeDaysBefore: rows.filter { $0.beforeCount > 0 }.count,
            activeDaysAfter: rows.filter { $0.afterCount > 0 }.count,
            runningStreakBefore: longestStreak(in: week, kind: .running),
            runningStreakAfter: longestStreak(
                in: week, kind: .running, moving: workout,
                from: source.id, to: checked.targetDayID
            ),
            strengthStreakBefore: longestStreak(in: week, kind: .strength),
            strengthStreakAfter: longestStreak(
                in: week, kind: .strength, moving: workout,
                from: source.id, to: checked.targetDayID
            )
        )
    }

    private static func longestStreak(
        in week: TrainingPlanWeek,
        kind: WorkoutKind,
        moving: PlannedSession? = nil,
        from sourceID: UUID? = nil,
        to destinationID: UUID? = nil
    ) -> Int {
        var streak = 0
        var longest = 0
        for number in 1...7 {
            let day = week.days.first { $0.dayIndex == number }
            let kept = day?.sessions.contains {
                $0.kind == kind && !(day?.id == sourceID && $0.id == moving?.id)
            } ?? false
            let movedHere = day?.id == destinationID && moving?.kind == kind
            if kept || movedHere {
                streak += 1
                longest = max(longest, streak)
            } else {
                streak = 0
            }
        }
        return longest
    }
}
