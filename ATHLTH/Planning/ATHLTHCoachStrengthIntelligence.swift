import Foundation

/// Local, read-only training intelligence for ATHLTH Coach.
/// Inspired by GymCoach's evidence-first training context, but operates only
/// on ATHLTH's existing on-device workout records. No AI, network or mutation.
enum ATHLTHCoachStrengthIntelligence {
    struct ExerciseSignal: Encodable, Equatable {
        let exercise: String
        let completedSessions: Int
        let mostRecentWorkingWeightKg: Double?
        let bestEstimatedOneRepMaxKg: Double?
        let trend: String
        let recommendation: String
        let evidence: String
    }

    struct Snapshot: Encodable, Equatable {
        let windowDays: Int
        let completedStrengthSessions: Int
        let strengthSessionsLastSevenDays: Int
        let completedWorkingSets: Int
        let recordedVolumeKg: Double
        let exerciseSignals: [ExerciseSignal]

        var hasEvidence: Bool { completedStrengthSessions > 0 }
        var summary: String {
            guard hasEvidence else {
                return ATHLTHLocalization.choose(
                    english: "No completed strength workouts found in the past eight weeks.",
                    norwegian: "Ingen fullførte styrkeøkter funnet de siste åtte ukene."
                )
            }
            let base = ATHLTHLocalization.choose(
                english: "\(completedStrengthSessions) strength sessions in eight weeks, \(strengthSessionsLastSevenDays) in the last seven days, \(completedWorkingSets) completed working sets.",
                norwegian: "\(completedStrengthSessions) styrkeøkter på åtte uker, \(strengthSessionsLastSevenDays) siste syv dager, \(completedWorkingSets) fullførte arbeidssett."
            )
            guard let notable = exerciseSignals.first else { return base }
            let more = ATHLTHLocalization.choose(
                english: "Latest focus: \(notable.exercise) (\(notable.trend)).",
                norwegian: "Siste analyse: \(notable.exercise) (\(notable.trend))."
            )
            return base + " " + more
        }
    }

    private struct SetEvidence {
        let actualWeight: Double?
        let actualReps: Int?
        let estimatedOneRepMax: Double?
        let metPlannedTarget: Bool?
    }

    private struct SessionEvidence {
        let id: UUID
        let date: Date
        let load: Double?
        let oneRepMax: Double?
        let verifiedTargetSuccess: Bool
        let workingSets: Int
    }

    /// Conservative Epley estimate for recorded external loads only.
    /// Excludes unweighted exercises and sets outside 1...12 repetitions;
    /// neither cardio samples nor manually entered resistance levels are 1RM.
    static func estimatedOneRepMax(weightKg: Double, reps: Int) -> Double? {
        guard weightKg.isFinite, weightKg > 0,
              (1...12).contains(reps) else { return nil }
        let value = weightKg * (1 + Double(reps) / 30)
        return (value * 10).rounded() / 10
    }

    static func snapshot(
        from history: [StrengthWorkoutLog],
        now: Date = Date(),
        maxExercises: Int = 10
    ) -> Snapshot {
        let start = now.addingTimeInterval(-56 * 86_400)
        let recentCutoff = now.addingTimeInterval(-7 * 86_400)
        var seenLogs = Set<UUID>()
        let completed = history.filter { log in
            let date = log.endedAt ?? log.startedAt
            return log.isFinished &&
                seenLogs.insert(log.id).inserted &&
                date <= now && date >= start
        }
        var grouped: [String: (display: String, entries: [SessionEvidence])] = [:]
        var totalSets = 0
        var totalVolume = 0.0

        for log in completed {
            let day = log.endedAt ?? log.startedAt
            for exercise in log.exercises where exercise.isEmbeddedRunningInterval != true {
                let key = ATHLTHTrainTrendEngine.normalize(exercise.exercise.name)
                guard !key.isEmpty else { continue }
                let sets = exercise.sets.filter {
                    $0.countsTowardTrainingLoad &&
                        $0.resolvedLoadKind == .weightKilograms
                }
                guard !sets.isEmpty else { continue }
                totalSets += sets.count
                totalVolume += sets.reduce(0) { $0 + $1.volumeKilograms }
                let evidence = sets.map(setEvidence)
                let valid = evidence.compactMap(\.estimatedOneRepMax).max()
                let latestLoad = evidence.compactMap(\.actualWeight).max()
                // At least two prescribed working sets must have both a
                // verified rep target and load target before we advise adding weight.
                let allTargetsMet = sets.count >= 2 &&
                    evidence.allSatisfy { $0.metPlannedTarget == true }
                let item = SessionEvidence(
                    id: log.id, date: day, load: latestLoad,
                    oneRepMax: valid, verifiedTargetSuccess: allTargetsMet,
                    workingSets: sets.count
                )
                if grouped[key] == nil {
                    grouped[key] = (display: String(exercise.exercise.name.prefix(100)), entries: [])
                }
                grouped[key]?.entries.append(item)
            }
        }

        let entries: [(date: Date, signal: ExerciseSignal)] = grouped.values.compactMap { group in
            var observedSessionIDs = Set<UUID>()
            let records = group.entries
                .sorted { $0.date > $1.date }
                .filter { observedSessionIDs.insert($0.id).inserted }
            guard let latest = records.first else { return nil }
            let best = records.compactMap(\.oneRepMax).max()
            let qualified = records.filter { $0.oneRepMax != nil }
            let trend: String
            if qualified.count >= 3,
               let oldest = qualified.last, let first = qualified.first,
               let earlier = oldest.oneRepMax, let latest = first.oneRepMax,
               first.date.timeIntervalSince(oldest.date) >= 14 * 86_400,
               latest <= earlier * 1.02 {
                trend = "plateau"
            } else if qualified.count >= 2,
                      let oldest = qualified.last?.oneRepMax,
                      let newest = qualified.first?.oneRepMax,
                      newest >= oldest * 1.025 {
                trend = "improving"
            } else {
                trend = "insufficient_evidence"
            }

            let recommendation: String
            let evidenceText: String
            if records.count >= 2 &&
               records[0].verifiedTargetSuccess &&
               records[1].verifiedTargetSuccess &&
               records[0].load != nil && records[1].load != nil {
                recommendation = "review_small_increase"
                evidenceText = "Targets met in two distinct completed sessions; consider a small, athlete-approved weight increase."
            } else if trend == "plateau" {
                recommendation = "review_plateau"
                evidenceText = "No clear estimated strength increase across at least three sessions spanning two weeks; review fatigue, load, technique and goals."
            } else {
                recommendation = "hold_and_collect_evidence"
                evidenceText = "Keep planned training unless individual targets and recovery justify changing it."
            }
            return (
                date: latest.date,
                signal: ExerciseSignal(
                    exercise: group.display,
                    completedSessions: Set(records.map(\.id)).count,
                    mostRecentWorkingWeightKg: latest.load,
                    bestEstimatedOneRepMaxKg: best,
                    trend: trend,
                    recommendation: recommendation,
                    evidence: evidenceText
                )
            )
        }
        let sorted = entries.sorted {
            $0.date == $1.date
                ? $0.signal.exercise < $1.signal.exercise
                : $0.date > $1.date
        }
        return Snapshot(
            windowDays: 56,
            completedStrengthSessions: completed.count,
            strengthSessionsLastSevenDays: completed.filter {
                ($0.endedAt ?? $0.startedAt) >= recentCutoff
            }.count,
            completedWorkingSets: totalSets,
            recordedVolumeKg: (totalVolume * 10).rounded() / 10,
            exerciseSignals: Array(sorted.prefix(min(max(maxExercises, 0), 12)).map(\.signal))
        )
    }

    private static func setEvidence(_ set: StrengthSetLog) -> SetEvidence {
        let values: [(weight: Double, reps: Int)]
        if let segments = set.effortSegments, !segments.isEmpty {
            values = segments.compactMap { segment in
                guard let w = segment.weightKilograms, w.isFinite, w > 0,
                      let reps = segment.reps, reps > 0 else { return nil }
                return (w, reps)
            }
        } else if let w = set.completedWeightKilograms, w.isFinite, w > 0,
                  let reps = set.resolvedCompletedReps, reps > 0 {
            values = [(w, reps)]
        } else {
            values = []
        }
        let weight = values.map { $0.weight }.max()
        let maxEstimate = values.compactMap {
            estimatedOneRepMax(weightKg: $0.weight, reps: $0.reps)
        }.max()
        let met: Bool?
        if let targetWeight = set.plannedWeightKilograms,
           targetWeight.isFinite, targetWeight > 0,
           let targetReps = set.plannedReps, targetReps > 0 {
            met = !values.isEmpty &&
                (set.resolvedCompletedReps ?? 0) >= targetReps &&
                values.allSatisfy { $0.weight >= targetWeight }
        } else {
            met = nil
        }
        return SetEvidence(
            actualWeight: weight,
            actualReps: set.resolvedCompletedReps,
            estimatedOneRepMax: maxEstimate,
            metPlannedTarget: met
        )
    }
}

