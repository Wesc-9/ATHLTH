import Foundation

/// A transparent, read-only scheduling review. It intentionally does not
/// infer recovery, injury risk, heart-rate zones or exercise intensity when
/// the plan doesn't contain enough data. It never mutates the plan.
enum ATHLTHPlanWeekBalanceAdvisor {
    struct Finding: Identifiable, Equatable {
        enum Kind: String {
            case mixedDay
            case consecutiveRuns
            case consecutiveStrength
            case crowdedWeek
            case longDay
        }

        let kind: Kind
        let dayIndex: Int
        let title: String
        let detail: String

        var id: String { "\(kind.rawValue)-\(dayIndex)" }
    }

    struct Report {
        let weekNumber: Int
        let runningCount: Int
        let strengthCount: Int
        let otherCount: Int
        let scheduledDays: Int
        let knownDurationMinutes: Int
        let sessionsWithoutDuration: Int
        let findings: [Finding]

        var sessionCount: Int {
            runningCount + strengthCount + otherCount
        }

        /// Display as a complete total only when all sessions have a duration.
        var completePlannedMinutes: Int? {
            sessionsWithoutDuration == 0 ? knownDurationMinutes : nil
        }
    }

    static func inspect(_ week: TrainingPlanWeek) -> Report {
        let ordered = week.days.sorted { $0.dayIndex < $1.dayIndex }
        let allSessions = ordered.flatMap(\.sessions)
        let runs = allSessions.filter { $0.kind == .running }
        let strength = allSessions.filter { $0.kind == .strength }
        let knownMinutes = allSessions.compactMap { workout -> Int? in
            guard let value = workout.durationMinutes, value > 0 else {
                return nil
            }
            return value
        }

        let runDays = Set(ordered.filter { $0.sessions.contains(where: { $0.kind == .running }) }.map(\.dayIndex))
        let strengthDays = Set(ordered.filter { $0.sessions.contains(where: { $0.kind == .strength }) }.map(\.dayIndex))
        let activeDays = Set(ordered.filter { day in
            day.sessions.contains { $0.kind == .running || $0.kind == .strength }
        }.map(\.dayIndex))

        var findings: [Finding] = []

        for day in ordered where (1...7).contains(day.dayIndex) {
            let runCount = day.sessions.filter { $0.kind == .running }.count
            let strengthCount = day.sessions.filter { $0.kind == .strength }.count

            if runCount > 0 && strengthCount > 0 {
                findings.append(Finding(
                    kind: .mixedDay,
                    dayIndex: day.dayIndex,
                    title: ATHLTHLocalization.choose(
                        english: "Running and strength on the same day",
                        norwegian: "Løping og styrke på samme dag"
                    ),
                    detail: ATHLTHLocalization.choose(
                        english: "Consider whether you have enough time and whether the order fits your goal. This combination is not necessarily a problem.",
                        norwegian: "Vurder om du har nok tid, og om rekkefølgen passer målet. Kombinasjonen er ikke nødvendigvis et problem."
                    )
                ))
            }

            // Only present exact time totals when *all* sessions on this day
            // have a valid planned duration; never fill missing minutes.
            if !day.sessions.isEmpty,
               day.sessions.allSatisfy({ ($0.durationMinutes ?? 0) > 0 }) {
                let total = day.sessions.compactMap(\.durationMinutes).reduce(0, +)
                if total >= 150 {
                    findings.append(Finding(
                        kind: .longDay,
                        dayIndex: day.dayIndex,
                        title: ATHLTHLocalization.choose(
                            english: "A long training day",
                            norwegian: "En lang treningsdag"
                        ),
                        detail: ATHLTHLocalization.choose(
                            english: "\(total) minutes are scheduled. Check your time budget and the sessions' purpose.",
                            norwegian: "\(total) minutter er planlagt. Kontroller tidsbudsjettet og formålet med øktene."
                        )
                    ))
                }
            }
        }

        // Check only runs that can actually be identified as running;
        // do not classify mobility, walking or custom sessions as hard work.
        for (set, kind, minimum) in [
            (runDays, Finding.Kind.consecutiveRuns, 3),
            (strengthDays, Finding.Kind.consecutiveStrength, 3),
            (activeDays, Finding.Kind.crowdedWeek, 5)
        ] {
            var streak = 0
            var reported = false
            for index in 1...7 {
                if set.contains(index) {
                    streak += 1
                    if streak >= minimum && !reported {
                        let title: String
                        let detail: String
                        switch kind {
                        case .consecutiveRuns:
                            title = ATHLTHLocalization.choose(
                                english: "Running on consecutive days",
                                norwegian: "Løping flere dager på rad"
                            )
                            detail = ATHLTHLocalization.choose(
                                english: "Check that the run sessions have different purposes. Intensity cannot be determined from a running label alone.",
                                norwegian: "Kontroller at løpeøktene har ulike formål. Intensitet kan ikke avgjøres av at en økt er merket løping."
                            )
                        case .consecutiveStrength:
                            title = ATHLTHLocalization.choose(
                                english: "Strength on consecutive days",
                                norwegian: "Styrke flere dager på rad"
                            )
                            detail = ATHLTHLocalization.choose(
                                english: "Review which muscles are trained on these days. Different muscle groups can be intentional.",
                                norwegian: "Se over hvilke muskelgrupper som trenes. Ulike muskelgrupper kan være helt tilsiktet."
                            )
                        case .crowdedWeek:
                            title = ATHLTHLocalization.choose(
                                english: "Several training days in a row",
                                norwegian: "Mange treningsdager på rad"
                            )
                            detail = ATHLTHLocalization.choose(
                                english: "Check whether this run of training days matches your available time and preferences.",
                                norwegian: "Vurder om treningsdagene samsvarer med tid og ønsker."
                            )
                        default:
                            continue
                        }
                        findings.append(Finding(
                            kind: kind,
                            dayIndex: index,
                            title: title,
                            detail: detail
                        ))
                        reported = true
                    }
                } else {
                    streak = 0
                    reported = false
                }
            }
        }

        return Report(
            weekNumber: week.weekNumber,
            runningCount: runs.count,
            strengthCount: strength.count,
            otherCount: allSessions.count - runs.count - strength.count,
            scheduledDays: ordered.filter { !$0.sessions.isEmpty }.count,
            knownDurationMinutes: knownMinutes.reduce(0, +),
            sessionsWithoutDuration: allSessions.count - knownMinutes.count,
            findings: findings.sorted {
                $0.dayIndex == $1.dayIndex
                    ? $0.kind.rawValue < $1.kind.rawValue
                    : $0.dayIndex < $1.dayIndex
            }
        )
    }
}
