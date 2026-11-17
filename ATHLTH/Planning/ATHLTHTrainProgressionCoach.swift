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
        var evidenceByName: [String: [Evidence]] = [:]
        var seenLogIDs = Set<UUID>()
        for log in logList {
            guard seenLogIDs.insert(log.id).inserted else { continue }
            for entry in log.exercises {
                let key = ATHLTHTrainTrendEngine.normalize(entry.exercise.name)
                guard !key.isEmpty else { continue }
                // The same Coach evidence policy is used for scheduled
                // plans and live training. Skipped or invalid working sets
                // never qualify as successful attempts.
                let evidence = ATHLTHCoachStrengthComparableHistory
                    .targetEvidence(for: entry)
                evidenceByName[key, default: []].append(Evidence(
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
                        let key = ATHLTHTrainTrendEngine.normalize(
                            exercise.embeddedExercise.name
                        )
                        let identityKey = key + "|" +
                            exercise.embeddedExercise.equipment
                                .map(ATHLTHTrainTrendEngine.normalize)
                                .sorted()
                                .joined(separator: ";") +
                            "|" + (exercise.embeddedExercise.libraryExerciseID?.uuidString ?? "")
                        guard !key.isEmpty,
                              !suggestedNames.contains(identityKey),
                              exercise.resolvedTargetKind == .reps,
                              exercise.resolvedLoadKind == .weightKilograms,
                              let current = plannedWorkingLoad(exercise),
                              current > 0 else { continue }

                        let records = (evidenceByName[key] ?? [])
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
