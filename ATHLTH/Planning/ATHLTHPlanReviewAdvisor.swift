import Foundation

/// A deliberately conservative coach for the structure of a saved plan.
/// Findings are review prompts, not automatic modifications or medical advice.
/// Only future scheduled workouts are candidates for editing suggestions.
enum ATHLTHPlanReviewAdvisor {
    enum Kind: String, Hashable {
        case missingDuration
        case longDay
        case mixedDay
        case consecutiveRuns
        case consecutiveStrength
        case crowdedWeek
        case increasingFrequency
    }

    struct Suggestion: Identifiable, Equatable {
        let kind: Kind
        let weekID: UUID
        let weekNumber: Int
        let dayID: UUID?
        let title: String
        let detail: String
        let priority: Int

        var id: String {
            "\(kind.rawValue)-\(weekID)-\(dayID?.uuidString ?? "week")"
        }
    }

    static func inspect(
        _ plan: TrainingPlan,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> [Suggestion] {
        // Do not guess dates for imported templates without a start.
        guard let startDate = plan.startDate else { return [] }

        let start = calendar.startOfDay(for: startDate)
        let today = calendar.startOfDay(for: referenceDate)
        var suggestions: [Suggestion] = []
        var previousWeekSessions: Int?
        var previousWeekNumber: Int?
        var seenWorkoutIDs = Set<UUID>()

        for (offset, week) in plan.weeks.enumerated() {
            let report = ATHLTHPlanWeekBalanceAdvisor.inspect(week)
            let weekStart = calendar.date(
                byAdding: .day, value: offset * 7, to: start
            ) ?? start
            let weekEnd = calendar.date(
                byAdding: .day, value: 6, to: weekStart
            ) ?? weekStart

            if let previousWeekSessions,
               let previousWeekNumber,
               week.weekNumber == previousWeekNumber + 1,
               weekEnd >= today,
               report.sessionCount - previousWeekSessions >= 2 {
                let increase = report.sessionCount - previousWeekSessions
                suggestions.append(Suggestion(
                    kind: .increasingFrequency,
                    weekID: week.id,
                    weekNumber: week.weekNumber,
                    dayID: nil,
                    title: ATHLTHLocalization.choose(
                        english: "Review the frequency increase",
                        norwegian: "Vurder økningen i antall økter"
                    ),
                    detail: ATHLTHLocalization.choose(
                        english: "Week \(week.weekNumber) has \(increase) more scheduled workouts than the previous week. Check that the mix and time requirements fit your goals; session count is not training load.",
                        norwegian: "Uke \(week.weekNumber) har \(increase) flere planlagte økter enn forrige uke. Sjekk at fordelingen og tidsbruken passer målene dine. Antall økter er ikke treningsbelastning."
                    ),
                    priority: 2
                ))
            }
            previousWeekSessions = report.sessionCount
            previousWeekNumber = week.weekNumber

            for day in week.days where (1...7).contains(day.dayIndex) {
                let fallbackDate = calendar.date(
                    byAdding: .day,
                    value: day.dayIndex - 1,
                    to: weekStart
                ) ?? weekStart
                let upcoming = day.sessions.filter { workout in
                    let scheduled = calendar.startOfDay(
                        for: workout.scheduledStart ?? fallbackDate
                    )
                    return scheduled >= today &&
                        seenWorkoutIDs.insert(workout.id).inserted
                }
                if upcoming.contains(where: { ($0.durationMinutes ?? 0) <= 0 }) {
                    suggestions.append(Suggestion(
                        kind: .missingDuration,
                        weekID: week.id,
                        weekNumber: week.weekNumber,
                        dayID: day.id,
                        title: ATHLTHLocalization.choose(
                            english: "Set a time target",
                            norwegian: "Legg til et tidsmål"
                        ),
                        detail: ATHLTHLocalization.choose(
                            english: "At least one upcoming workout in week \(week.weekNumber), day \(day.dayIndex), has no valid duration. Open the day and choose a realistic duration before training.",
                            norwegian: "Minst én kommende økt i uke \(week.weekNumber), dag \(day.dayIndex), mangler gyldig varighet. Åpne dagen og velg en realistisk varighet før trening."
                        ),
                        priority: 1
                    ))
                }
            }

            for finding in report.findings {
                guard let day = week.days.first(where: {
                    $0.dayIndex == finding.dayIndex
                }) else { continue }
                let plannedDate = calendar.date(
                    byAdding: .day,
                    value: day.dayIndex - 1,
                    to: weekStart
                ) ?? weekStart
                guard plannedDate >= today else { continue }

                let kind: Kind
                let priority: Int
                switch finding.kind {
                case .longDay:
                    kind = .longDay
                    priority = 1
                case .consecutiveRuns:
                    kind = .consecutiveRuns
                    priority = 2
                case .consecutiveStrength:
                    kind = .consecutiveStrength
                    priority = 2
                case .crowdedWeek:
                    kind = .crowdedWeek
                    priority = 2
                case .mixedDay:
                    kind = .mixedDay
                    priority = 3
                }
                suggestions.append(Suggestion(
                    kind: kind,
                    weekID: week.id,
                    weekNumber: week.weekNumber,
                    dayID: day.id,
                    title: finding.title,
                    detail: finding.detail,
                    priority: priority
                ))
            }
        }

        return suggestions.sorted {
            if $0.priority != $1.priority {
                return $0.priority < $1.priority
            }
            if $0.weekNumber != $1.weekNumber {
                return $0.weekNumber < $1.weekNumber
            }
            return $0.id < $1.id
        }
    }
}
