import Foundation

/// Non-AI, evidence-only recommendations. Suggestions never mutate a workout.
/// The athlete must review and approve a specific pending change.
enum ATHLTHTrainProgressionCoach {
    struct Suggestion: Identifiable, Hashable {
        var id: UUID { exerciseID }
        let workoutID: UUID
        let exerciseID: UUID
        let exerciseName: String
        let workoutName: String
        let scheduledDate: Date
        let weekNumber: Int
        let beforeLoad: Double
        let proposedLoad: Double
        let matchingFinishedWorkouts: Int
        let workingSetsVerified: Int
        let reasoning: String
    }

    /// Count distinct finished workouts where every logged working set
    /// (with a prescribed target) met both the rep and load targets.
    private struct Evidence {
        let date: Date
        let workoutID: UUID
        let exercise: ExerciseSnapshot
        let workingSetIDs: [UUID]
        let minimumWorkingWeightKg: Double
        let metTargets: Bool
    }

    static func suggestions(
        plan: TrainingPlan,
        strengthHistory: [StrengthWorkoutLog],
        completedSessionIDs: Set<UUID>,
        skippedSessionIDs: Set<UUID>,
        increaseKg: Double = 1,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [Suggestion] {
        guard increaseKg.isFinite, (0.5...5).contains(increaseKg),
              let start = plan.startDate else { return [] }

        let plannedIDs = Set(plan.weeks.flatMap(\.days)
            .flatMap(\.sessions).map(\.id))
        let logList = strengthHistory.filter {
            $0.isFinished &&
            ($0.endedAt ?? $0.startedAt) <= now &&
            $0.plannedSessionID.map(plannedIDs.contains) == true
        }
        var evidenceByIdentity: [String: [Evidence]] = [:]
        var seenLogIDs = Set<UUID>()
        for log in logList {
            guard seenLogIDs.insert(log.id).inserted else { continue }
            var grouped: [String: [StrengthExerciseLog]] = [:]
            for entry in log.exercises {
                guard let key = ATHLTHCoachStrengthComparableHistory
                    .identityKey(for: entry.exercise) else { continue }
                grouped[key, default: []].append(entry)
            }
            for (key, entries) in grouped {
                guard let entry = entries.first else { continue }
                // Repeated occurrences in one session are ambiguous and
                // cannot be counted as successful independent evidence.
                let evidence = entries.count == 1
                    ? ATHLTHCoachStrengthComparableHistory.targetEvidence(
                        for: entry
                    )
                    : nil
                evidenceByIdentity[key, default: []].append(Evidence(
                    date: log.endedAt ?? log.startedAt,
                    workoutID: log.id,
                    exercise: entry.exercise,
                    workingSetIDs: evidence?.workingSetIDs ?? [],
                    minimumWorkingWeightKg: evidence?.minimumRecordedWeightKg ?? 0,
                    metTargets: evidence?.metAllTargets == true
                ))
            }
        }

        let startDay = calendar.startOfDay(for: start)
        let today = calendar.startOfDay(for: now)
        var suggestions: [Suggestion] = []
        var suggestedNames = Set<String>()
        for (weekIndex, week) in plan.weeks.enumerated() {
            for day in week.days.sorted(by: { $0.dayIndex < $1.dayIndex }) {
                guard let scheduledDay = calendar.date(
                    byAdding: .day,
                    value: weekIndex * 7 + day.dayIndex - 1,
                    to: startDay
                ), scheduledDay >= today else { continue }

                for workout in day.sessions where workout.kind == .strength {
                    guard !completedSessionIDs.contains(workout.id),
                          !skippedSessionIDs.contains(workout.id) else { continue }
                    for exercise in workout.exercises {
                        let name = exercise.embeddedExercise.displayName
                        guard let identityKey = ATHLTHCoachStrengthComparableHistory
                            .identityKey(for: exercise.embeddedExercise),
                              !suggestedNames.contains(identityKey),
                              exercise.resolvedTargetKind == .reps,
                              exercise.resolvedLoadKind == .weightKilograms,
                              let current = plannedWorkingLoad(exercise),
                              current > 0 else { continue }

                        let records = (evidenceByIdentity[identityKey] ?? [])
                            .filter {
                                $0.date < now &&
                                ATHLTHCoachStrengthComparableHistory.isSameExercise(
                                    $0.exercise, exercise.embeddedExercise
                                )
                            }
                            .sorted { $0.date > $1.date }
                        // Require two distinct verified finished sessions,
                        // not two sets from the same session.
                        var unique: [Evidence] = []
                        var usedIDs = Set<UUID>()
                        for record in records where usedIDs.insert(record.workoutID).inserted {
                            unique.append(record)
                            if unique.count == 2 { break }
                        }
                        let assessment = ATHLTHCoachStrengthDecision.assess(
                            evidence: unique.map {
                                ATHLTHCoachStrengthDecision.Evidence(
                                    workoutID: $0.workoutID,
                                    date: $0.date,
                                    workingSetIDs: $0.workingSetIDs,
                                    minimumWorkingWeightKg: $0.minimumWorkingWeightKg,
                                    metTargets: $0.metTargets
                                )
                            },
                            prescribedLoadKg: current,
                            incrementKg: increaseKg
                        )
                        guard assessment.action == .reviewSmallIncrease,
                              let proposed = assessment.proposedWeightKg else { continue }
                        suggestedNames.insert(identityKey)
                        suggestions.append(Suggestion(
                            workoutID: workout.id,
                            exerciseID: exercise.id,
                            exerciseName: name,
                            workoutName: workout.title,
                            scheduledDate: scheduledDay,
                            weekNumber: weekIndex + 1,
                            beforeLoad: current,
                            proposedLoad: proposed,
                            matchingFinishedWorkouts: assessment.sourceWorkoutIDs.count,
                            workingSetsVerified: assessment.sourceSetIDs.count,
                            reasoning: "ATHLTH Coach: targets verified in two distinct linked workouts. The proposed increase is limited and requires your approval."
                        ))
                    }
                }
            }
        }
        return suggestions
    }

    struct RepetitionSuggestion: Identifiable, Hashable {
        var id: UUID { exerciseID }
        let workoutID: UUID
        let exerciseID: UUID
        let exerciseName: String
        let workoutName: String
        let scheduledDate: Date
        let beforeReps: Int
        let proposedReps: Int
        let prescribedWeightKg: Double
        let supportingSessions: Int
        let supportingSets: Int
    }

    struct VolumeReviewSuggestion: Identifiable, Hashable {
        var id: UUID { exerciseID }
        let workoutID: UUID
        let exerciseID: UUID
        let exerciseName: String
        let workoutName: String
        let scheduledDate: Date
        let currentReps: Int
        let currentWeightKg: Double
        let comparableWorkouts: Int
        let verifiedWorkingSets: Int
        /// This is a review prompt, never an automatic set prescription.
        let sourceWorkoutIDs: [UUID]
    }

    /// Separate entry points, one shared scan/policy for both results.
    static func volumeReviewSuggestions(
        plan: TrainingPlan,
        strengthHistory: [StrengthWorkoutLog],
        completedSessionIDs: Set<UUID>,
        skippedSessionIDs: Set<UUID>,
        range: ATHLTHCoachStrengthRepetitionVolume.RepRange,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [VolumeReviewSuggestion] {
        progressionReviews(
            plan: plan,
            strengthHistory: strengthHistory,
            completedSessionIDs: completedSessionIDs,
            skippedSessionIDs: skippedSessionIDs,
            range: range,
            now: now,
            calendar: calendar
        ).volumes
    }

    /// An explicit range is required; goal comes from the saved plan.
    /// No future workout, completed workout, or saved history is modified.
    static func repetitionSuggestions(
        plan: TrainingPlan,
        strengthHistory: [StrengthWorkoutLog],
        completedSessionIDs: Set<UUID>,
        skippedSessionIDs: Set<UUID>,
        range: ATHLTHCoachStrengthRepetitionVolume.RepRange,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [RepetitionSuggestion] {
        progressionReviews(
            plan: plan,
            strengthHistory: strengthHistory,
            completedSessionIDs: completedSessionIDs,
            skippedSessionIDs: skippedSessionIDs,
            range: range,
            now: now,
            calendar: calendar
        ).repetitions
    }

    private static func progressionReviews(
        plan: TrainingPlan,
        strengthHistory: [StrengthWorkoutLog],
        completedSessionIDs: Set<UUID>,
        skippedSessionIDs: Set<UUID>,
        range: ATHLTHCoachStrengthRepetitionVolume.RepRange,
        now: Date,
        calendar: Calendar
    ) -> (repetitions: [RepetitionSuggestion], volumes: [VolumeReviewSuggestion]) {
        guard let goal = plan.builderProfile?.goal,
              goal == .getStronger || goal == .buildMuscle,
              let planStart = plan.startDate else { return ([], []) }
        let plannedIDs = Set(plan.weeks.flatMap(\.days).flatMap(\.sessions).map(\.id))
        let cutoff = now.addingTimeInterval(-56 * 86_400)
        let completed = strengthHistory.filter {
            $0.isFinished &&
            $0.plannedSessionID.map(plannedIDs.contains) == true &&
            ($0.endedAt ?? $0.startedAt) < now &&
            ($0.endedAt ?? $0.startedAt) >= cutoff
        }
        let start = calendar.startOfDay(for: planStart)
        let today = calendar.startOfDay(for: now)
        var result: [RepetitionSuggestion] = []
        var volumeReviews: [VolumeReviewSuggestion] = []
        var usedExerciseKeys = Set<String>()

        for (weekIndex, week) in plan.weeks.enumerated() {
            for day in week.days {
                guard let scheduled = calendar.date(
                    byAdding: .day,
                    value: weekIndex * 7 + day.dayIndex - 1,
                    to: start
                ), scheduled >= today else { continue }
                for workout in day.sessions where workout.kind == .strength {
                    guard !completedSessionIDs.contains(workout.id),
                          !skippedSessionIDs.contains(workout.id) else { continue }
                    for planned in workout.exercises {
                        guard planned.resolvedTargetKind == .reps,
                              planned.resolvedLoadKind == .weightKilograms,
                              let prescription = uniformRepetitionPrescription(planned),
                              range.lower <= prescription.reps,
                              prescription.reps <= range.upper,
                              let identity = ATHLTHCoachStrengthComparableHistory
                                  .identityKey(for: planned.embeddedExercise),
                              !usedExerciseKeys.contains(identity) else { continue }

                        var sessionEvidence: [ATHLTHCoachStrengthRepetitionVolume.Session] = []
                        for logged in completed {
                            let date = logged.endedAt ?? logged.startedAt
                            let matches = logged.exercises.filter {
                                ATHLTHCoachStrengthComparableHistory.isSameExercise(
                                    $0.exercise, planned.embeddedExercise
                                )
                            }
                            guard !matches.isEmpty else { continue }
                            // Multiple occurrences in one workout are not
                            // independent successes; require manual review.
                            let sample = matches.count == 1 ? matches.first.flatMap {
                                ATHLTHCoachStrengthRepetitionVolume.evidence(
                                    workoutID: logged.id,
                                    date: date,
                                    exercise: $0,
                                    prescribedLoadKg: prescription.load
                                )
                            } : nil
                            if let sample {
                                sessionEvidence.append(sample)
                            } else {
                                // An invalid latest attempt cannot vanish and
                                // reveal older successes as the most recent.
                                sessionEvidence.append(
                                    ATHLTHCoachStrengthRepetitionVolume.Session(
                                        workoutID: logged.id,
                                        date: date,
                                        workingSetIDs: [],
                                        minimumReps: 0,
                                        minimumWeightKg: 0,
                                        allTargetsMet: false,
                                        effortSupportsMore: false
                                    )
                                )
                            }
                        }
                        let assessment = ATHLTHCoachStrengthRepetitionVolume.assess(
                            sessions: sessionEvidence,
                            goal: goal,
                            range: range,
                            prescribedReps: prescription.reps,
                            prescribedLoadKg: prescription.load
                        )
                        switch assessment.action {
                        case .reviewOneMoreRep:
                            guard let next = assessment.proposedReps else { continue }
                            usedExerciseKeys.insert(identity)
                            result.append(RepetitionSuggestion(
                                workoutID: workout.id,
                                exerciseID: planned.id,
                                exerciseName: planned.embeddedExercise.displayName,
                                workoutName: workout.title,
                                scheduledDate: scheduled,
                                beforeReps: prescription.reps,
                                proposedReps: next,
                                prescribedWeightKg: prescription.load,
                                supportingSessions: min(2, assessment.sourceWorkoutIDs.count),
                                supportingSets: assessment.sourceSetIDs.count
                            ))
                        case .reviewTrainingVolume:
                            guard goal == .buildMuscle else { continue }
                            usedExerciseKeys.insert(identity)
                            volumeReviews.append(VolumeReviewSuggestion(
                                workoutID: workout.id,
                                exerciseID: planned.id,
                                exerciseName: planned.embeddedExercise.displayName,
                                workoutName: workout.title,
                                scheduledDate: scheduled,
                                currentReps: prescription.reps,
                                currentWeightKg: prescription.load,
                                comparableWorkouts: min(3, assessment.sourceWorkoutIDs.count),
                                verifiedWorkingSets: assessment.sourceSetIDs.count,
                                sourceWorkoutIDs: Array(assessment.sourceWorkoutIDs.prefix(3))
                            ))
                        case .collectEvidence, .hold:
                            break
                        }
                    }
                }
            }
        }
        return (result, volumeReviews)
    }

    /// Reject mixed working prescriptions instead of changing unrelated sets.
    static func uniformRepetitionPrescription(
        _ exercise: PlannedExercise
    ) -> (reps: Int, load: Double)? {
        guard exercise.resolvedTargetKind == .reps,
              exercise.resolvedLoadKind == .weightKilograms else { return nil }
        if exercise.hasIndividualSetTargets {
            let targets = exercise.resolvedSetTargets.filter {
                $0.isWarmUp != true && $0.setType != .warmUp
            }
            guard targets.count >= 2,
                  let first = targets.first,
                  let reps = first.reps, reps > 0,
                  let weight = first.weightKilograms, weight.isFinite, weight > 0,
                  targets.allSatisfy({
                      $0.reps == reps &&
                      $0.weightKilograms == weight
                  }) else { return nil }
            return (reps, weight)
        }
        guard exercise.sets >= 2,
              let reps = exercise.reps, reps > 0,
              let weight = exercise.targetWeightKilograms,
              weight.isFinite, weight > 0 else { return nil }
        return (reps, weight)
    }

    /// Safe, approved change for *one* future planned exercise. Does not touch
    /// other workouts, warm-ups, IDs, time-based sets or recorded history.
    static func adjustedExerciseRepetitions(
        _ original: PlannedExercise,
        expectedReps: Int,
        approvedReps: Int,
        range: ATHLTHCoachStrengthRepetitionVolume.RepRange
    ) -> PlannedExercise? {
        guard let current = uniformRepetitionPrescription(original),
              current.reps == expectedReps,
              approvedReps == current.reps + 1,
              approvedReps <= range.upper,
              current.reps >= range.lower else { return nil }
        var updated = original
        if original.hasIndividualSetTargets {
            updated.setTargets = original.setTargets?.map { target in
                var copy = target
                if target.isWarmUp != true && target.setType != .warmUp {
                    copy.reps = approvedReps
                }
                return copy
            }
        }
        updated.reps = approvedReps
        return updated == original ? nil : updated
    }

    static func plannedWorkingLoad(_ exercise: PlannedExercise) -> Double? {
        guard exercise.resolvedTargetKind == .reps,
              exercise.resolvedLoadKind == .weightKilograms else { return nil }
        if exercise.hasIndividualSetTargets {
            let working = exercise.resolvedSetTargets.filter {
                $0.isWarmUp != true && $0.setType != .warmUp
            }
            let weights = working.compactMap(\.weightKilograms)
            // Mixed/unprescribed loads should be reviewed manually.
            guard !working.isEmpty, weights.count == working.count,
                  weights.allSatisfy({ $0.isFinite && $0 > 0 }) else { return nil }
            return weights.max()
        }
        guard let current = exercise.targetWeightKilograms,
              current.isFinite && current > 0 else { return nil }
        return current
    }

    /// Apply a reviewed delta to positive prescribed *working* loads only.
    /// Warm-up sets, 0 kg, unprescribed sets and non-weight exercises remain.
    static func adjustedExercise(
        _ original: PlannedExercise,
        increaseKg: Double
    ) -> PlannedExercise? {
        guard increaseKg.isFinite, (0.5...5).contains(increaseKg),
              plannedWorkingLoad(original) != nil else { return nil }
        var result = original
        if original.hasIndividualSetTargets {
            result.setTargets = original.setTargets?.map { target in
                var target = target
                guard target.isWarmUp != true,
                      target.setType != .warmUp,
                      let value = target.weightKilograms,
                      value > 0 else { return target }
                target.weightKilograms = (value + increaseKg).rounded(toPlaces: 2)
                return target
            }
            // Mirror the first working prescription into the Basic display,
            // without turning an unprescribed target into a prescription.
            if let firstWorking = result.setTargets?.first(where: {
                $0.isWarmUp != true && $0.setType != .warmUp
            }), firstWorking.weightKilograms != nil {
                result.targetWeightKilograms = firstWorking.weightKilograms
            }
        } else if let current = original.targetWeightKilograms {
            result.targetWeightKilograms = (current + increaseKg).rounded(toPlaces: 2)
        }
        return result == original ? nil : result
    }
}

private extension Double {
    func rounded(toPlaces digits: Int) -> Double {
        let factor = pow(10, Double(digits))
        return (self * factor).rounded() / factor
    }
}
