import Foundation

/// Personalized, conservative suggestions derived from known plan + Health
/// signals only. Never rewrites a user's plan or infers injury/medical status.
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

        var kind: WorkoutKind? {
            switch self {
            case .planned: return nil
            case .easyWalk: return .walking
            case .easyRun: return .running
            }
        }
        var durationMinutes: Int? {
            switch self {
            case .planned: return nil
            case .easyWalk(let minutes), .easyRun(let minutes): return minutes
            }
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
        plannedWorkoutTitle: String? = nil
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
            switch readiness {
            case .ready:
                return tr(
                    "Available recovery measurements look positive today. Check how your body feels during the warm-up.",
                    "Tilgjengelige restitusjonsmålinger ser gode ut i dag. Kjenn etter hvordan kroppen føles under oppvarmingen."
                )
            case .balanced:
                return tr(
                    "Recovery measurements look balanced. Moderate activity may fit well today.",
                    "Restitusjonsmålingene ser balanserte ut. Moderat aktivitet kan passe fint i dag."
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
                "Comfortable pace without hard intervals.",
                "Behagelig tempo uten harde intervaller."
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
                destination: .training
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
