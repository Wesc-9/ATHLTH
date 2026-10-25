import Foundation

/// Canonical plan timeline. Day indexes represent offsets from a plan's
/// start date (day 1 = start date), not ISO weekdays. A moved workout's
/// explicit scheduledStart overrides its original day position.
enum TrainingPlanSchedule {
    static func dayDate(
        in plan: TrainingPlan,
        week: TrainingPlanWeek,
        day: TrainingPlanDay,
        calendar: Calendar = .current
    ) -> Date? {
        guard let startDate = plan.startDate else { return nil }
        let offset = max(week.weekNumber - 1, 0) * 7 +
            max(day.dayIndex - 1, 0)
        return calendar.date(
            byAdding: .day,
            value: offset,
            to: calendar.startOfDay(for: startDate)
        )
    }

    static func occurrences(
        in plan: TrainingPlan,
        calendar: Calendar = .current
    ) -> [TrainingPlanSessionOccurrence] {
        var result: [TrainingPlanSessionOccurrence] = []
        for week in plan.weeks {
            for day in week.days {
                let fallback = dayDate(
                    in: plan,
                    week: week,
                    day: day,
                    calendar: calendar
                )
                for session in day.sessions {
                    // Unscheduled templates have no reliable calendar date.
                    // Active plans normally have a start date.
                    guard let date = session.scheduledStart ?? fallback else {
                        continue
                    }
                    result.append(
                        TrainingPlanSessionOccurrence(
                            planID: plan.id,
                            session: session,
                            date: date,
                            weekNumber: week.weekNumber
                        )
                    )
                }
            }
        }
        return result.sorted { lhs, rhs in
            if lhs.date == rhs.date {
                return lhs.session.title < rhs.session.title
            }
            return lhs.date < rhs.date
        }
    }

    static func sessions(
        in plan: TrainingPlan,
        on date: Date,
        calendar: Calendar = .current
    ) -> [PlannedSession] {
        guard let startDate = plan.startDate else { return [] }
        let target = calendar.startOfDay(for: date)
        guard target >= calendar.startOfDay(for: startDate),
              target <= calendar.startOfDay(
                for: plan.endDate ??
                    calendar.date(
                        byAdding: .day,
                        value: max(plan.weeks.count * 7 - 1, 0),
                        to: calendar.startOfDay(for: startDate)
                    ) ?? startDate
              )
        else {
            return []
        }
        return occurrences(in: plan, calendar: calendar)
            .filter { calendar.isDate($0.date, inSameDayAs: date) }
            .map(\.session)
    }

    /// Rest is intentional, never inferred from an empty date. A workout
    /// moved onto this day takes precedence if older data contains a conflict.
    static func isRestDay(
        in plan: TrainingPlan,
        on date: Date,
        calendar: Calendar = .current
    ) -> Bool {
        guard sessions(in: plan, on: date, calendar: calendar).isEmpty else {
            return false
        }
        return plan.weeks.contains { week in
            week.days.contains { day in
                guard day.isRestDay == true,
                      let plannedDate = dayDate(
                        in: plan, week: week, day: day, calendar: calendar
                      )
                else { return false }
                return calendar.isDate(plannedDate, inSameDayAs: date)
            }
        }
    }

    /// A health-only workout has no intrinsic plan identity. Only accept an
    /// automatic match when it has a specific planned clock time, exactly one
    /// candidate workout, and a compatible activity. Otherwise the user can
    /// confirm completion manually; never assign an unrelated free workout.
    static func confidentHealthCompletionIDs(
        sessions: [PlannedSession],
        healthWorkouts: [WorkoutSummary],
        on date: Date,
        calendar: Calendar = .current
    ) -> Set<UUID> {
        var completed = Set<UUID>()
        var used = Set<UUID>()

        for planned in sessions {
            guard let scheduled = planned.scheduledStart,
                  calendar.isDate(scheduled, inSameDayAs: date)
            else { continue }

            let clock = calendar.dateComponents([.hour, .minute], from: scheduled)
            // A midnight scheduledStart commonly means "date only" after
            // rescheduling and is not strong evidence of a timed workout.
            guard clock.hour != 0 || clock.minute != 0 else { continue }
            guard sessions.filter({ $0.kind == planned.kind }).count == 1 else {
                continue
            }

            let candidates = healthWorkouts.filter { workout in
                guard !used.contains(workout.id),
                      calendar.isDate(workout.startDate, inSameDayAs: date),
                      abs(workout.startDate.timeIntervalSince(scheduled)) <= 90 * 60,
                      activityMatches(workout.activity, planned: planned.kind)
                else { return false }

                if let km = planned.targetDistanceKilometers,
                   km > 0,
                   let meters = workout.distanceMeters {
                    let ratio = meters / (km * 1_000)
                    guard (0.65...1.35).contains(ratio) else { return false }
                }
                return true
            }

            // If multiple workouts meet the same intent there is no reliable
            // automatic association; leave this plan item unconfirmed.
            guard candidates.count == 1,
                  let matching = candidates.first
            else { continue }

            completed.insert(planned.id)
            used.insert(matching.id)
        }
        return completed
    }

    private static func activityMatches(
        _ activity: WorkoutActivity,
        planned: WorkoutKind
    ) -> Bool {
        switch planned {
        case .running: return activity == .running
        case .walking: return activity == .walking || activity == .hiking
        case .strength: return activity == .strength
        case .mobility: return activity == .yoga || activity == .coreTraining
        case .recovery: return false
        case .custom:
            return activity == .hiit || activity == .rowing ||
                activity == .cycling || activity == .stairClimbing ||
                activity == .other
        }
    }
}
