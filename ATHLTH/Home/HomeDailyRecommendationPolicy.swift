import Foundation

/// Training suggestions grounded in recorded activity and available Health signals.
/// Readiness is not proof of fitness. No plan changes or inferred medical status.
enum HomeDailyRecommendationPolicy {
    enum Readiness: Equatable {
        case ready, balanced, takeItEasy, recover, unavailable
    }

    enum Destination: Equatable {
        case insights, training
    }

    enum PlannedActivity: Equatable {
        case running, strength, other
    }

    enum SuggestedWorkout: Equatable {
        case planned
        case easyWalk(minutes: Int)
        case easyRun(minutes: Int)
        case progressiveRun(minutes: Int)
        case tempoRun(minutes: Int)

        var kind: WorkoutKind? {
            switch self {
            case .planned: return nil
            case .easyWalk: return .walking
            case .easyRun, .progressiveRun, .tempoRun: return .running
            }
        }
        var durationMinutes: Int? {
            switch self {
            case .planned: return nil
            case .easyWalk(let minutes), .easyRun(let minutes),
                 .progressiveRun(let minutes), .tempoRun(let minutes):
                return minutes
            }
        }
    }


    /// A training-history signal, not a fitness diagnosis. Missing workouts
    /// mean that we cannot justify prescribing harder running.
    struct TrainingHistory: Equatable {
        let sessionsLast28Days: Int
        let runsLast28Days: Int
        let mostRecentRunDaysAgo: Int?
        let averageRecentRunMinutes: Int?
        var hasCompletedWorkoutToday: Bool = false

        static let empty = TrainingHistory(
            sessionsLast28Days: 0,
            runsLast28Days: 0,
            mostRecentRunDaysAgo: nil,
            averageRecentRunMinutes: nil
        )

        static func from(
            workouts: [WorkoutSummary],
            now: Date = Date(),
            calendar: Calendar = .current
        ) -> TrainingHistory {
            let start = calendar.date(
                byAdding: .day, value: -28,
                to: calendar.startOfDay(for: now)
            ) ?? now.addingTimeInterval(-28 * 86_400)
            let recent = workouts.filter {
                $0.startDate >= start &&
                $0.startDate <= now &&
                $0.duration.isFinite &&
                $0.duration >= 5 * 60
            }
            let runs = recent.filter { $0.activity == .running }
            let lastRun = runs.map(\.startDate).max()
            let daysAgo = lastRun.map {
                max(0, calendar.dateComponents(
                    [.day],
                    from: calendar.startOfDay(for: $0),
                    to: calendar.startOfDay(for: now)
                ).day ?? 28)
            }
            let average = runs.isEmpty ? nil : Int(
                (runs.reduce(0) { $0 + $1.duration } /
                 Double(runs.count) / 60).rounded()
            )
            return TrainingHistory(
                sessionsLast28Days: recent.count,
                runsLast28Days: runs.count,
                mostRecentRunDaysAgo: daysAgo,
                averageRecentRunMinutes: average,
                hasCompletedWorkoutToday: recent.contains {
                    calendar.isDate($0.startDate, inSameDayAs: now)
                }
            )
        }

        var hasRecentRunningExperience: Bool {
            runsLast28Days >= 1 &&
            (mostRecentRunDaysAgo ?? 100) <= 14 &&
            (averageRecentRunMinutes ?? 0) >= 20
        }

        var supportsControlledTempo: Bool {
            runsLast28Days >= 3 &&
            (2...10).contains(mostRecentRunDaysAgo ?? 100) &&
            (averageRecentRunMinutes ?? 0) >= 30
        }
    }

    struct Advice {
        let dayDescription: String
        let suggestedWorkout: SuggestedWorkout
        let suggestedTitle: String
        let suggestedDetail: String
        let title: String
        let detail: String
        let source: String
        let symbol: String
        let destination: Destination
        /// Real comparison, omitted if the baseline is absent.
        let evidence: String?

        init(title: String, detail: String, source: String,
             symbol: String, destination: Destination,
             evidence: String? = nil,
             dayDescription: String = "",
             suggestedWorkout: SuggestedWorkout = .easyWalk(minutes: 20),
             suggestedTitle: String = "",
             suggestedDetail: String = "") {
            self.dayDescription = dayDescription
            self.suggestedWorkout = suggestedWorkout
            self.suggestedTitle = suggestedTitle
            self.suggestedDetail = suggestedDetail
            self.title = title
            self.detail = detail
            self.source = source
            self.symbol = symbol
            self.destination = destination
            self.evidence = evidence
        }
    }

    static func recommendation(
        readiness: Readiness,
        hasWorkoutToday: Bool,
        trainingLoadRatio: Double?,
        plannedActivity: PlannedActivity? = nil,
        plannedWorkoutTitle: String? = nil,
        trainingHistory: TrainingHistory = .empty
    ) -> Advice {
        func tr(_ en: String, _ no: String) -> String {
            ATHLTHLocalization.choose(english: en, norwegian: no)
        }

        // A load *ratio* means recent minutes relative to a personal baseline.
        // Never use the raw ratio as a clinical fatigue or injury indicator.
        let ratio = trainingLoadRatio.flatMap { value in
            value.isFinite && value >= 0 && value <= 20 ? value : nil
        }
        let loadEvidence: String? = ratio.map { value in
            let change = Int(((value - 1) * 100).rounded())
            return tr(
                "Training minutes \(change >= 0 ? "+" : "")\(change)% vs 4-week average",
                "Treningsminutter \(change >= 0 ? "+" : "")\(change) % mot 4-ukers snitt"
            )
        }

        let recoveryPriority = readiness == .recover ||
            readiness == .takeItEasy || (ratio ?? 0) >= 1.5

        // Conservative recovery suggestions take precedence over a hard
        // scheduled session. The existing plan remains unchanged.
        let suggestedWorkout: SuggestedWorkout
        if recoveryPriority {
            suggestedWorkout = .easyWalk(
                minutes: readiness == .recover ? 15 : 20
            )
        } else if hasWorkoutToday, plannedWorkoutTitle != nil {
            suggestedWorkout = .planned
        } else if trainingHistory.hasCompletedWorkoutToday {
            // A readiness score must not prescribe a second demanding
            // session on a day with an already completed workout.
            suggestedWorkout = .easyWalk(minutes: 20)
        } else if readiness == .ready, trainingHistory.supportsControlledTempo {
            // A good readiness score alone never triggers tempo. Require
            // repeated recent running and a modest historic duration.
            suggestedWorkout = .tempoRun(minutes: 35)
        } else if (readiness == .ready || readiness == .balanced),
                  trainingHistory.hasRecentRunningExperience {
            suggestedWorkout = .progressiveRun(minutes: 30)
        } else if readiness == .ready {
            suggestedWorkout = .easyRun(minutes: 25)
        } else {
            suggestedWorkout = .easyWalk(minutes: 20)
        }

        let dayDescription: String = {
            if readiness == .recover {
                return tr(
                    "Recovery indicators suggest a quieter day. Listen to your body and rest if needed.",
                    "Restitusjonsmålingene tyder på at en roligere dag kan passe. Kjenn etter og hvil ved behov."
                )
            }
            if readiness == .takeItEasy {
                return tr(
                    "Readiness is lower than usual. Prioritize an easy session and check how you feel.",
                    "Dagsformen ser lavere ut enn vanlig. Prioriter en lett økt og kjenn etter."
                )
            }
            if (ratio ?? 0) >= 1.5 {
                return tr(
                    "Your recent training minutes are above your usual level. A lighter day can help balance the load.",
                    "Du har trent mer enn ditt vanlige nivå i det siste. En roligere dag kan balansere belastningen."
                )
            }
            if trainingHistory.hasCompletedWorkoutToday,
               suggestedWorkout != .planned {
                return tr(
                    "You already completed a workout today. Leave room for recovery before the next demanding session.",
                    "Du har allerede trent i dag. Gi kroppen tid til å hente seg inn før neste krevende økt."
                )
            }
            if suggestedWorkout == .planned {
                return tr(
                    "Today's planned workout is ready. Use your recovery indicators and warm-up to adjust the effort.",
                    "Dagens planlagte økt ligger klar. Bruk restitusjonsmålingene og oppvarmingen til å tilpasse innsatsen."
                )
            }
            switch readiness {
            case .ready:
                if suggestedWorkout == .tempoRun(minutes: 35) {
                    return tr(
                        "Recovery looks good and recent runs show a running base. A controlled tempo session can give you a little more challenge.",
                        "Gode restitusjonssignaler og flere løpeøkter gir grunnlag for litt mer intensitet. Prøv en kontrollert tempoøkt."
                    )
                }
                if case .progressiveRun = suggestedWorkout {
                    return tr(
                        "Your recovery looks good. You have some recent running behind you, so you can gradually raise the pace today.",
                        "Restitusjonen ser god ut. Du har løpt nylig, så i dag kan du øke tempoet gradvis uten å gå rett på hardøkter."
                    )
                }
                return tr(
                    "Recovery looks positive, but recent running history is limited. Start easy and build up when your body responds well.",
                    "Restitusjonen ser god ut, men vi har begrenset løpegrunnlag. Bygg deg gradvis opp og kjenn etter under oppvarmingen."
                )
            case .balanced:
                if case .progressiveRun = suggestedWorkout {
                    return tr(
                        "Readiness is balanced, and your recent runs support some variation. Start easy and finish a little faster if it feels right.",
                        "Dagsformen er balansert, og du har løpt nylig. Start rolig og øk litt mot slutten hvis kroppen svarer bra."
                    )
                }
                return tr(
                    "Recovery looks balanced. Maintain your routine with manageable effort today.",
                    "Restitusjonen ser balansert ut. Hold treningsrytmen i gang med en overkommelig økt i dag."
                )
            case .unavailable:
                return tr(
                    "Reliable recovery data is missing today. Start gently and adjust to how you feel.",
                    "Vi mangler sikre restitusjonsdata i dag. Start rolig og tilpass etter hvordan du føler deg."
                )
            case .recover, .takeItEasy:
                return tr("Take it easy today.", "Ta det rolig i dag.")
            }
        }()

        let suggestedTitle: String
        let suggestedDetail: String
        switch suggestedWorkout {
        case .planned:
            suggestedTitle = plannedWorkoutTitle ?? tr(
                "Planned workout", "Planlagt økt"
            )
            suggestedDetail = tr(
                "Open this session and start it with the usual workout engine.",
                "Åpne denne økten og start med den vanlige øktmotoren."
            )
        case .easyWalk(let minutes):
            suggestedTitle = tr(
                "Easy walk · \(minutes) min", "Rolig gåtur · \(minutes) min"
            )
            suggestedDetail = tr(
                "Relaxed walking at a comfortable pace.",
                "Rolig gange i et behagelig tempo."
            )
        case .easyRun(let minutes):
            suggestedTitle = tr(
                "Easy run · \(minutes) min", "Rolig løpetur · \(minutes) min"
            )
            suggestedDetail = tr(
                "Conversational pace; evaluate after the warm-up.",
                "Pratefart; vurder dagsformen etter oppvarming."
            )
        case .progressiveRun(let minutes):
            suggestedTitle = tr(
                "Progressive run · \(minutes) min",
                "Progressiv løpetur · \(minutes) min"
            )
            suggestedDetail = tr(
                "8 min easy · 17 min steady · 5 min easy (RPE 5).",
                "8 min rolig · 17 min jevnt · 5 min rolig (RPE 5)."
            )
        case .tempoRun(let minutes):
            suggestedTitle = tr(
                "Controlled tempo · \(minutes) min",
                "Kontrollert tempo · \(minutes) min"
            )
            suggestedDetail = tr(
                "8 min easy · 3 × 5 min tempo · 8 min cool-down.",
                "8 min rolig · 3 × 5 min tempo · 8 min nedjogg."
            )
        }

        func makeAdvice(
            title: String, detail: String, source: String,
            symbol: String, destination: Destination,
            evidence: String? = nil
        ) -> Advice {
            Advice(
                title: title, detail: detail, source: source,
                symbol: symbol, destination: destination, evidence: evidence,
                dayDescription: dayDescription,
                suggestedWorkout: suggestedWorkout,
                suggestedTitle: suggestedTitle,
                suggestedDetail: suggestedDetail
            )
        }

        func lighterSessionTitle() -> String {
            switch plannedActivity {
            case .running:
                return tr("Choose an easy run", "Velg en rolig løpetur")
            case .strength:
                return tr("Reduce strength volume", "Reduser styrkevolumet")
            case .other, .none:
                return hasWorkoutToday
                    ? tr("Adjust today's workout", "Tilpass dagens økt")
                    : tr("Take an active recovery day", "Velg aktiv restitusjon")
            }
        }

        func lighterSessionDetail() -> String {
            switch plannedActivity {
            case .running:
                return tr("Consider 20–30 min at conversational pace. Skip hard efforts.",
                          "Vurder 20–30 min i pratefart. Dropp harde drag.")
            case .strength:
                return tr("Consider 1–2 fewer sets and lighter weights today.",
                          "Vurder 1–2 færre sett og lettere vekter i dag.")
            case .other:
                return tr("Keep the planned workout short and comfortable.",
                          "Hold den planlagte økten kort og behagelig.")
            case .none:
                return tr("Try a gentle 20–30 min walk if it feels right.",
                          "Prøv en rolig gåtur på 20–30 min hvis det passer.")
            }
        }

        // Low readiness takes priority over a seemingly normal training load.
        if readiness == .recover || readiness == .takeItEasy {
            return makeAdvice(
                title: lighterSessionTitle(),
                detail: lighterSessionDetail(),
                source: tr("Based on readiness", "Basert på dagsform"),
                symbol: "leaf",
                destination: .insights,
                evidence: (ratio ?? 0) >= 1.5 ? loadEvidence : nil
            )
        }

        if let ratio, ratio >= 1.5 {
            return makeAdvice(
                title: lighterSessionTitle(),
                detail: lighterSessionDetail(),
                source: tr("Based on recent training", "Basert på treningsbelastning"),
                symbol: plannedActivity == .strength ? "dumbbell" : "chart.bar.xaxis",
                destination: .insights,
                evidence: loadEvidence
            )
        }

        switch readiness {
        case .ready:
            return makeAdvice(
                title: hasWorkoutToday
                    ? tr("Your planned session fits", "Dagens økt kan passe")
                    : tr("Ready for movement", "Klar for bevegelse"),
                detail: hasWorkoutToday
                    ? tr("Start as planned. Check how you feel during the warm-up.",
                         "Start som planlagt. Kjenn etter under oppvarmingen.")
                    : tr("Try 20–30 min walking or a comfortable run.",
                         "Prøv 20–30 min gange eller rolig løping."),
                source: tr("Based on readiness", "Basert på dagsform"),
                symbol: "sparkles",
                destination: .training,
                evidence: (ratio ?? 1) < 0.85 &&
                    trainingHistory.hasRecentRunningExperience
                    ? loadEvidence : nil
            )
        case .balanced:
            return makeAdvice(
                title: hasWorkoutToday
                    ? tr("Keep today's intensity steady", "Hold jevn intensitet")
                    : tr("Build a steady habit", "Bygg en jevn vane"),
                detail: hasWorkoutToday
                    ? tr("Warm up gently, then follow the plan at a comfortable effort.",
                         "Varm rolig opp og følg planen med behagelig innsats.")
                    : tr("Try 20–30 min easy activity today.",
                         "Prøv 20–30 min rolig aktivitet i dag."),
                source: tr("Based on readiness", "Basert på dagsform"),
                symbol: "figure.walk",
                destination: .training
            )
        case .unavailable:
            return makeAdvice(
                title: hasWorkoutToday
                    ? tr("Start with a gentle warm-up", "Start med rolig oppvarming")
                    : tr("Try a short walk", "Prøv en kort gåtur"),
                detail: hasWorkoutToday
                    ? tr("No reliable readiness data. Use the warm-up to adjust today's plan.",
                         "Mangler sikre dagsformdata. Tilpass økten under oppvarmingen.")
                    : tr("Try 15–20 min easy walking. No readiness estimate is available.",
                         "Prøv 15–20 min rolig gange. Dagsformdata mangler."),
                source: hasWorkoutToday
                    ? tr("Based on your plan", "Basert på planen")
                    : tr("General suggestion", "Generelt forslag"),
                symbol: hasWorkoutToday ? "calendar" : "figure.walk",
                destination: .training
            )
        case .recover, .takeItEasy:
            // Already handled above.
            return makeAdvice(
                title: lighterSessionTitle(),
                detail: lighterSessionDetail(),
                source: tr("Based on readiness", "Basert på dagsform"),
                symbol: "leaf",
                destination: .insights
            )
        }
    }
}
