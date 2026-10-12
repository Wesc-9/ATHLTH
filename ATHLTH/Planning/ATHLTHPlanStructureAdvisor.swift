import Foundation

/// Lightweight, deterministic structure checks for a persisted training plan.
/// Not a sports-science or medical assessment: it never modifies workouts.
enum ATHLTHPlanStructureAdvisor {
    struct Finding: Identifiable, Hashable {
        enum Severity: String, Hashable {
            case attention
            case information
        }
        let id: String
        let title: String
        let detail: String
        let severity: Severity
        let symbol: String
    }

    static func inspect(_ plan: TrainingPlan) -> [Finding] {
        var findings: [Finding] = []
        var knownSessionIDs = Set<UUID>()
        var duplicateIDs = 0
        var hasSessions = false

        for week in plan.weeks {
            let dayIndices = week.days.map(\.dayIndex)
            if Set(dayIndices).count != dayIndices.count ||
                dayIndices.contains(where: { !(1...7).contains($0) }) {
                findings.append(Finding(
                    id: "days-\(week.id)",
                    title: ATHLTHLocalization.choose(
                        english: "Check the days in week \(week.weekNumber)",
                        norwegian: "Kontroller dagene i uke \(week.weekNumber)"
                    ),
                    detail: ATHLTHLocalization.choose(
                        english: "This week has duplicated or unrecognized day positions.",
                        norwegian: "Uken har dupliserte eller ukjente dagplasseringer."
                    ),
                    severity: .attention,
                    symbol: "calendar.badge.exclamationmark"
                ))
            }

            let weekSessions = week.days.reduce(0) { $0 + $1.sessions.count }
            hasSessions = hasSessions || weekSessions > 0

            for day in week.days {
                if day.sessions.count >= 3 {
                    findings.append(Finding(
                        id: "busy-\(week.id)-\(day.id)",
                        title: ATHLTHLocalization.choose(
                            english: "Several workouts on one day",
                            norwegian: "Flere økter på samme dag"
                        ),
                        detail: ATHLTHLocalization.choose(
                            english: "Week \(week.weekNumber): \(day.sessions.count) workouts on day \(day.dayIndex). Check the time and recovery between workouts.",
                            norwegian: "Uke \(week.weekNumber): \(day.sessions.count) økter på dag \(day.dayIndex). Kontroller tidsbruk og pauser mellom øktene."
                        ),
                        severity: .information,
                        symbol: "calendar.badge.clock"
                    ))
                }

                for workout in day.sessions {
                    if !knownSessionIDs.insert(workout.id).inserted {
                        duplicateIDs += 1
                    }
                    if workout.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        findings.append(Finding(
                            id: "title-\(workout.id)",
                            title: ATHLTHLocalization.choose(
                                english: "Workout without a name",
                                norwegian: "Økt uten navn"
                            ),
                            detail: ATHLTHLocalization.choose(
                                english: "Give the workout a clear name so it is easy to recognize later.",
                                norwegian: "Gi økten et tydelig navn så den er enkel å finne igjen."
                            ),
                            severity: .attention,
                            symbol: "pencil.line"
                        ))
                    }
                    if let minutes = workout.durationMinutes, minutes <= 0 {
                        findings.append(Finding(
                            id: "duration-\(workout.id)",
                            title: ATHLTHLocalization.choose(
                                english: "Invalid planned duration",
                                norwegian: "Ugyldig planlagt varighet"
                            ),
                            detail: ATHLTHLocalization.choose(
                                english: "This workout has a duration of zero or less.",
                                norwegian: "Denne økten har en varighet på null eller mindre."
                            ),
                            severity: .attention,
                            symbol: "timer"
                        ))
                    }
                }
            }
        }

        if duplicateIDs > 0 {
            findings.insert(Finding(
                id: "duplicate-session-identities",
                title: ATHLTHLocalization.choose(
                    english: "Some workouts share an identifier",
                    norwegian: "Noen økter deler samme identitet"
                ),
                detail: ATHLTHLocalization.choose(
                    english: "Workout IDs must be unique to reliably connect your plan, Apple Watch and recorded activities.",
                    norwegian: "Økt-ID-er må være unike for å koble plan, Apple Watch og registrerte aktiviteter riktig."
                ),
                severity: .attention,
                symbol: "link.badge.plus"
            ), at: 0)
        }

        if !hasSessions {
            findings.append(Finding(
                id: "empty-plan",
                title: ATHLTHLocalization.choose(
                    english: "No workouts scheduled yet",
                    norwegian: "Ingen økter planlagt ennå"
                ),
                detail: ATHLTHLocalization.choose(
                    english: "Choose a week and day to add your first workout.",
                    norwegian: "Velg en uke og dag for å legge til din første økt."
                ),
                severity: .information,
                symbol: "calendar.badge.plus"
            ))
        }

        return findings
    }
}
