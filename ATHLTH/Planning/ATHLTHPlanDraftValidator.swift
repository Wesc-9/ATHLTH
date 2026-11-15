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
        requireFullWeeks: Bool = false,
        requireExecutableWorkouts: Bool = false
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
                    if requireExecutableWorkouts {
                        let authored = workout.authoredWorkout?.resolvedWorkoutBlocks ?? []
                        let isStrength = workout.kind == "strength"
                        let isCardio = workout.kind == "running" ||
                            workout.kind == "walking"
                        let playableStrength = workout.exercises.contains {
                            !$0.name.trimmingCharacters(
                                in: .whitespacesAndNewlines
                            ).isEmpty && $0.sets > 0 &&
                                ($0.reps ?? 0) > 0
                        } || (workout.blocks ?? []).contains {
                            $0.kind == "exercise" &&
                                (($0.repetitions ?? 0) > 0 ||
                                 ($0.durationSeconds ?? 0) > 0)
                        } || authored.contains {
                            $0.kind == .exercise &&
                                (($0.repetitions ?? 0) > 0 ||
                                 ($0.durationSeconds ?? 0) > 0)
                        }
                        if isStrength && !playableStrength {
                            issues.append("strength_missing_structured_sets")
                        }
                        if isCardio {
                            let timedBlocks = (workout.blocks ?? []).filter {
                                $0.kind == "run" &&
                                (($0.durationSeconds ?? 0) > 0 ||
                                 ($0.distanceMeters ?? 0) > 0)
                            }
                            let authoredRun = authored.contains {
                                $0.kind == .run &&
                                    (($0.durationSeconds ?? 0) > 0 ||
                                     ($0.distanceMeters ?? 0) > 0)
                            }
                            if timedBlocks.isEmpty && !authoredRun &&
                                (workout.durationMinutes ?? 0) <= 0 &&
                                (workout.targetDistanceKilometers ?? 0) <= 0 {
                                issues.append("cardio_missing_executable_target")
                            }
                            let lower = workout.title.lowercased()
                            let interval = lower.contains("interval") ||
                                lower.contains("intervall") ||
                                lower.contains("4x4") ||
                                lower.contains("4×4")
                            if interval {
                                let main = (workout.blocks ?? []).filter {
                                    $0.kind == "run" && $0.phase == "main"
                                }.count
                                let recovery = (workout.blocks ?? []).contains {
                                    $0.kind == "rest" || $0.phase == "recovery"
                                }
                                let actualMain = authored.filter {
                                    $0.kind == .run && $0.resolvedPhase == .main
                                }.count
                                let actualRecovery = authored.contains {
                                    $0.kind == .rest || $0.resolvedPhase == .recovery
                                }
                                if (main < 2 || !recovery) &&
                                    (actualMain < 2 || !actualRecovery) {
                                    issues.append("interval_missing_drags")
                                }
                            }
                        }
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
