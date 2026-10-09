import Foundation

/// A local, deterministic and opt-in recovery advisor.
/// No health information leaves the device; this engine never writes a plan.
enum ATHLTHTrainRecoveryAdvisor {
    enum Signal: Hashable {
        case lowSelfReportedEnergy
        case lowRecentReadiness
        case denseRecentStrengthTraining
    }

    struct Proposal: Identifiable {
        var id: UUID { workoutID }
        let workoutID: UUID
        let workoutTitle: String
        let scheduledDay: Date
        let signals: [Signal]
        let beforeWorkingSets: Int
        let afterWorkingSets: Int
        let beforeWeight: Double?
        let afterWeight: Double?
        let proposedSession: PlannedSession

        var hasChanges: Bool {
            beforeWorkingSets != afterWorkingSets ||
                beforeWeight != afterWeight
        }
    }

    /// Only a *real* existing planned strength workout, scheduled for today
    /// or tomorrow, may receive an actionable suggestion. Other activity
    /// types receive no fabricated prescriptions.
    static func proposals(
        plan: TrainingPlan,
        completedIDs: Set<UUID>,
        skippedIDs: Set<UUID>,
        strengthHistory: [StrengthWorkoutLog],
        selfReportedEnergy: Int?,
        readiness: RecoveryReadinessSummary?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [Proposal] {
        guard let start = plan.startDate else { return [] }
        let today = calendar.startOfDay(for: now)
        let recentSessions = Set(strengthHistory.filter {
            $0.isFinished &&
                ($0.endedAt ?? $0.startedAt) <= now &&
                now.timeIntervalSince($0.endedAt ?? $0.startedAt) <= 72 * 3600
        }.map(\.id))

        var signals: [Signal] = []
        if let energy = selfReportedEnergy, (1...5).contains(energy), energy <= 2 {
            signals.append(.lowSelfReportedEnergy)
        }
        if let readiness, readiness.baselineDays >= 5, readiness.score != nil,
           readiness.state == .recover || readiness.state == .takeItEasy {
            signals.append(.lowRecentReadiness)
        }
        if recentSessions.count >= 3 {
            signals.append(.denseRecentStrengthTraining)
        }
        guard !signals.isEmpty else { return [] }

        var output: [Proposal] = []
        for (weekIndex, week) in plan.weeks.enumerated() {
            for day in week.days {
                guard let date = calendar.date(
                    byAdding: .day,
                    value: weekIndex * 7 + day.dayIndex - 1,
                    to: calendar.startOfDay(for: start)
                ), date >= today,
                   let latest = calendar.date(byAdding: .day, value: 1, to: today),
                   date <= latest else { continue }
                for workout in day.sessions where workout.kind == .strength {
                    guard !completedIDs.contains(workout.id),
                          !skippedIDs.contains(workout.id),
                          workout.recoveryAdjustedAt == nil else { continue }
                    guard let adapted = lighterStrengthSession(workout) else { continue }
                    let beforeSets = workingSets(in: workout)
                    let afterSets = workingSets(in: adapted)
                    let beforeWeight = peakWorkingLoad(in: workout)
                    let afterWeight = peakWorkingLoad(in: adapted)
                    output.append(Proposal(
                        workoutID: workout.id,
                        workoutTitle: workout.title,
                        scheduledDay: date,
                        signals: signals,
                        beforeWorkingSets: beforeSets,
                        afterWorkingSets: afterSets,
                        beforeWeight: beforeWeight,
                        afterWeight: afterWeight,
                        proposedSession: adapted
                    ))
                }
            }
        }
        return output
    }

    /// A modest example adjustment for athlete review, not a physiological
    /// claim. Reduce working sets ~25%, preserving at least one, and reduce
    /// positive prescribed working loads by 10% (rounded to nearest 0.5 kg).
    static func lighterStrengthSession(_ original: PlannedSession) -> PlannedSession? {
        guard original.kind == .strength,
              original.recoveryAdjustedAt == nil else { return nil }
        var proposed = original
        for index in proposed.exercises.indices {
            var exercise = proposed.exercises[index]
            if exercise.hasIndividualSetTargets {
                let current = exercise.resolvedSetTargets
                let working = current.filter {
                    $0.isWarmUp != true && $0.setType != .warmUp
                }
                guard !working.isEmpty else { continue }
                let desiredCount = max(1, Int((Double(working.count) * 0.75).rounded()))
                var kept = 0
                var reduced: [PlannedExerciseSetTarget] = []
                for target in current {
                    let isWarmup = target.isWarmUp == true || target.setType == .warmUp
                    if !isWarmup {
                        guard kept < desiredCount else { continue }
                        kept += 1
                    }
                    var updated = target
                    if !isWarmup, exercise.resolvedLoadKind == .weightKilograms,
                       let oldWeight = updated.weightKilograms, oldWeight > 0,
                       oldWeight.isFinite {
                        updated.weightKilograms = roundedLoad(oldWeight * 0.9)
                    }
                    reduced.append(updated)
                }
                exercise.setTargets = reduced
                exercise.sets = reduced.count
                if let workingLoad = reduced.first(where: {
                    $0.isWarmUp != true && $0.setType != .warmUp
                })?.weightKilograms, workingLoad > 0 {
                    exercise.targetWeightKilograms = workingLoad
                }
            } else {
                exercise.sets = max(1, Int((Double(max(exercise.sets, 1)) * 0.75).rounded()))
                if exercise.resolvedLoadKind == .weightKilograms,
                   let oldWeight = exercise.targetWeightKilograms,
                   oldWeight > 0, oldWeight.isFinite {
                    exercise.targetWeightKilograms = roundedLoad(oldWeight * 0.9)
                }
            }
            proposed.exercises[index] = exercise
        }
        guard proposed.exercises != original.exercises else { return nil }
        // The original remains available for an exact one-tap reversal.
        proposed.recoveryOriginalExercises = original.exercises
        proposed.recoveryAdjustedExercises = proposed.exercises
        proposed.recoveryAdjustedAt = Date()
        return proposed
    }

    static func workingSets(in session: PlannedSession) -> Int {
        session.exercises.reduce(0) { partial, exercise in
            partial + (exercise.hasIndividualSetTargets
                ? exercise.resolvedSetTargets.filter {
                    $0.isWarmUp != true && $0.setType != .warmUp
                  }.count
                : max(exercise.sets, 0))
        }
    }

    static func peakWorkingLoad(in session: PlannedSession) -> Double? {
        let loads = session.exercises.flatMap { exercise -> [Double] in
            guard exercise.resolvedLoadKind == .weightKilograms else { return [] }
            if exercise.hasIndividualSetTargets {
                return exercise.resolvedSetTargets.filter {
                    $0.isWarmUp != true && $0.setType != .warmUp
                }.compactMap(\.weightKilograms).filter {
                    $0.isFinite && $0 > 0
                }
            }
            return exercise.targetWeightKilograms.map { [$0] } ?? []
        }
        return loads.max()
    }

    private static func roundedLoad(_ value: Double) -> Double {
        max(0, (value * 2).rounded() / 2)
    }
}
