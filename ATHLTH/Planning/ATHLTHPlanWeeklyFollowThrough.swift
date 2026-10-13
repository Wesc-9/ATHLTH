import Foundation

/// Read-only status of scheduled plan workouts. An unresolved day in the past
/// needs review, but must never be labelled as a failed workout automatically.
/// Uses the same explicit completion/skip authority as the plan editor.
@MainActor
enum ATHLTHPlanWeeklyFollowThrough {
    struct Week: Identifiable {
        let id: UUID
        let number: Int
        let completed: Int
        let skipped: Int
        let upcoming: Int
        let needsReview: Int
        let unknownDate: Int
        let pastDated: Int
        let pastConfirmed: Int
        let pastCompleted: Int
        let isFullyElapsed: Bool
        let firstReviewDayID: UUID?
        let firstSkippedDayID: UUID?

        var pastSkipped: Int { pastConfirmed - pastCompleted }
        var pastUnreviewed: Int { pastDated - pastConfirmed }

        var pastCompletionPercent: Int? {
            guard pastDated > 0 else { return nil }
            return Int((Double(pastCompleted) / Double(pastDated) * 100).rounded())
        }

        var preferredReviewDayID: UUID? { firstReviewDayID ?? firstSkippedDayID }

        var planned: Int {
            completed + skipped + upcoming + needsReview + unknownDate
        }
    }

    enum ReviewSuggestion: Equatable {
        case reviewUnresolved(Int)
        case reviewSkipped(Int)
    }

    struct Report {
        let weeks: [Week]

        var completed: Int { weeks.reduce(0) { $0 + $1.completed } }
        var skipped: Int { weeks.reduce(0) { $0 + $1.skipped } }
        var upcoming: Int { weeks.reduce(0) { $0 + $1.upcoming } }
        var needsReview: Int { weeks.reduce(0) { $0 + $1.needsReview } }
        var unknownDate: Int { weeks.reduce(0) { $0 + $1.unknownDate } }
        var pastDated: Int { weeks.reduce(0) { $0 + $1.pastDated } }
        var pastConfirmed: Int { weeks.reduce(0) { $0 + $1.pastConfirmed } }
        var pastCompleted: Int { weeks.reduce(0) { $0 + $1.pastCompleted } }
        var pastSkipped: Int { weeks.reduce(0) { $0 + $1.pastSkipped } }
        var pastUnreviewed: Int { weeks.reduce(0) { $0 + $1.pastUnreviewed } }

        /// Nil means there are no past scheduled workouts to evaluate.
        var completionPercent: Int? {
            guard pastDated > 0 else { return nil }
            return Int((Double(pastCompleted) / Double(pastDated) * 100).rounded())
        }

        var accountedPercent: Int? {
            guard pastDated > 0 else { return nil }
            return Int((Double(pastConfirmed) / Double(pastDated) * 100).rounded())
        }
        var total: Int { weeks.reduce(0) { $0 + $1.planned } }

        /// Read-only guidance; never edits, reschedules or assumes an outcome.
        var reviewSuggestion: ReviewSuggestion? {
            if pastUnreviewed >= 2 { return .reviewUnresolved(pastUnreviewed) }
            if pastSkipped >= 2 { return .reviewSkipped(pastSkipped) }
            return nil
        }

        /// Compare only complete historical weeks. Current/partial weeks and
        /// undated sessions are excluded to avoid misleading trends.
        var completedWeekTrend: (previous: Week, latest: Week, delta: Int)? {
            let eligible = weeks.filter {
                $0.isFullyElapsed && $0.pastDated > 0 && $0.upcoming == 0 && $0.unknownDate == 0
                && $0.pastDated == $0.planned
            }
            guard eligible.count >= 2,
                  let latest = eligible.last,
                  let previous = eligible.dropLast().last,
                  let latestPercent = latest.pastCompletionPercent,
                  let previousPercent = previous.pastCompletionPercent else {
                return nil
            }
            return (previous, latest, latestPercent - previousPercent)
        }

        /// Lead with weeks needing review, then the nearest upcoming weeks.
        /// Older fully settled weeks remain accessible when expanded.
        var relevantWeeks: [Week] {
            let nonempty = weeks.filter { $0.planned > 0 }
            let review = nonempty.filter { $0.needsReview > 0 }
            let skipped = nonempty.filter {
                $0.needsReview == 0 && $0.pastSkipped > 0
            }
            let upcoming = nonempty.filter {
                $0.needsReview == 0 && $0.pastSkipped == 0 && $0.upcoming > 0
            }
            let others = nonempty.filter {
                $0.needsReview == 0 && $0.pastSkipped == 0 && $0.upcoming == 0
            }
            return review + skipped + upcoming + others
        }
    }

    /// Conservative, non-mutating candidate for a future workout.
    /// The destination must be empty and later in the same week; explicitly
    /// timed, completed or skipped sessions are never offered for relocation.
    struct MovePreview {
        let weekID: UUID
        let sessionID: UUID
        let sourceDayID: UUID
        let destinationDayID: UUID
        let sourceDayIndex: Int
        let destinationDayIndex: Int
    }

    static func previewNextSafeMove(
        plan: TrainingPlan,
        store: AppSessionStore,
        healthWorkouts: [WorkoutSummary],
        strengthHistory: [StrengthWorkoutLog],
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> MovePreview? {
        guard let start = plan.startDate.map({ calendar.startOfDay(for: $0) }) else {
            return nil
        }
        let today = calendar.startOfDay(for: referenceDate)
        let allIDs = plan.weeks.flatMap { $0.days.flatMap { $0.sessions.map(\.id) } }
        guard Set(allIDs).count == allIDs.count else { return nil }
        for (offset, week) in plan.weeks.enumerated() {
            let days = week.days.sorted { $0.dayIndex < $1.dayIndex }
            for (index, day) in days.enumerated() {
                guard (1...7).contains(day.dayIndex),
                      let sourceDate = calendar.date(
                          byAdding: .day,
                          value: offset * 7 + day.dayIndex - 1,
                          to: start
                      ),
                      sourceDate >= today,
                      day.sessions.count == 1,
                      let workout = day.sessions.first,
                      workout.scheduledStart == nil,
                      !store.isPlanSessionSkipped(planID: plan.id, sessionID: workout.id),
                      !store.isPlanSessionCompleted(
                          planID: plan.id,
                          sessionID: workout.id,
                          healthWorkouts: healthWorkouts,
                          strengthHistory: strengthHistory
                      ) else { continue }
                for target in days.dropFirst(index + 1) {
                    guard (1...7).contains(target.dayIndex),
                          target.sessions.isEmpty,
                          let targetDate = calendar.date(
                              byAdding: .day,
                              value: offset * 7 + target.dayIndex - 1,
                              to: start
                          ),
                          targetDate > sourceDate else { continue }
                    return MovePreview(
                        weekID: week.id,
                        sessionID: workout.id,
                        sourceDayID: day.id,
                        destinationDayID: target.id,
                        sourceDayIndex: day.dayIndex,
                        destinationDayIndex: target.dayIndex
                    )
                }
            }
        }
        return nil
    }

    /// Revalidate a previously shown preview against the current plan.
    /// Never apply a stale proposal or silently change another session.
    static func validateMovePreview(
        _ preview: MovePreview,
        plan: TrainingPlan,
        store: AppSessionStore,
        healthWorkouts: [WorkoutSummary],
        strengthHistory: [StrengthWorkoutLog],
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        let allIDs = plan.weeks.flatMap { $0.days.flatMap { $0.sessions.map(\.id) } }
        guard Set(allIDs).count == allIDs.count,
              let start = plan.startDate.map({ calendar.startOfDay(for: $0) }),
              let weekOffset = plan.weeks.firstIndex(where: { $0.id == preview.weekID }),
              let source = plan.weeks[weekOffset].days.first(where: {
                  $0.id == preview.sourceDayID && $0.dayIndex == preview.sourceDayIndex
              }),
              let destination = plan.weeks[weekOffset].days.first(where: {
                  $0.id == preview.destinationDayID && $0.dayIndex == preview.destinationDayIndex
              }),
              (1...7).contains(source.dayIndex),
              (1...7).contains(destination.dayIndex),
              source.dayIndex < destination.dayIndex,
              source.sessions.count == 1,
              source.sessions[0].id == preview.sessionID,
              source.sessions[0].scheduledStart == nil,
              destination.sessions.isEmpty,
              !store.isPlanSessionSkipped(planID: plan.id, sessionID: preview.sessionID),
              !store.isPlanSessionCompleted(
                  planID: plan.id,
                  sessionID: preview.sessionID,
                  healthWorkouts: healthWorkouts,
                  strengthHistory: strengthHistory
              ),
              let sourceDate = calendar.date(
                  byAdding: .day,
                  value: weekOffset * 7 + source.dayIndex - 1,
                  to: start
              ),
              sourceDate >= calendar.startOfDay(for: referenceDate),
              let destinationDate = calendar.date(
                  byAdding: .day,
                  value: weekOffset * 7 + destination.dayIndex - 1,
                  to: start
              ),
              destinationDate > sourceDate else {
            return false
        }
        return true
    }

    static func inspect(
        plan: TrainingPlan,
        store: AppSessionStore,
        healthWorkouts: [WorkoutSummary],
        strengthHistory: [StrengthWorkoutLog],
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> Report {
        let today = calendar.startOfDay(for: referenceDate)
        let start = plan.startDate.map {
            calendar.startOfDay(for: $0)
        }
        var seen = Set<UUID>()
        var result: [Week] = []

        for (weekOffset, week) in plan.weeks.enumerated() {
            var completed = 0
            var skipped = 0
            var upcoming = 0
            var needsReview = 0
            var unknownDate = 0
            var pastDated = 0
            var pastConfirmed = 0
            var pastCompleted = 0
            var firstReviewDayID: UUID?
            var firstSkippedDayID: UUID?

            for day in week.days.sorted(by: { $0.dayIndex < $1.dayIndex }) {
                let fallback: Date?
                if let start, (1...7).contains(day.dayIndex) {
                    fallback = calendar.date(
                        byAdding: .day,
                        value: weekOffset * 7 + day.dayIndex - 1,
                        to: start
                    )
                } else {
                    fallback = nil
                }

                for workout in day.sessions {
                    guard seen.insert(workout.id).inserted else { continue }

                    let scheduled = workout.scheduledStart ?? fallback
                    let isPast = scheduled.map { calendar.startOfDay(for: $0) < today } ?? false
                    if isPast { pastDated += 1 }
                    if store.isPlanSessionSkipped(
                        planID: plan.id, sessionID: workout.id
                    ) {
                        skipped += 1
                        if isPast {
                            pastConfirmed += 1
                            if firstSkippedDayID == nil { firstSkippedDayID = day.id }
                        }
                    } else if store.isPlanSessionCompleted(
                        planID: plan.id,
                        sessionID: workout.id,
                        healthWorkouts: healthWorkouts,
                        strengthHistory: strengthHistory
                    ) {
                        completed += 1
                        if isPast {
                            pastConfirmed += 1
                            pastCompleted += 1
                        }
                    } else if let scheduled {
                        if calendar.startOfDay(for: scheduled) < today {
                            needsReview += 1
                            if firstReviewDayID == nil {
                                firstReviewDayID = day.id
                            }
                        } else {
                            // Today's workouts can still be done today.
                            upcoming += 1
                        }
                    } else {
                        // An undated template is not overdue or a missed workout.
                        unknownDate += 1
                    }
                }
            }

            result.append(Week(
                id: week.id,
                number: week.weekNumber,
                completed: completed,
                skipped: skipped,
                upcoming: upcoming,
                needsReview: needsReview,
                unknownDate: unknownDate,
                pastDated: pastDated,
                pastConfirmed: pastConfirmed,
                pastCompleted: pastCompleted,
                isFullyElapsed: start.flatMap {
                    calendar.date(byAdding: .day, value: (weekOffset + 1) * 7, to: $0)
                }.map { $0 <= today } ?? false,
                firstReviewDayID: firstReviewDayID,
                firstSkippedDayID: firstSkippedDayID
            ))
        }
        return Report(weeks: result)
    }
}
