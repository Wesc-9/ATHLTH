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
        let firstReviewDayID: UUID?

        var pastCompletionPercent: Int? {
            guard pastDated > 0 else { return nil }
            return Int((Double(pastCompleted) / Double(pastDated) * 100).rounded())
        }

        var planned: Int {
            completed + skipped + upcoming + needsReview + unknownDate
        }
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

        /// Compare only complete historical weeks. Current/partial weeks and
        /// undated sessions are excluded to avoid misleading trends.
        var completedWeekTrend: (previous: Week, latest: Week, delta: Int)? {
            let eligible = weeks.filter {
                $0.pastDated > 0 && $0.upcoming == 0 && $0.unknownDate == 0
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
            let upcoming = nonempty.filter {
                $0.needsReview == 0 && $0.upcoming > 0
            }
            let others = nonempty.filter {
                $0.needsReview == 0 && $0.upcoming == 0
            }
            return review + upcoming + others
        }
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
                        if isPast { pastConfirmed += 1 }
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
                firstReviewDayID: firstReviewDayID
            ))
        }
        return Report(weeks: result)
    }
}
