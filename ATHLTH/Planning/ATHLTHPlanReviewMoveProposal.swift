import Foundation

/// A read-only proposal for moving one future planned workout to an empty day.
/// The athlete must explicitly approve; the canonical Plan Studio guards
/// remain the only write path.
enum ATHLTHPlanReviewMoveProposal {
    struct Proposal: Identifiable, Equatable {
        let planID: UUID
        let expectedPlanVersion: Int
        let weekID: UUID
        let sourceDayID: UUID
        let targetDayID: UUID
        let workoutID: UUID
        let workoutTitle: String
        let sourceDate: Date
        let targetDate: Date
        let reason: String

        var id: UUID { workoutID }
    }

    static func suggest(
        for suggestion: ATHLTHPlanReviewAdvisor.Suggestion,
        in plan: TrainingPlan,
        referenceDate: Date = Date(),
        calendar: Calendar = .current,
        eligibleWorkoutIDs: Set<UUID>? = nil
    ) -> Proposal? {
        guard let startDate = plan.startDate,
              let weekIndex = plan.weeks.firstIndex(where: {
                  $0.id == suggestion.weekID
              }),
              let sourceDayID = suggestion.dayID,
              let source = plan.weeks[weekIndex].days.first(where: {
                  $0.id == sourceDayID
              }),
              (1...7).contains(source.dayIndex),
              [.mixedDay, .consecutiveRuns, .consecutiveStrength, .longDay]
                .contains(suggestion.kind)
        else { return nil }

        let week = plan.weeks[weekIndex]
        let start = calendar.startOfDay(for: startDate)
        guard let weekStart = calendar.date(
            byAdding: .day, value: weekIndex * 7, to: start
        ),
              let sourceDate = calendar.date(
                byAdding: .day, value: source.dayIndex - 1, to: weekStart
              ) else { return nil }

        let today = calendar.startOfDay(for: referenceDate)
        guard sourceDate >= today else { return nil }

        let sourceCandidates: [PlannedSession]
        switch suggestion.kind {
        case .consecutiveRuns:
            sourceCandidates = source.sessions.filter { $0.kind == .running }
        case .consecutiveStrength:
            sourceCandidates = source.sessions.filter { $0.kind == .strength }
        case .mixedDay:
            guard source.sessions.contains(where: { $0.kind == .running }),
                  source.sessions.contains(where: { $0.kind == .strength })
            else { return nil }
            // Prefer moving strength when both workout types share a day.
            sourceCandidates = source.sessions.filter { $0.kind == .strength }
        case .longDay:
            guard source.sessions.count >= 2,
                  source.sessions.allSatisfy({
                      ($0.durationMinutes ?? 0) > 0
                  }),
                  source.sessions.compactMap(\.durationMinutes)
                    .reduce(0, +) >= 150
            else { return nil }
            sourceCandidates = source.sessions.sorted {
                ($0.durationMinutes ?? 0) > ($1.durationMinutes ?? 0)
            }
        default:
            return nil
        }

        let availableDays = week.days.filter { day in
            guard day.sessions.isEmpty,
                  (1...7).contains(day.dayIndex),
                  let target = calendar.date(
                      byAdding: .day, value: day.dayIndex - 1, to: weekStart
                  ) else { return false }
            return target >= today
        }
        guard !availableDays.isEmpty else { return nil }

        struct Candidate {
            let workout: PlannedSession
            let day: TrainingPlanDay
            let date: Date
            let streakAfter: Int
            let proximity: Int
        }
        var candidates: [Candidate] = []
        for workout in sourceCandidates {
            guard eligibleWorkoutIDs?.contains(workout.id) ?? true else {
                continue
            }
            // Do not trust an imported session with a conflicting date.
            if let scheduled = workout.scheduledStart,
               !calendar.isDate(scheduled, inSameDayAs: sourceDate) {
                continue
            }
            let before = maximumStreak(in: week, kind: workout.kind)
            for day in availableDays {
                guard let targetDate = calendar.date(
                    byAdding: .day, value: day.dayIndex - 1, to: weekStart
                ) else { continue }
                let after = maximumStreak(
                    in: week,
                    kind: workout.kind,
                    moving: workout.id,
                    from: source.id,
                    to: day.id
                )
                if suggestion.kind == .consecutiveRuns ||
                    suggestion.kind == .consecutiveStrength {
                    // Do not promise a better distribution unless there is
                    // a concrete decrease in the streak of that workout type.
                    guard after < before else { continue }
                } else {
                    // A move from a mixed or long day must not introduce a
                    // new run/strength streak of three or more.
                    guard after <= max(before, 2) else { continue }
                }
                candidates.append(Candidate(
                    workout: workout, day: day, date: targetDate,
                    streakAfter: after,
                    proximity: abs(day.dayIndex - source.dayIndex)
                ))
            }
        }

        guard let best = candidates.sorted(by: { lhs, rhs in
            if lhs.streakAfter != rhs.streakAfter {
                return lhs.streakAfter < rhs.streakAfter
            }
            if lhs.proximity != rhs.proximity {
                return lhs.proximity < rhs.proximity
            }
            return lhs.day.dayIndex < rhs.day.dayIndex
        }).first else { return nil }

        return Proposal(
            planID: plan.id,
            expectedPlanVersion: plan.version,
            weekID: week.id,
            sourceDayID: source.id,
            targetDayID: best.day.id,
            workoutID: best.workout.id,
            workoutTitle: best.workout.title,
            sourceDate: sourceDate,
            targetDate: best.date,
            reason: suggestion.detail
        )
    }

    private static func maximumStreak(
        in week: TrainingPlanWeek,
        kind: WorkoutKind,
        moving workoutID: UUID? = nil,
        from sourceDayID: UUID? = nil,
        to targetDayID: UUID? = nil
    ) -> Int {
        var result = 0
        var streak = 0
        for dayIndex in 1...7 {
            guard let day = week.days.first(where: {
                $0.dayIndex == dayIndex
            }) else {
                streak = 0
                continue
            }
            let hasKind = day.sessions.contains {
                $0.kind == kind &&
                !(day.id == sourceDayID && $0.id == workoutID)
            } || (day.id == targetDayID)
            if hasKind {
                streak += 1
                result = max(result, streak)
            } else {
                streak = 0
            }
        }
        return result
    }
}

@MainActor
extension AppSessionStore {
    /// Never silently moves workouts. In particular, a stale preview,
    /// a filled target day or a completed/skipped workout is rejected.
    @discardableResult
    func applyPlanReviewMoveProposal(
        _ proposal: ATHLTHPlanReviewMoveProposal.Proposal,
        healthWorkouts: [WorkoutSummary],
        strengthHistory: [StrengthWorkoutLog]
    ) -> Bool {
        guard let plan = trainingPlan(withID: proposal.planID),
              plan.version == proposal.expectedPlanVersion,
              let startDate = plan.startDate,
              let weekIndex = plan.weeks.firstIndex(where: {
                  $0.id == proposal.weekID
              }),
              let source = plan.weeks[weekIndex].days.first(where: {
                  $0.id == proposal.sourceDayID
              }),
              let target = plan.weeks[weekIndex].days.first(where: {
                  $0.id == proposal.targetDayID
              }),
              source.sessions.contains(where: {
                  $0.id == proposal.workoutID
              }),
              source.id != target.id,
              target.sessions.isEmpty,
              (1...7).contains(source.dayIndex),
              (1...7).contains(target.dayIndex)
        else { return false }

        let calendar = Calendar.current
        let weekStart = calendar.date(
            byAdding: .day, value: weekIndex * 7,
            to: calendar.startOfDay(for: startDate)
        )
        guard let weekStart,
              let sourceDate = calendar.date(
                  byAdding: .day, value: source.dayIndex - 1, to: weekStart
              ),
              let targetDate = calendar.date(
                  byAdding: .day, value: target.dayIndex - 1, to: weekStart
              ),
              calendar.isDate(sourceDate, inSameDayAs: proposal.sourceDate),
              calendar.isDate(targetDate, inSameDayAs: proposal.targetDate)
        else { return false }

        return movePlanStudioWorkout(
            planID: proposal.planID,
            workoutID: proposal.workoutID,
            targetDate: proposal.targetDate,
            expectedVersion: proposal.expectedPlanVersion,
            healthWorkouts: healthWorkouts,
            strengthHistory: strengthHistory
        )
    }
}
