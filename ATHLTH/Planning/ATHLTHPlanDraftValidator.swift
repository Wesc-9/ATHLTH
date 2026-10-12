import Foundation

/// Defensive schema validation of generated training programs before the user
/// is offered the option of saving or filling a plan. This is NOT a medical
/// or complete sports-science validation engine.
enum ATHLTHPlanDraftValidator {
    static func issues(
        in draft: AIProgramDraft,
        expectedWeeks: Int? = nil,
        allowedDayIndexes: Set<Int>? = nil,
        maximumSessionsPerWeek: Int? = nil,
        lockedDayKeys: Set<String> = [],
        requireFullWeeks: Bool = false
    ) -> [String] {
        var issues: [String] = []
        if draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append("missing_title")
        }
        if draft.weeks.isEmpty || draft.weeks.count > 52 {
            issues.append("invalid_week_count")
        }
        if let expectedWeeks, draft.weeks.count != expectedWeeks {
            issues.append("incomplete_program")
        }
        if draft.sessionCount == 0 {
            issues.append("no_sessions")
        }

        for (index, week) in draft.weeks.enumerated() {
            if week.weekNumber != index + 1 {
                issues.append("week_order")
            }

            let indices = week.days.map(\.dayIndex)
            if requireFullWeeks && Set(indices) != Set(1...7) {
                issues.append("incomplete_week_days")
            }
            let weekSessionCount = week.days.reduce(0) { $0 + $1.sessions.count }
            if let maximumSessionsPerWeek, weekSessionCount > maximumSessionsPerWeek {
                issues.append("exceeds_weekly_session_limit")
            }
            if Set(indices).count != indices.count ||
                indices.contains(where: { !(1...7).contains($0) }) {
                issues.append("invalid_day_indices")
            }

            for day in week.days {
                if !day.sessions.isEmpty,
                   let allowedDayIndexes,
                   !allowedDayIndexes.contains(day.dayIndex) {
                    issues.append("outside_available_days")
                }
                if !day.sessions.isEmpty,
                   lockedDayKeys.contains("\(week.weekNumber):\(day.dayIndex)") {
                    issues.append("overwrites_existing_workout")
                }
                if requireFullWeeks && day.sessions.count > 1 {
                    issues.append("multiple_sessions_on_day")
                }
                if day.sessions.count > 5 {
                    issues.append("too_many_daily_sessions")
                }
                for workout in day.sessions {
                    if workout.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        issues.append("missing_workout_title")
                    }
                    if let duration = workout.durationMinutes,
                       !(1...360).contains(duration) {
                        issues.append("invalid_duration")
                    }
                    if let distance = workout.targetDistanceKilometers,
                       !distance.isFinite || distance <= 0 {
                        issues.append("invalid_distance")
                    }
                    if let pace = workout.targetPaceSecondsPerKilometer,
                       !pace.isFinite || pace <= 0 {
                        issues.append("invalid_pace")
                    }
                    for exercise in workout.exercises {
                        if exercise.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                           !(1...30).contains(exercise.sets) ||
                           exercise.reps.map({ !(1...1000).contains($0) }) == true ||
                           exercise.restSeconds.map({ !(0...3600).contains($0) }) == true ||
                           exercise.targetRPE.map({ !$0.isFinite || !(1...10).contains($0) }) == true {
                            issues.append("invalid_exercise")
                        }
                    }
                }
            }
        }

        return Array(Set(issues)).sorted()
    }
}
