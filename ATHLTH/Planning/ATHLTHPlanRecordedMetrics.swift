import Foundation

/// A deliberately narrow comparison of recorded vs prescribed work.
/// Never assumes that a manually completed session has measured duration
/// or distance. Values are paired by the same explicitly identified workout.
@MainActor
enum ATHLTHPlanRecordedMetrics {
    struct Paired: Equatable {
        var planned: Double = 0
        var actual: Double = 0
        var sessions: Int = 0

        /// Actual minus planned, using only directly paired sessions.
        var difference: Double { actual - planned }

        mutating func append(planned: Double, actual: Double) {
            self.planned += planned
            self.actual += actual
            sessions += 1
        }

        mutating func merge(_ other: Paired) {
            planned += other.planned
            actual += other.actual
            sessions += other.sessions
        }
    }

    struct Week: Identifiable {
        let id: UUID
        let number: Int
        let runningMinutes: Paired
        let strengthMinutes: Paired
        let runningKilometers: Paired
    }

    struct Report {
        let weeks: [Week]
        let runningMinutes: Paired
        let strengthMinutes: Paired
        let runningKilometers: Paired

        var comparableWeeks: [Week] {
            weeks.filter {
                $0.runningMinutes.sessions > 0 ||
                $0.strengthMinutes.sessions > 0 ||
                $0.runningKilometers.sessions > 0
            }
        }

        var hasComparisons: Bool {
            !comparableWeeks.isEmpty
        }
    }

    static func inspect(
        plan: TrainingPlan,
        store: AppSessionStore,
        healthWorkouts: [WorkoutSummary],
        strengthHistory: [StrengthWorkoutLog]
    ) -> Report {
        var healthByID: [UUID: WorkoutSummary] = [:]
        for health in healthWorkouts {
            healthByID[health.id] = health
        }
        var strengthBySession: [UUID: StrengthWorkoutLog] = [:]
        for log in strengthHistory where log.isFinished {
            guard let sessionID = log.plannedSessionID else { continue }
            if let older = strengthBySession[sessionID] {
                if (log.endedAt ?? log.startedAt) >
                    (older.endedAt ?? older.startedAt) {
                    strengthBySession[sessionID] = log
                }
            } else {
                strengthBySession[sessionID] = log
            }
        }

        var seenSessionIDs = Set<UUID>()
        var weeks: [Week] = []
        var totalRunningTime = Paired()
        var totalStrengthTime = Paired()
        var totalRunningDistance = Paired()

        for week in plan.weeks.sorted(by: { $0.weekNumber < $1.weekNumber }) {
            var runningMinutes = Paired()
            var strengthMinutes = Paired()
            var runningKilometers = Paired()

            for workout in week.days.flatMap(\.sessions) {
                guard seenSessionIDs.insert(workout.id).inserted,
                      workout.kind == .running || workout.kind == .strength,
                      !store.isPlanSessionSkipped(planID: plan.id, sessionID: workout.id),
                      store.isPlanSessionCompleted(
                          planID: plan.id,
                          sessionID: workout.id,
                          healthWorkouts: healthWorkouts,
                          strengthHistory: strengthHistory
                      ) else { continue }

                let linkedHealth: WorkoutSummary?
                if let healthID = store.linkedHealthWorkoutID(
                    planID: plan.id, sessionID: workout.id
                ),
                   let record = healthByID[healthID],
                   (workout.kind == .running && record.activity == .running) ||
                   (workout.kind == .strength && record.activity == .strength) {
                    linkedHealth = record
                } else {
                    linkedHealth = nil
                }

                let strengthLog = workout.kind == .strength
                    ? strengthBySession[workout.id] : nil
                let measuredSeconds: Double?
                if let linkedHealth,
                   validPositive(linkedHealth.duration) {
                    measuredSeconds = linkedHealth.duration
                } else if let strengthLog {
                    if let duration = strengthLog.healthMetrics.duration,
                       validPositive(duration) {
                        measuredSeconds = duration
                    } else if let endedAt = strengthLog.endedAt,
                              validPositive(endedAt.timeIntervalSince(strengthLog.startedAt)) {
                        // Elapsed strength-log time may include pauses.
                        measuredSeconds = endedAt.timeIntervalSince(strengthLog.startedAt)
                    } else {
                        measuredSeconds = nil
                    }
                } else {
                    measuredSeconds = nil
                }

                if let plannedMinutes = workout.durationMinutes,
                   plannedMinutes > 0,
                   let measuredSeconds {
                    if workout.kind == .running {
                        runningMinutes.append(
                            planned: Double(plannedMinutes),
                            actual: measuredSeconds / 60
                        )
                    } else {
                        strengthMinutes.append(
                            planned: Double(plannedMinutes),
                            actual: measuredSeconds / 60
                        )
                    }
                }

                if workout.kind == .running,
                   let targetKm = workout.targetDistanceKilometers,
                   validPositive(targetKm),
                   let meters = linkedHealth?.distanceMeters,
                   validPositive(meters) {
                    runningKilometers.append(
                        planned: targetKm, actual: meters / 1000
                    )
                }
            }

            let result = Week(
                id: week.id,
                number: week.weekNumber,
                runningMinutes: runningMinutes,
                strengthMinutes: strengthMinutes,
                runningKilometers: runningKilometers
            )
            weeks.append(result)
            totalRunningTime.merge(runningMinutes)
            totalStrengthTime.merge(strengthMinutes)
            totalRunningDistance.merge(runningKilometers)
        }

        return Report(
            weeks: weeks,
            runningMinutes: totalRunningTime,
            strengthMinutes: totalStrengthTime,
            runningKilometers: totalRunningDistance
        )
    }

    private static func validPositive(_ value: Double) -> Bool {
        value.isFinite && value > 0
    }
}
