import Foundation

/// Longitudinal review of the *planned* program. Uses the same week
/// classifications as ATHLTHPlanWeekBalanceAdvisor; does not interpret
/// session count as physiological training load or change active sessions.
enum ATHLTHPlanProgramTrendAdvisor {
    struct Week: Identifiable {
        let id: UUID
        let number: Int
        let running: Int
        let strength: Int
        let other: Int
        let plannedMinutes: Int?
        let plannedRunKilometers: Double?
        let deload: Bool
        let comparison: Comparison?

        var sessionCount: Int { running + strength + other }
    }

    enum Comparison: Equatable {
        case higher(Int)
        case lower(Int)
        case unchanged
        case noBaseline
    }

    struct Report {
        let weeks: [Week]
        let totalSessions: Int
        let totalRuns: Int
        let totalStrength: Int
        let totalOther: Int
        let knownTotalMinutes: Int
        let weeksWithUnknownTime: Int
        let totalRunKilometers: Double?
        let largestIncrease: Int?
        let isSingleWeek: Bool

        var maximumWeekSessions: Int {
            max(weeks.map(\.sessionCount).max() ?? 0, 1)
        }
    }

    static func inspect(_ plan: TrainingPlan) -> Report {
        let ordered = plan.weeks.sorted { $0.weekNumber < $1.weekNumber }
        var preceding: Week?
        var largestIncrease: Int?
        var weeks: [Week] = []
        var totalRunKilometers = 0.0
        var hasUnknownRunDistance = false

        for week in ordered {
            let balance = ATHLTHPlanWeekBalanceAdvisor.inspect(week)
            let running = week.days
                .flatMap(\.sessions)
                .filter { $0.kind == .running }
            let distances = running.compactMap { workout -> Double? in
                guard let value = workout.targetDistanceKilometers,
                      value.isFinite, value > 0 else { return nil }
                return value
            }
            if distances.count != running.count {
                hasUnknownRunDistance = true
            }
            let runKilometers = distances.count == running.count
                ? distances.reduce(0, +)
                : nil
            totalRunKilometers += distances.reduce(0, +)

            let comparison: Comparison?
            if let preceding, week.weekNumber == preceding.number + 1 {
                let difference = balance.sessionCount - preceding.sessionCount
                if difference > 0 {
                    comparison = .higher(difference)
                    largestIncrease = max(largestIncrease ?? 0, difference)
                } else if difference < 0 {
                    comparison = .lower(-difference)
                } else {
                    comparison = .unchanged
                }
            } else {
                // Missing or out-of-order week numbers are not comparable.
                comparison = .noBaseline
            }

            let row = Week(
                id: week.id,
                number: week.weekNumber,
                running: balance.runningCount,
                strength: balance.strengthCount,
                other: balance.otherCount,
                plannedMinutes: balance.completePlannedMinutes,
                plannedRunKilometers: runKilometers,
                deload: week.strengthPhase == .deload,
                comparison: comparison
            )
            weeks.append(row)
            preceding = row
        }

        return Report(
            weeks: weeks,
            totalSessions: weeks.reduce(0) { $0 + $1.sessionCount },
            totalRuns: weeks.reduce(0) { $0 + $1.running },
            totalStrength: weeks.reduce(0) { $0 + $1.strength },
            totalOther: weeks.reduce(0) { $0 + $1.other },
            knownTotalMinutes: weeks.compactMap(\.plannedMinutes).reduce(0, +),
            weeksWithUnknownTime: weeks.filter { $0.plannedMinutes == nil && $0.sessionCount > 0 }.count,
            totalRunKilometers: hasUnknownRunDistance ? nil : totalRunKilometers,
            largestIncrease: largestIncrease,
            isSingleWeek: weeks.count <= 1
        )
    }
}
